"""BeautifulSoup fallback for HTML scraping.

Used when Shopify JSON is empty, blocked, or for html_only brands.
Applies strict category filtering only when an exact_category is set.
"""

from __future__ import annotations

import re
import uuid
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from core.config import settings
from services.brands import BrandConfig
from services.query_builder import (
    product_conflicts_with_category,
    product_matches_category,
)

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)


def _parse_price_text(text: str) -> int | None:
    # Remove currency symbols, spaces, commas and extract the number
    cleaned = re.sub(r"[^\d]", "", text)
    if cleaned:
        return int(cleaned)
    return None


def _normalize_image_url(raw: str | None, base_url: str) -> str | None:
    if not raw:
        return None
    first = raw.split(",")[0].strip().split(" ")[0]
    if not first:
        return None
    if first.startswith("//"):
        return "https:" + first
    return urljoin(base_url, first)


async def scrape_collection_html(
    client: httpx.AsyncClient,
    brand: BrandConfig,
    collection_slug: str,
    exact_category: str | None,
    limit: int,
) -> list[dict]:
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

    # Broad CSS selectors to capture product cards across Shopify themes
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

        # Try to find product title
        title_el = card.find(class_=re.compile(
            r"card__heading|product-title|title|product-name|card__name"
        ))
        title = (
            title_el.get_text(strip=True)
            if title_el
            else card.get("title") or card.get("aria-label") or ""
        )
        # Fallback: try the first text content of the card
        if not title or len(title) < 3:
            title = card.get_text(strip=True)[:100]
        if not title or len(title) < 3:
            continue

        # ── STRICT CATEGORY FILTER (only when exact_category is set) ──
        if exact_category:
            category_label = collection_slug.replace("-", " ")
            if not product_matches_category(title, [], category_label, exact_category):
                continue
            if product_conflicts_with_category(title, [], exact_category):
                continue

        # Extract image
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

        # Extract price
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
