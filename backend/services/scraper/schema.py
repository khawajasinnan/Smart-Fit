"""Parsing helpers that turn retailer HTML / Shopify JSON into clean product
fields (price, image URL, sizes, colours). Shared by every spider."""

from __future__ import annotations

import re
from urllib.parse import urljoin

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
