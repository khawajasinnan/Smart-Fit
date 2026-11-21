"""Re-check one catalog product at its brand's own store.

The scheduled refresh keeps each brand's newest products and removes the rest
(spec §10), so a product a user saved or was shown earlier can be missing from
the catalog although the brand still sells it. Try-on then asks here: the
product is fetched from the store (Shopify's public /products/<handle>.js,
the same data the feed has, allowed by robots.txt), checked by the same
parser as the refresh (adult clothing, in stock, has a price and a photo),
and saved back to the catalog.

Only brands in FEED_BRANDS are ever contacted: the product id names the brand
("outfitters:<handle>"), so no caller-chosen URL is fetched.
"""

from __future__ import annotations

import logging
import re
from datetime import UTC, datetime
from typing import Literal

import httpx

from shared.feed_brands import FEED_BRANDS, FeedBrand
from shared.schemas.catalog import ScrapedProduct
from services.scraper.catalog import (
    FEED_PAGE_SIZE,
    MAX_FEED_PAGES,
    FeedRateLimited,
    attach_size_charts,
    get_feed_page,
    parse_shopify_product,
)
from services.scraper.polite import PoliteClient, RobotsDisallowed

logger = logging.getLogger("smartfit.scraper.lookup")

LookupStatus = Literal["available", "gone", "sold_out", "not_clothing", "unknown_brand", "unreachable"]

_HANDLE = re.compile(r"^[a-z0-9][a-z0-9\-_.]{0,199}$", re.IGNORECASE)
_BRANDS: dict[str, FeedBrand] = {b.key: b for b in FEED_BRANDS}


def split_product_id(product_id: str) -> tuple[FeedBrand, str] | None:
    """("outfitters:f0566-303") -> (Outfitters, "f0566-303"); None if it isn't a feed brand's product."""
    key, sep, handle = product_id.partition(":")
    brand = _BRANDS.get(key)
    if not sep or brand is None or not _HANDLE.match(handle):
        return None
    return brand, handle


def feed_item_from_js(data: dict) -> dict:
    """Shopify's /products/<handle>.js in the /products.json feed's shape:
    prices are in paisa there, images are "//cdn..." strings, the type is "type"."""

    def price(v: dict) -> str | None:
        try:
            return f"{int(v.get('price')) / 100:.2f}"
        except (TypeError, ValueError):
            return None

    images = []
    for src in data.get("images") or []:
        if isinstance(src, str) and src:
            images.append({"src": "https:" + src if src.startswith("//") else src})
    return {
        "title": data.get("title"),
        "handle": data.get("handle"),
        "tags": data.get("tags") or [],
        "product_type": data.get("type") or "",
        "images": images,
        "options": [{"name": o.get("name")} if isinstance(o, dict) else {"name": o}
                    for o in data.get("options") or []],
        "variants": [
            {"option1": v.get("option1"), "option2": v.get("option2"), "option3": v.get("option3"),
             "available": bool(v.get("available")), "price": price(v)}
            for v in data.get("variants") or []
        ],
    }


async def _store_item(polite: PoliteClient, brand: FeedBrand, handle: str) -> dict | None:
    """The product in the feed's item shape, or None if the store doesn't have it.
    Raises on network problems / unexpected answers (-> "unreachable")."""
    res = await polite.get(f"{brand.base_url}/products/{handle}.js", headers={"Accept": "application/json"})
    is_json = "json" in res.headers.get("content-type", "") or "javascript" in res.headers.get("content-type", "")
    if res.status_code == 200 and is_json:
        data = res.json()
        if not isinstance(data, dict):
            raise ValueError("unexpected product data")
        return feed_item_from_js(data)
    if res.status_code == 404 and "json" in res.headers.get("content-type", ""):
        return None  # Shopify's own "no such product"
    if res.status_code not in (200, 404):
        raise RuntimeError(f"HTTP {res.status_code}")
    # A custom (headless) storefront without /products/<handle>.js (e.g. Cougar):
    # look for the handle in its /products.json feed, the same pages the refresh reads.
    for page in range(1, MAX_FEED_PAGES + 1):
        data = await get_feed_page(polite, f"{brand.base_url}/products.json?limit={FEED_PAGE_SIZE}&page={page}")
        items = data.get("products") or []
        for item in items:
            if item.get("handle") == handle:
                return item
        if len(items) < FEED_PAGE_SIZE:
            break
    return None


# parse_shopify_product's skip reasons -> what the app is told
_SKIP_STATUS: dict[str, LookupStatus] = {
    "out_of_stock": "sold_out",
    "no_price": "sold_out",
}


async def lookup_product(client: httpx.AsyncClient, product_id: str) -> tuple[ScrapedProduct | None, LookupStatus]:
    """(product, "available") when the brand still sells it; otherwise (None, why)."""
    parsed = split_product_id(product_id)
    if parsed is None:
        return None, "unknown_brand"
    brand, handle = parsed
    polite = PoliteClient(client)
    try:
        item = await _store_item(polite, brand, handle)
    except (RobotsDisallowed, FeedRateLimited, RuntimeError, ValueError, httpx.HTTPError) as exc:
        logger.warning("Couldn't check %s at %s: %s", product_id, brand.name, exc)
        return None, "unreachable"
    if item is None:
        return None, "gone"
    product, skip = parse_shopify_product(item, brand, datetime.now(UTC))
    if product is None:
        return None, _SKIP_STATUS.get(skip, "not_clothing")
    if product.product_id != product_id:  # the store redirected to another product
        return None, "gone"
    products = [product]
    try:
        await attach_size_charts(polite, brand, products)
    except Exception as exc:  # the fit check copes without a chart
        logger.warning("Size chart for %s: %s", product_id, type(exc).__name__)
    return products[0], "available"
