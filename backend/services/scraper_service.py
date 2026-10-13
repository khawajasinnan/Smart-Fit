"""Orchestrates scraping from multiple Pakistani fashion brands.

Consolidates both Shopify JSON and BeautifulSoup HTML parsing into a single
unified, optimized module to eliminate extra files and duplicate code.

Uses asyncio.gather for concurrent brand scraping:
  - Shopify JSON for brands with working JSON APIs
  - HTML scraping for html_only brands AND as fallback for low yield

KEY FEATURE: Brand selection is now category-aware.
When user asks for "pent coat", only brands that stock Western formal suits
(Cambridge, Charcoal, Edenrobe, Royal Tag, Uniworth) are queried.
Kurta/shalwar brands (Nishat, J., Khaadi) are NEVER queried for pent coat.
"""

import asyncio
import logging
import re
import uuid
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from core.config import settings
from models.schemas import (
    ProductRecommendation,
    ScrapeRecommendRequest,
    ScrapeRecommendResponse,
    UserProfileInput,
)
from services.brands import PAKISTANI_BRANDS, BrandConfig, normalize_gender
from services.local_catalog import local_products
from services.query_builder import (
    build_search_context,
    product_conflicts_with_category,
    product_matches_category,
    gender_garment_conflict,
)
from services.recommendation_engine import rank_products

logger = logging.getLogger("smartfit.scraper")

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

# ──────────────────────────────────────────────────────────────────────────────
# UTILITIES & PARSERS
# ──────────────────────────────────────────────────────────────────────────────

def _parse_price_text(text: str) -> int | None:
    """Remove currency symbols, spaces, commas and extract the integer price."""
    cleaned = re.sub(r"[^\d]", "", text)
    if cleaned:
        return int(cleaned)
    return None


def _parse_price(value: str | int | float | None) -> int | None:
    """Parse numeric price from Shopify JSON variant data."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    digits = re.sub(r"[^\d.]", "", str(value))
    if not digits:
        return None
    return int(float(digits))


def _normalize_image_url(raw: str | None, base_url: str) -> str | None:
    """Normalize and format raw image URLs harvested from HTML source."""
    if not raw:
        return None
    first = raw.split(",")[0].strip().split(" ")[0]
    if not first:
        return None
    if first.startswith("//"):
        return "https:" + first
    return urljoin(base_url, first)


def _extract_sizes(variants: list[dict]) -> list[str]:
    """Extract and sort available sizing configurations from Shopify variants."""
    sizes: list[str] = []
    for v in variants:
        title = (v.get("title") or "").strip()
        if title and title.lower() != "default title":
            sizes.append(title.split(" / ")[0].strip())
    return sorted(set(sizes))[:12]


def _extract_colors(variants: list[dict], tags: list[str]) -> list[str]:
    """Try to extract color info from variant options or tags."""
    colors: set[str] = set()
    color_keywords = {
        "black", "white", "navy", "blue", "red", "green", "beige", "cream",
        "brown", "maroon", "pink", "purple", "grey", "gray", "olive", "mustard",
        "teal", "gold", "silver", "peach", "coral", "burgundy", "emerald",
        "charcoal", "sky blue", "royal blue", "off white", "ivory", "rust",
        "lavender", "mint", "sage", "plum", "yellow", "orange", "khaki",
    }
    for v in variants:
        title = (v.get("title") or "").lower()
        for c in color_keywords:
            if c in title:
                colors.add(c)
    for tag in tags:
        tag_lower = tag.lower().strip()
        if tag_lower in color_keywords:
            colors.add(tag_lower)
    return sorted(colors)[:4]


# ──────────────────────────────────────────────────────────────────────────────
# SHOPIFY JSON SCRAPER
# ──────────────────────────────────────────────────────────────────────────────

async def fetch_shopify_collection(
    client: httpx.AsyncClient,
    brand: BrandConfig,
    collection_slug: str,
    query: str,
    exact_category: str | None,
    limit: int,
) -> list[dict]:
    """Fetch and filter products from a single Shopify collection."""
    url = f"{brand.base_url}/collections/{collection_slug}/products.json"
    try:
        response = await client.get(
            url,
            params={"limit": min(limit * 4, 80)},  # fetch more to filter
            headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        )
        if response.status_code != 200:
            return []
        data = response.json()
    except (httpx.HTTPError, ValueError):
        return []

    products: list[dict] = []
    for item in data.get("products") or []:
        title = item.get("title") or ""
        tags = item.get("tags") or []
        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(",")]

        product_type = item.get("product_type") or collection_slug.replace("-", " ")

        # ── STRICT CATEGORY FILTER ──
        if exact_category:
            if not product_matches_category(title, tags, product_type, exact_category):
                continue
            if product_conflicts_with_category(title, tags, exact_category):
                continue

        variants = item.get("variants") or []
        price = None
        for v in variants:
            if v.get("available"):
                price = _parse_price(v.get("price"))
                break
        if price is None and variants:
            price = _parse_price(variants[0].get("price"))

        handle = item.get("handle") or ""
        if not handle:
            continue

        image = None
        images = item.get("images") or []
        if images:
            image = images[0].get("src")
        if not image and item.get("image"):
            image = item["image"].get("src")

        colors = _extract_colors(variants, tags)

        products.append(
            {
                "id": str(item.get("id") or uuid.uuid4()),
                "brand": brand.name,
                "title": title,
                "category": product_type,
                "price_pkr": price,
                "currency": "PKR",
                "image_url": image,
                "product_url": f"{brand.base_url}/products/{handle}",
                "sizes": _extract_sizes(variants),
                "colors": colors,
                "tags": tags if isinstance(tags, list) else [],
                "in_stock": any(v.get("available") for v in variants) if variants else True,
            }
        )
        if len(products) >= limit:
            break

    return products


async def scrape_brands_shopify(
    brands: list[BrandConfig],
    gender: str,
    query: str,
    exact_category: str | None,
    max_per_brand: int,
) -> list[dict]:
    """Scrape registered Shopify collections concurrently."""
    timeout = httpx.Timeout(settings.scrape_request_timeout)
    all_products: list[dict] = []

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        for brand in brands:
            if brand.html_only:
                continue

            slugs = brand.collection_slugs.get(gender) or brand.collection_slugs.get(
                "unisex", []
            )
            brand_products: list[dict] = []
            for slug in slugs[:4]:  # try up to 4 collection slugs
                batch = await fetch_shopify_collection(
                    client, brand, slug, query, exact_category, max_per_brand
                )
                brand_products.extend(batch)
                if len(brand_products) >= max_per_brand:
                    break
            all_products.extend(brand_products[:max_per_brand])

    return all_products


# ──────────────────────────────────────────────────────────────────────────────
# BEAUTIFULSOUP HTML SCRAPER
# ──────────────────────────────────────────────────────────────────────────────

async def scrape_collection_html(
    client: httpx.AsyncClient,
    brand: BrandConfig,
    collection_slug: str,
    exact_category: str | None,
    limit: int,
) -> list[dict]:
    """Fallback parser that scrapes and parses standard Shopify HTML templates."""
    url = f"{brand.base_url}/collections/{collection_slug}"
    try:
        response = await client.get(
            url,
            headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
        )
        if response.status_code != 200:
            return []
        soup = BeautifulSoup(response.text, "lxml")
    except (httpx.HTTPError, ValueError):
        return []

    products: list[dict] = []
    seen_urls: set[str] = set()

    selectors = [
        "a[href*='/products/']",
        ".card-wrapper a",
        ".product-card a",
        "hdt-card a",
        ".product-item a",
        ".collection-product a",
        ".grid-product a",
        ".product-list a",
    ]
    selector_string = ", ".join(selectors)

    for card in soup.select(selector_string):
        href = card.get("href") or ""
        if "/products/" not in href:
            continue
        product_url = urljoin(brand.base_url, href.split("?")[0])
        if product_url in seen_urls:
            continue
        seen_urls.add(product_url)

        title_el = card.find(class_=re.compile(
            r"card__heading|product-title|title|product-name|card__name"
        ))
        title = (
            title_el.get_text(strip=True)
            if title_el
            else card.get("title") or card.get("aria-label") or ""
        )
        if not title or len(title) < 3:
            title = card.get_text(strip=True)[:100]
        if not title or len(title) < 3:
            continue

        # ── STRICT CATEGORY FILTER ──
        if exact_category:
            category_label = collection_slug.replace("-", " ")
            if not product_matches_category(title, [], category_label, exact_category):
                continue
            if product_conflicts_with_category(title, [], exact_category):
                continue

        img = card.find("img")
        image_url = None
        if img:
            image_url = _normalize_image_url(
                img.get("src")
                or img.get("data-src")
                or img.get("data-original")
                or img.get("srcset")
                or img.get("data-srcset"),
                brand.base_url,
            )

        price_el = card.find(class_=re.compile(r"price|money|amount"))
        price_pkr = _parse_price_text(price_el.get_text()) if price_el else None

        products.append(
            {
                "id": str(uuid.uuid4()),
                "brand": brand.name,
                "title": title,
                "category": collection_slug.replace("-", " "),
                "price_pkr": price_pkr,
                "currency": "PKR",
                "image_url": image_url,
                "product_url": product_url,
                "sizes": [],
                "colors": [],
                "tags": [],
                "in_stock": True,
            }
        )
        if len(products) >= limit:
            break

    return products


async def scrape_brands_html(
    brands: list[BrandConfig],
    gender: str,
    exact_category: str | None,
    limit_per_brand: int,
) -> list[dict]:
    """HTML fallbacks scraping driver."""
    timeout = httpx.Timeout(settings.scrape_request_timeout)
    results: list[dict] = []

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        for brand in brands:
            slugs = brand.collection_slugs.get(gender) or brand.collection_slugs.get(
                "unisex", []
            )
            if not slugs:
                continue
            for slug in slugs[:3]:  # try up to 3 slugs
                batch = await scrape_collection_html(
                    client, brand, slug, exact_category, limit_per_brand
                )
                results.extend(batch)
                if len(results) >= limit_per_brand * len(brands):
                    break

    return results


# ──────────────────────────────────────────────────────────────────────────────
# SCRAPER CORE AND COORDINATION
# ──────────────────────────────────────────────────────────────────────────────

def _select_brands(
    profile: UserProfileInput,
    gender: str,
    exact_category: str | None,
    requested_brands: list[str] | None = None,
) -> list[BrandConfig]:
    """Select brands based on gender AND category strength."""
    candidates: list[BrandConfig] = []
    requested = {b.lower() for b in requested_brands or []}
    for brand in PAKISTANI_BRANDS:
        if requested and brand.name.lower() not in requested:
            continue
        slugs = brand.collection_slugs.get(gender) or brand.collection_slugs.get("unisex", [])
        if not slugs:
            continue

        if exact_category and brand.strengths:
            if exact_category not in brand.strengths:
                logger.debug(
                    "  Skipping %s — no strength for category '%s'",
                    brand.name,
                    exact_category,
                )
                continue

        candidates.append(brand)

    return candidates


async def recommend_products(
    request: ScrapeRecommendRequest,
) -> ScrapeRecommendResponse:
    profile = request.profile
    context = build_search_context(
        profile,
        request.user_message,
        request.assistant_message,
        request.chat_context,
        request.dynamic_prefs,
    )
    gender = context["gender"]
    query = context["search_query"]
    exact_category = context.get("exact_category")
    detected_garment = context.get("detected_garment", query)

    conflict = gender_garment_conflict(gender, exact_category or "") or gender_garment_conflict(gender, detected_garment)
    if conflict:
        return ScrapeRecommendResponse(
            products=[],
            search_query=context.get("search_queries", [""])[0] if context.get("search_queries") else "",
            brands_searched=[],
            stylist_message=conflict["message"] + " Suggested alternatives: " + ", ".join(conflict["alternatives"]) + ".",
        )

    if context.get("invalid_budget"):
        return ScrapeRecommendResponse(
            products=[],
            search_query=query,
            brands_searched=[],
            message=(
                "Budget cannot be a negative amount. Please enter a positive "
                "PKR budget, for example 5000 PKR."
            ),
        )

    brands = _select_brands(
        profile,
        gender,
        exact_category,
        context.get("requested_brands") or [],
    )
    brand_names = [b.name for b in brands]

    shopify_brands = [b for b in brands if not b.html_only]
    html_brands = [b for b in brands if b.html_only]

    logger.info(
        "Scraping %d brands (%d Shopify, %d HTML-only) for gender=%s query='%s' category=%s",
        len(brands), len(shopify_brands), len(html_brands),
        gender, query, exact_category,
    )
    logger.info("  Brands selected: %s", ", ".join(brand_names))

    max_total = min(request.max_products, settings.max_total_products)
    per_brand = max(3, settings.max_products_per_brand)

    # ── Phase 1: Shopify JSON + HTML-only brands in parallel ──
    async def _scrape_shopify_task(brand):
        try:
            batch = await scrape_brands_shopify(
                [brand], gender, query, exact_category, per_brand
            )
            logger.info("  %s (Shopify): %d products", brand.name, len(batch))
            return batch
        except Exception as exc:
            logger.warning("  %s (Shopify) FAILED: %s", brand.name, exc)
            return []

    async def _scrape_html_task(brand):
        try:
            html_batch = await scrape_brands_html(
                [brand], gender, exact_category, per_brand
            )
            logger.info("  %s (HTML): %d products", brand.name, len(html_batch))
            return html_batch
        except Exception as exc:
            logger.warning("  %s (HTML) FAILED: %s", brand.name, exc)
            return []

    all_tasks = []
    all_tasks.extend(_scrape_shopify_task(b) for b in shopify_brands)
    all_tasks.extend(_scrape_html_task(b) for b in html_brands)

    results = await asyncio.gather(*all_tasks)

    raw: list[dict] = []
    for batch in results:
        raw.extend(batch)

    # ── Phase 2: HTML fallback for Shopify brands if yield is still low ──
    if len(raw) < max_total // 2:
        logger.info("Low yield (%d), running HTML fallback for Shopify brands...", len(raw))
        seen = {p["product_url"] for p in raw}

        fallback_tasks = [_scrape_html_task(b) for b in shopify_brands]
        fallback_results = await asyncio.gather(*fallback_tasks)
        for html_batch in fallback_results:
            for item in html_batch:
                if item["product_url"] not in seen:
                    raw.append(item)
                    seen.add(item["product_url"])

    # ── Phase 3: Local catalog fallback (always runs) ──
    seen = {p["product_url"] for p in raw}
    for item in local_products(profile, context, max_total):
        if item["product_url"] not in seen:
            raw.append(item)
            seen.add(item["product_url"])

    logger.info("Total raw products: %d — ranking top %d", len(raw), max_total)
    ranked = rank_products(raw, profile, context, max_total)

    message = (
        f"Found {len(ranked)} items from Pakistani brands matching "
        f'"{detected_garment}" for your profile.'
        if ranked
        else f'No products matched "{detected_garment}" right now. '
        "Try describing a different style, garment, or occasion."
    )

    return ScrapeRecommendResponse(
        products=ranked,
        search_query=query,
        brands_searched=brand_names,
        message=message,
    )
