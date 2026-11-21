"""Catalog fallback for /recommend/app: products already scraped into the
catalog (Supabase `products`, or the local snapshot), filtered for the chat
request. Used when the live keyword search yields few results or the scraper
is down.

Every item is a real scraped product, so `product_url` is the exact product
page (SFR-037) and `id` is the stable catalog product_id. No hand-written
entries: they could only link to collection pages.
"""

from __future__ import annotations

from urllib.parse import urlparse

from services.recommendation.keyword_ranking import product_matches_requested_color
from shared.feed_brands import brand_name
from shared.schemas.catalog import ScrapedProduct
from shared.schemas.recommendation import UserProfileInput
from shared.taxonomy import (
    product_conflicts_with_category,
    product_matches_category,
)

# catalog gender -> the chat search context's gender words
_GENDER_TAG = {"men": "male", "women": "female", "unisex": "unisex"}


def is_product_page(url: str) -> bool:
    """True for an exact product page (https://<shop>/products/<handle>),
    false for home, collection or search pages."""
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    parts = [p for p in parsed.path.split("/") if p]
    return parsed.scheme == "https" and bool(parsed.netloc) and "products" in parts[:-1]


def catalog_item(product: ScrapedProduct) -> dict:
    """A catalog product in the keyword-ranking item shape."""
    words = [w for w in product.category.replace("-", " ").split() if w]
    return {
        "id": product.product_id,
        "brand": brand_name(product.retailer),
        "title": product.name,
        "category": product.category,
        "price_pkr": int(round(product.price)),
        "currency": "PKR",
        "image_url": product.image_url,
        "product_url": product.product_url,
        "sizes": list(product.sizes),
        "all_sizes": list(product.all_sizes),  # made, in stock or not (size check)
        "size_chart": product.size_chart or {},  # the product's own chart (size check)
        "colors": [c.lower() for c in product.colors],
        "tags": [_GENDER_TAG[product.gender], *words, *(c.lower() for c in product.colors)],
        "in_stock": bool(product.sizes),
        "catalog_updated_at": product.scraped_at,
    }


def local_products(
    profile: UserProfileInput,
    context: dict,
    limit: int,
    catalog: list[dict],
) -> list[dict]:
    """Return catalog items that match the requested category.

    Chat-requested color is a hard requirement. Profile colors remain a soft
    ranking signal in the scoring engine.
    """
    gender = context.get("gender", "unisex")
    exact_category = context.get("exact_category")
    budget_max = context.get("budget_max")  # only a budget asked for in this chat filters
    requested_brands = {
        b.lower() for b in (context.get("requested_brands") or []) if isinstance(b, str)
    }
    requested_colors = [
        c.lower().strip()
        for c in (context.get("requested_colors") or [])
        if isinstance(c, str) and c.strip()
    ]
    construction = context.get("construction")
    outfit_context = context.get("outfit_context")

    color_matched: list[dict] = []
    category_matched: list[dict] = []

    for item in catalog:
        if not is_product_page(item.get("product_url") or ""):
            continue

        tags = set(item["tags"])
        tag_text = " ".join(item["tags"]).lower()
        blob = f"{item['title']} {tag_text} {item.get('category') or ''}".lower()

        if requested_brands and item["brand"].lower() not in requested_brands:
            continue

        # Gender filter
        if gender != "unisex" and gender not in tags and "unisex" not in tags:
            continue

        if construction == "unstitched" and "unstitched" not in blob and "fabric" not in blob:
            continue
        if construction == "stitched" and ("unstitched" in blob or "fabric" in blob):
            continue

        if outfit_context == "shalwar-kameez-waistcoat":
            if not (
                ("waistcoat" in blob or "waist coat" in blob or "vest" in blob)
                and any(w in blob for w in ("shalwar", "salwar", "kameez", "qameez", "kurta"))
            ):
                continue

        # ── STRICT CATEGORY FILTER ──
        if exact_category:
            if not product_matches_category(
                item["title"], item["tags"], item.get("category"), exact_category
            ):
                continue
            if product_conflicts_with_category(item["title"], item["tags"], exact_category):
                continue

        # Budget filter (lenient)
        if budget_max and item.get("price_pkr") and item["price_pkr"] > budget_max * 1.5:
            continue

        # Same matcher as the ranking step: "blue" also finds "Indigo Blue", "Navy".
        if requested_colors:
            if not product_matches_requested_color(item, item["title"].lower(), requested_colors):
                continue
            color_matched.append(dict(item))
        else:
            category_matched.append(dict(item))

    # Return color-matched items first, then others
    results = color_matched + category_matched
    return results[:limit]
