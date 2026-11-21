"""Manual catalog import (spec §10 fallback), used for Breakout, and the same
validation for products an admin adds or edits (SFR-040).

Breakout has no product feed, so products are collected by hand into a CSV
and validated here before entering the catalog. Template:
backend/services/scraper/templates/manual_catalog_template.csv

Columns (header row required):
  name, product_url, image_url, extra_image_urls, price, sizes_in_stock,
  all_sizes, category, tryon_category, gender, colors
Lists (extra_image_urls, sizes, colors) are separated with "|".
"""

from __future__ import annotations

import csv
import io
from datetime import UTC, datetime
from urllib.parse import urlparse

from pydantic import ValidationError

from shared.feed_brands import FEED_BRANDS
from shared.schemas.catalog import ScrapedProduct

# retailer key -> product-page host: every feed brand, plus Breakout (CSV only)
RETAILER_HOSTS = {
    **{b.key: urlparse(b.base_url).hostname for b in FEED_BRANDS},
    "breakout": "www.breakout.com.pk",
}
MANUAL_RETAILERS = {"breakout": RETAILER_HOSTS["breakout"]}  # retailers imported by CSV
ALLOWED_IMAGE_HOSTS = {"cdn.shopify.com", *RETAILER_HOSTS.values()}
REQUIRED_COLUMNS = {"name", "product_url", "image_url", "price", "sizes_in_stock", "category", "tryon_category", "gender"}


def _list(value) -> list[str]:
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    return [v.strip() for v in (value or "").split("|") if v.strip()]


def _https_on(url: str, hosts: set[str]) -> bool:
    p = urlparse(url)
    return p.scheme == "https" and (p.hostname or "").lower() in hosts


def product_from_fields(
    fields: dict, retailer: str, source: str, scraped_at: datetime | None = None
) -> tuple[ScrapedProduct | None, str | None]:
    """(product, None) or (None, reason). `fields` uses the CSV column names;
    list fields may be "|"-separated strings or lists."""
    if retailer not in RETAILER_HOSTS:
        return None, f"unknown retailer '{retailer}'"
    page_host = RETAILER_HOSTS[retailer]
    url = str(fields.get("product_url") or "").strip()
    parsed = urlparse(url)
    if not _https_on(url, {page_host}) or not parsed.path.startswith("/products/"):
        return None, f"product_url must be https://{page_host}/products/<handle>"
    handle = parsed.path.removeprefix("/products/").strip("/")
    if not handle or "/" in handle:
        return None, f"product_url must be https://{page_host}/products/<handle>"

    image = str(fields.get("image_url") or "").strip()
    extras = _list(fields.get("extra_image_urls"))
    if any(not _https_on(u, ALLOWED_IMAGE_HOSTS) for u in [image, *extras]):
        return None, f"image URLs must be https on {', '.join(sorted(ALLOWED_IMAGE_HOSTS))}"
    try:
        price = float(str(fields.get("price") or "").replace(",", ""))
    except ValueError:
        return None, "price must be a number (PKR)"

    in_stock = _list(fields.get("sizes_in_stock"))
    try:
        product = ScrapedProduct(
            product_id=f"{retailer}:{handle}",
            retailer=retailer,
            name=str(fields.get("name") or "").strip(),
            product_url=f"https://{page_host}/products/{handle}",
            image_url=image,
            image_urls=[image, *extras],
            price=price,
            sizes=in_stock,
            all_sizes=_list(fields.get("all_sizes")) or in_stock,
            category=str(fields.get("category") or "").strip().lower(),
            tryon_category=str(fields.get("tryon_category") or "").strip().lower(),
            gender=str(fields.get("gender") or "").strip().lower(),
            colors=_list(fields.get("colors")),
            source=source,
            scraped_at=scraped_at or datetime.now(UTC),
        )
    except ValidationError as exc:
        return None, "invalid " + ", ".join(str(e["loc"][0]) for e in exc.errors())
    if not product.name or not product.category:
        return None, "name and category are required"
    return product, None


def parse_manual_csv(text: str, retailer: str) -> tuple[list[ScrapedProduct], list[str]]:
    """(valid products, human-readable problems with row numbers)."""
    if retailer not in MANUAL_RETAILERS:
        return [], [f"Unknown retailer '{retailer}'. Known: {', '.join(MANUAL_RETAILERS)}"]
    reader = csv.DictReader(io.StringIO(text.lstrip("﻿")))
    missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
    if missing:
        return [], [f"Missing columns: {', '.join(sorted(missing))}"]

    products: list[ScrapedProduct] = []
    problems: list[str] = []
    seen: set[str] = set()
    scraped_at = datetime.now(UTC)
    for row_no, row in enumerate(reader, start=2):  # row 1 is the header
        product, problem = product_from_fields(row, retailer, "manual_csv", scraped_at)
        if problem:
            problems.append(f"row {row_no}: {problem}")
            continue
        if product.product_id in seen:
            problems.append(f"row {row_no}: duplicate product {product.product_id.split(':', 1)[1]}")
            continue
        seen.add(product.product_id)
        products.append(product)
    return products, problems
