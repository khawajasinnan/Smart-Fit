"""Fetch products from Shopify-based Pakistani retailers via public JSON endpoints.

Applies strict category filtering so only products matching the user's exact
garment request are returned.  Query keyword matching is now relaxed — the
category filter is the primary gate; we only use query matching as a *bonus*
signal, never as a hard reject.
"""

from __future__ import annotations

import re
import uuid

import httpx

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


def _parse_price(value: str | int | float | None) -> int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    digits = re.sub(r"[^\d.]", "", str(value))
    if not digits:
        return None
    return int(float(digits))


def _extract_sizes(variants: list[dict]) -> list[str]:
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


async def fetch_shopify_collection(
    client: httpx.AsyncClient,
    brand: BrandConfig,
    collection_slug: str,
    query: str,
    exact_category: str | None,
    limit: int,
) -> list[dict]:
    """Fetch and filter products from a single Shopify collection.

    The category filter is the primary gate.  We do NOT hard-reject products
    based on query keywords — that was causing valid products to be dropped.
    """
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

        # ── STRICT CATEGORY FILTER (primary gate) ──
        if exact_category:
            if not product_matches_category(title, tags, product_type, exact_category):
                continue
            if product_conflicts_with_category(title, tags, exact_category):
                continue

        # NOTE: We no longer hard-reject based on query keywords.
        # The recommendation engine scoring handles relevance ranking.

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
            continue  # skip products without a handle (broken URLs)

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
    timeout = httpx.Timeout(settings.scrape_request_timeout)
    all_products: list[dict] = []

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        for brand in brands:
            # Skip brands that are HTML-only (their JSON API is blocked)
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
