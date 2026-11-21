"""Generic retailer spiders for the scraper service (SFR-022).

Two strategies, used by services/scraper/main.py:
  - Shopify JSON  (/collections/<slug>/products.json) for brands with a working API
  - BeautifulSoup HTML parsing for html_only brands and as a low-yield fallback

Category filtering is strict: a product is kept only if it matches the exact
requested category and does not conflict with it (shared/taxonomy.py).
"""

import re
import uuid
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from shared.audience import is_kids_item
from shared.brands import BrandConfig
from shared.config import settings
from shared.taxonomy import product_conflicts_with_category, product_matches_category
from services.scraper.schema import (
    _extract_colors,
    _extract_sizes,
    _normalize_image_url,
    _parse_price,
    _parse_price_text,
)

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

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
        handle = item.get("handle") or ""

        # ── ADULTS ONLY (men and women 18+) ──
        if is_kids_item(title, tags, product_type, f"/products/{handle}",
                        _extract_sizes(item.get("variants") or [])):
            continue

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

        # ── ADULTS ONLY (men and women 18+) ──
        if is_kids_item(title, [], collection_slug.replace("-", " "), product_url):
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
