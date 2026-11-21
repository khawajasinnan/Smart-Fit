"""Product catalog (spec §7, §10): what the scraper stores and the
recommendation service ranks. SFR-022 (scrape), SFR-025 (sizes), SFR-037
(exact retailer URL for the "buy" redirect)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field

# A brand key from shared/feed_brands.py (or a manual-import brand), e.g. "bonanza-satrangi".
Retailer = Annotated[str, Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", max_length=40)]
Gender = Literal["men", "women", "unisex"]
TryOnCategory = Literal["upper", "lower", "dress"]


class ScrapedProduct(BaseModel):
    """One retail product. Spec fields: name, image_url, price, sizes,
    category, product_url; the rest supports ranking, try-on and dedup."""

    product_id: str = Field(description='"<retailer>:<handle>", stable across scrapes')
    retailer: Retailer
    name: str
    product_url: str = Field(description="Exact retailer page, kept as scraped (SFR-037)")
    image_url: str = Field(description="Primary image: embedded for ranking, shown in the app")
    image_urls: list[str] = Field(default_factory=list, description="All product images (model shots + flat-lays)")
    price: float = Field(gt=0, description="Lowest in-stock price, PKR")
    currency: Literal["PKR"] = "PKR"
    sizes: list[str] = Field(default_factory=list, description="Sizes in stock right now (SFR-025)")
    all_sizes: list[str] = Field(default_factory=list)
    category: str = Field(description="Retailer's product type, normalised, e.g. 't-shirts'")
    tryon_category: TryOnCategory | None = Field(
        description="Which garment slot virtual try-on repaints; None for unstitched fabric (recommended, "
        "never tried on)")
    gender: Gender
    colors: list[str] = Field(default_factory=list)
    # Product-specific size chart (fit check). size_chart holds only values
    # that could be read as garment circumferences in cm, per size label;
    # size_chart_raw is the chart exactly as published, for display.
    size_chart_tag: str | None = None
    size_chart: dict[str, dict[str, float]] | None = None
    size_chart_raw: list[list[str]] | None = None
    source: Literal["shopify_feed", "manual_csv", "admin"]
    scraped_at: datetime


class CatalogRefreshRequest(BaseModel):
    """POST /catalog/refresh on the scraper."""

    retailers: list[Retailer] | None = Field(None, description="Brand keys (shared/feed_brands.py); None = every feed brand")
    max_products: int | None = Field(None, ge=1, le=5000, description="Per brand; default CATALOG_MAX_PRODUCTS")


class CatalogRefreshResult(BaseModel):
    stored_in: str
    kept: dict[str, int]
    skipped: dict[str, dict[str, int]]
    removed: dict[str, int] = Field(default_factory=dict, description="Stale feed products deleted per brand")
    errors: dict[str, str] = Field(default_factory=dict)
    recommendation_synced: bool = False
    rate_limited: bool = Field(False, description="Stopped early: the stores asked this IP to slow down (HTTP 429)")
    not_reached: list[str] = Field(default_factory=list, description="Brands left for the next run")
    disabled: list[str] = Field(default_factory=list,
                                description="Brands an admin switched off (scraper_config, SFR-040): not refreshed")
