"""Scraper service — SRDS SFR-022 (scrape Pakistani retailers).

POST /scrape            ScrapeJob -> ScrapeResult (live keyword search; the app's
                        current recommend path)
POST /catalog/refresh   crawl retailer feeds into the product catalog (spec §10)
POST /catalog/products/{id}/recheck   one missing product, re-checked at its store

Ranking, the local-catalog fallback and user-facing messages live in the
recommendation service, so a retailer site change only ever touches this
service (rules.md §2.3, SRDS §4.3.7).

Brand selection is category-aware: e.g. "pent coat" only queries brands that
stock Western formal suits; kurta/shalwar brands are never queried for it.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from datetime import UTC, datetime, timedelta
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from collections.abc import Coroutine
from typing import Any

import httpx
from fastapi import FastAPI

from shared.brands import PAKISTANI_BRANDS, BrandConfig
from shared.feed_brands import FEED_BRANDS
from shared.config import settings
from shared.schemas.catalog import CatalogRefreshRequest, CatalogRefreshResult
from shared.schemas.scrape import ScrapeJob, ScrapeResult
from shared.service_app import create_service_app
from services.scraper.breakout_spider import scrape as scrape_breakout
from services.scraper.catalog_admin import router as catalog_admin_router
from services.scraper.catalog_service import refresh_feeds
from services.scraper.product_lookup import lookup_product
from shared.catalog_store import save_products
from services.scraper.generic_spider import scrape_brands_html, scrape_brands_shopify
from services.scraper.outfitters_spider import scrape as scrape_outfitters

logger = logging.getLogger("smartfit.scraper")

@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    task = asyncio.create_task(scheduled_refresh_loop()) if settings.catalog_refresh_hours > 0 else None
    try:
        yield
    finally:
        if task is not None:
            task.cancel()


app = create_service_app(
    "scraper",
    "SmartFit Scraper Service",
    "Catalog sync from Pakistani brands' official product feeds (SFR-022, spec §10).",
    lifespan=lifespan,
    health_extra=lambda: {
        "feed_brands": len(FEED_BRANDS),
        "refresh_every_hours": settings.catalog_refresh_hours,
        "last_scheduled_refresh": {k: last_scheduled_refresh.get(k) for k in (
            "running", "started_at", "kept", "errors", "rate_limited", "not_reached", "finished_in_s", "next_run_at")}
        if last_scheduled_refresh else None,
    },
)
app.include_router(catalog_admin_router)

# Retailers named in the SRDS get dedicated spider modules; every other brand
# uses the generic Shopify/HTML spiders.
SPIDERS = {
    "Outfitters": scrape_outfitters,
    "Breakout": scrape_breakout,
}


def select_brands(
    gender: str,
    exact_category: str | None,
    requested_brands: list[str] | None = None,
) -> list[BrandConfig]:
    """Select brands based on gender AND category strength."""
    candidates: list[BrandConfig] = []
    requested = {b.lower() for b in requested_brands or []}
    for brand in PAKISTANI_BRANDS:
        if requested and brand.name.lower() not in requested:
            continue
        slugs = brand.collection_slugs.get(gender) or brand.collection_slugs.get("unisex", [])
        if not slugs:
            continue
        if exact_category and brand.strengths and exact_category not in brand.strengths:
            logger.debug("  Skipping %s — no strength for category '%s'", brand.name, exact_category)
            continue
        candidates.append(brand)
    return candidates


async def gather_until(coros: list[Coroutine[Any, Any, list[dict]]], timeout: float) -> list[list[dict]]:
    """Run the brand searches concurrently; return the batches finished within
    `timeout` seconds and cancel the rest (slow sites must not sink the search)."""
    if not coros:
        return []
    tasks = [asyncio.create_task(c) for c in coros]
    done, pending = await asyncio.wait(tasks, timeout=max(0.0, timeout))
    for task in pending:
        task.cancel()
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)
        logger.info("  %d brand searches ran out of time and were skipped", len(pending))
    return [t.result() for t in done if not t.cancelled() and t.exception() is None]


async def run_scrape(job: ScrapeJob) -> ScrapeResult:
    started = time.monotonic()
    deadline = settings.scrape_deadline_seconds
    brands = select_brands(job.gender, job.exact_category, job.requested_brands)
    brand_names = [b.name for b in brands]
    shopify_brands = [b for b in brands if not b.html_only]
    html_brands = [b for b in brands if b.html_only]

    logger.info(
        "Scraping %d brands (%d Shopify, %d HTML-only) for gender=%s query='%s' category=%s",
        len(brands), len(shopify_brands), len(html_brands), job.gender, job.query, job.exact_category,
    )
    logger.info("  Brands selected: %s", ", ".join(brand_names))

    per_brand = max(3, settings.max_products_per_brand)

    async def shopify_task(brand: BrandConfig) -> list[dict]:
        try:
            spider = SPIDERS.get(brand.name)
            if spider is not None:
                batch = await spider(job.gender, job.query, job.exact_category, per_brand)
            else:
                batch = await scrape_brands_shopify([brand], job.gender, job.query, job.exact_category, per_brand)
            logger.info("  %s (Shopify): %d products", brand.name, len(batch))
            return batch
        except Exception as exc:  # one broken retailer must not fail the whole search
            logger.warning("  %s (Shopify) FAILED: %s", brand.name, exc)
            return []

    async def html_task(brand: BrandConfig) -> list[dict]:
        try:
            batch = await scrape_brands_html([brand], job.gender, job.exact_category, per_brand)
            logger.info("  %s (HTML): %d products", brand.name, len(batch))
            return batch
        except Exception as exc:
            logger.warning("  %s (HTML) FAILED: %s", brand.name, exc)
            return []

    def remaining() -> float:
        return deadline - (time.monotonic() - started)

    # ── Phase 1: Shopify JSON + HTML-only brands in parallel ──
    results = await gather_until(
        [*(shopify_task(b) for b in shopify_brands), *(html_task(b) for b in html_brands)],
        remaining(),
    )
    raw: list[dict] = [item for batch in results for item in batch]

    # ── Phase 2: HTML fallback for Shopify brands if yield is still low ──
    # (only with real time left; a few results now beat a timeout later)
    if len(raw) < job.max_total // 2 and remaining() > 8:
        logger.info("Low yield (%d), running HTML fallback for Shopify brands...", len(raw))
        seen = {p["product_url"] for p in raw}
        for batch in await gather_until([html_task(b) for b in shopify_brands], remaining()):
            for item in batch:
                if item["product_url"] not in seen:
                    raw.append(item)
                    seen.add(item["product_url"])

    return ScrapeResult(products=raw, brands_searched=brand_names)


@app.post("/scrape", response_model=ScrapeResult)
async def scrape(job: ScrapeJob) -> ScrapeResult:
    return await run_scrape(job)


@app.post("/catalog/refresh", response_model=CatalogRefreshResult)
async def catalog_refresh(body: CatalogRefreshRequest | None = None) -> CatalogRefreshResult:
    """Refresh now (admin "run", scripts). One refresh at a time: they share
    the stores' per-IP limits."""
    body = body or CatalogRefreshRequest()
    async with _refresh_lock, httpx.AsyncClient() as client:
        return await refresh_feeds(client, body.retailers, body.max_products)


@app.post("/catalog/products/{product_id}/recheck")
async def catalog_recheck(product_id: str) -> dict:
    """A product missing from the catalog (e.g. a saved item the refresh no
    longer keeps): ask its brand's store. Still sold -> saved back to the
    catalog and returned. Internal: called by the try-on service."""
    async with httpx.AsyncClient(follow_redirects=True) as client:
        product, status = await lookup_product(client, product_id)
        if product is not None:
            await save_products(client, [product])
            logger.info("Restored %s to the catalog from its store", product_id)
    return {"status": status, "product": product.model_dump(mode="json") if product else None}


_refresh_lock = asyncio.Lock()
last_scheduled_refresh: dict = {}


# When the stores rate-limit this IP: wait 15 min, then 30, 60, ... up to 3 h.
RATE_LIMIT_BACKOFF_SECONDS = (900.0, 1800.0, 3600.0, 7200.0, 10800.0)


def next_refresh_delay(rate_limited: bool, strikes: int, elapsed: float) -> float:
    if rate_limited:
        return RATE_LIMIT_BACKOFF_SECONDS[min(strikes, len(RATE_LIMIT_BACKOFF_SECONDS)) - 1]
    return max(60.0, settings.catalog_refresh_hours * 3600 - elapsed)


def _saved_next_run() -> datetime | None:
    """When the next scheduled refresh is due, as saved by the last run (survives restarts)."""
    try:
        raw = json.loads(Path(settings.catalog_refresh_state_path).read_text(encoding="utf-8"))
        when = datetime.fromisoformat(raw["next_run_at"])
        return when if when.tzinfo else when.replace(tzinfo=UTC)
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _save_next_run(when: datetime) -> None:
    try:
        path = Path(settings.catalog_refresh_state_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"next_run_at": when.isoformat()}), encoding="utf-8")
    except OSError as exc:
        logger.warning("Couldn't save the refresh schedule: %s", exc)


def first_refresh_delay(now: datetime, saved_next: datetime | None) -> float:
    """Seconds until the first refresh after a (re)start: the saved schedule,
    never sooner than the start-up delay. Restarting doesn't start a new run."""
    start = settings.catalog_refresh_start_delay_seconds
    if saved_next is None:
        return start
    return max(start, (saved_next - now).total_seconds())


async def scheduled_refresh_loop() -> None:
    """Every CATALOG_REFRESH_HOURS: refresh every feed brand (spec §23.12).
    If the stores rate-limit the run stops, backs off, and the next run starts
    with the brands it didn't reach. The next run time is saved to disk."""
    first = first_refresh_delay(datetime.now(UTC), _saved_next_run())
    last_scheduled_refresh.update(running=False, next_run_at=(datetime.now(UTC) + timedelta(seconds=first)).isoformat())
    await asyncio.sleep(first)
    strikes = 0
    while True:
        started = time.monotonic()
        rate_limited = False
        last_scheduled_refresh.update(running=True, started_at=datetime.now(UTC).isoformat())
        try:
            async with _refresh_lock, httpx.AsyncClient() as client:
                result = await refresh_feeds(client, None, None)
            rate_limited = result.rate_limited
            last_scheduled_refresh.update(result.model_dump(), finished_in_s=round(time.monotonic() - started))
            logger.info("Scheduled catalog refresh: kept %d products from %d brands; %d brands failed%s",
                        sum(result.kept.values()), len(result.kept), len(result.errors),
                        "; stopped early, stores rate-limiting" if rate_limited else "")
        except Exception:  # keep the schedule alive; the next run retries
            logger.exception("Scheduled catalog refresh failed")
        strikes = strikes + 1 if rate_limited else 0
        delay = next_refresh_delay(rate_limited, strikes, time.monotonic() - started)
        next_run = datetime.now(UTC) + timedelta(seconds=delay)
        _save_next_run(next_run)
        last_scheduled_refresh.update(running=False, next_run_at=next_run.isoformat())
        await asyncio.sleep(delay)
