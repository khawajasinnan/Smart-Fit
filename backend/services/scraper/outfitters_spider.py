"""Outfitters (outfitters.com.pk) spider — named in SRDS §1.1 / SFR-022.

Outfitters runs on Shopify, so this delegates to the generic Shopify spider
with Outfitters' collection config from shared/brands.py. Site-specific
tweaks (extra collections, custom parsing) belong here, not in the generic code.
"""

from __future__ import annotations

from shared.brands import PAKISTANI_BRANDS
from services.scraper.generic_spider import scrape_brands_shopify

BRAND = next(b for b in PAKISTANI_BRANDS if b.name == "Outfitters")


async def scrape(gender: str, query: str, exact_category: str | None, max_per_brand: int) -> list[dict]:
    return await scrape_brands_shopify([BRAND], gender, query, exact_category, max_per_brand)
