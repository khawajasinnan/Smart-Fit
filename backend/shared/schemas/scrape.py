"""Contract between the recommendation service (client) and the scraper
service (server): what to scrape, and the raw products found."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ScrapeJob(BaseModel):
    """Search parameters already derived by the recommendation service."""

    gender: str
    query: str = ""
    exact_category: str | None = None
    requested_brands: list[str] = Field(default_factory=list)
    max_total: int = Field(30, ge=1, le=100)


class ScrapeResult(BaseModel):
    """Raw (unranked) product dicts — same keys the ranking engine consumes:
    id, brand, title, category, price_pkr, currency, image_url, product_url,
    sizes, colors, tags, in_stock."""

    products: list[dict[str, Any]] = Field(default_factory=list)
    brands_searched: list[str] = Field(default_factory=list)
