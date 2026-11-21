"""Catalog refresh used by the scraper's API and scripts/ingest_catalog.py:
crawl the feeds, store the products, ask the recommendation service to
re-embed changed images (spec §10: never let embeddings go stale)."""

from __future__ import annotations

import logging

import httpx

from shared.catalog_store import load_products, remove_stale_feed_products, save_products, uses_supabase
from shared.config import settings
from shared.supabase_client import service_select
from shared.schemas.catalog import CatalogRefreshResult
from shared.feed_brands import FEED_BRANDS
from services.scraper.catalog import FEED_RETAILERS, FeedRateLimited, attach_size_charts, crawl_shopify_feed
from services.scraper.polite import PoliteClient, RobotsDisallowed
from services.scraper.remote import crawl_remote

logger = logging.getLogger("smartfit.scraper.catalog")


async def notify_recommendation(client: httpx.AsyncClient) -> bool:
    """Best effort: the recommendation service also syncs on start-up."""
    try:
        res = await client.post(f"{settings.recommendation_url.rstrip('/')}/catalog/sync", timeout=600)
        return res.status_code == 200
    except httpx.HTTPError as exc:
        logger.info("Recommendation service not reachable for catalog sync (%s); it will sync on start-up.", exc)
        return False


async def scraper_settings(client: httpx.AsyncClient) -> dict[str, dict]:
    """retailer -> its admin settings row (SFR-040: on/off, product limit) from
    public.scraper_config; {} when there is no Supabase or it can't be read, and
    then every brand is refreshed with the default limit, as before."""
    if not uses_supabase():
        return {}
    try:
        rows = await service_select(client, "scraper_config", {"select": "retailer,enabled,max_products"})
    except Exception as exc:  # noqa: BLE001 - settings are optional; never stop a refresh for them
        logger.info("scraper settings unreadable (%s); using the defaults", type(exc).__name__)
        return {}
    return {r["retailer"]: r for r in rows if isinstance(r, dict) and r.get("retailer")}


def brand_limit(key: str, requested: int | None, config: dict[str, dict]) -> int:
    """A refresh's own limit wins, then the admin's limit for this brand, then the default."""
    if requested:
        return requested
    row_limit = config.get(key, {}).get("max_products")
    if isinstance(row_limit, int) and row_limit > 0:
        return row_limit
    return settings.catalog_max_products


async def refresh_feeds(
    client: httpx.AsyncClient,
    retailers: list[str] | None,
    max_products: int | None,
    notify: bool = True,
    sleep=None,
) -> CatalogRefreshResult:
    """Refresh the given brands (None = every feed brand an admin hasn't switched
    off, SFR-040), one at a time: Shopify limits requests per IP across all its
    stores. Each brand is saved as soon as it's read; its stale feed products are
    then removed. A brand that fails keeps its previous products until the next
    refresh. An admin's "Run now" names its brand, so it runs even when off."""
    polite = PoliteClient(client)
    config = await scraper_settings(client)
    kept: dict[str, int] = {}
    skipped: dict[str, dict[str, int]] = {}
    removed: dict[str, int] = {}
    errors: dict[str, str] = {}
    stored_in = ""
    try:
        previous = {p.product_id: p for p in await load_products(client)}
    except Exception:  # first run / store unreachable: just fetch every chart
        previous = {}
    disabled = [] if retailers else [b.key for b in FEED_BRANDS if config.get(b.key, {}).get("enabled") is False]
    keys = retailers or refresh_order([b.key for b in FEED_BRANDS if b.key not in disabled], previous.values())
    rate_limited, not_reached = False, []
    for i, key in enumerate(keys):
        retailer = FEED_RETAILERS.get(key)
        if retailer is None:
            errors[key] = "not a feed brand (shared/feed_brands.py)"
            continue
        limit = brand_limit(key, max_products, config)
        try:
            if settings.scraper_backend == "modal":
                batch, stats = await crawl_remote(key, limit, previous)
            else:
                batch, stats = await crawl_shopify_feed(polite, retailer, limit, sleep=sleep)
                if retailer.size_chart_shop:
                    charts = await attach_size_charts(polite, retailer, batch, previous)
                    logger.info("%s size charts: %s", key, dict(charts))
        except RobotsDisallowed as exc:
            errors[key] = f"robots.txt forbids it ({exc}); use the manual CSV import instead"
            continue
        except FeedRateLimited as exc:
            # Shopify limits per IP across all its stores: every other brand
            # would say the same. Stop now and let the IP cool down.
            errors[key] = f"rate-limited by the store ({exc}); previous products kept"
            rate_limited, not_reached = True, list(keys[i + 1:])
            logger.warning("Stores are rate-limiting this IP; stopping this refresh (%d brands left for the next run)",
                           len(not_reached))
            break
        except (httpx.HTTPError, RuntimeError, ValueError) as exc:
            errors[key] = f"feed failed: {exc}; previous products kept"
            continue
        try:
            stored_in = await save_products(client, batch)
            if batch:  # an empty read is suspicious: never wipe a brand because of it
                removed[key] = await remove_stale_feed_products(
                    client, key, {p.product_id for p in batch}, min(p.scraped_at for p in batch))
        except httpx.HTTPError as exc:  # one brand's save failing must not stop the others
            errors[key] = f"save failed: {exc}; previous products kept"
            logger.error("%s: saving to the catalog failed: %s", key, exc)
            continue
        kept[key] = len(batch)
        skipped[key] = dict(stats.skipped)
        logger.info("%s: kept %d of %d (%d pages), removed %d stale, skipped %s",
                    key, len(batch), stats.seen, stats.pages, removed.get(key, 0), dict(stats.skipped))

    synced = await notify_recommendation(client) if (notify and kept) else False
    return CatalogRefreshResult(stored_in=stored_in or ("supabase" if uses_supabase() else "snapshot"),
                                kept=kept, skipped=skipped, removed=removed, errors=errors,
                                recommendation_synced=synced, rate_limited=rate_limited, not_reached=not_reached,
                                disabled=disabled)


def refresh_order(keys: list[str], products) -> list[str]:
    """Brands never refreshed first, then the longest since their last refresh,
    so a run stopped early (rate limit) carries on where it left off."""
    last: dict[str, object] = {}
    for p in products:
        if p.source == "shopify_feed" and (p.retailer not in last or p.scraped_at > last[p.retailer]):
            last[p.retailer] = p.scraped_at
    never = [k for k in keys if k not in last]
    seen = sorted((k for k in keys if k in last), key=lambda k: last[k])
    return never + seen
