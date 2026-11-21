"""Read one brand through the cloud runner (services/scraper/modal_app.py).

Same contract as the local crawl in catalog_service.refresh_feeds: returns
(products, stats) or raises RobotsDisallowed / FeedRateLimited / RuntimeError,
so a cloud read is handled exactly like a local one. Every product that comes
back is validated against ScrapedProduct before it can be saved.
"""

from __future__ import annotations

import asyncio
import logging
from collections import Counter

from pydantic import ValidationError

from shared.config import settings
from shared.schemas.catalog import ScrapedProduct
from services.scraper.catalog import FeedRateLimited, IngestStats
from services.scraper.polite import RobotsDisallowed

logger = logging.getLogger("smartfit.scraper.remote")

FUNCTION_NAME = "crawl_brand"  # services/scraper/modal_app.py

# Waits before the 2nd and 3rd try of a cloud read that failed for a temporary
# reason (18 Nov 2026: StreamTerminatedError made whole brands wait a day).
RETRY_WAITS_SECONDS = (10.0, 30.0)


async def _sleep(seconds: float) -> None:  # replaced in tests
    await asyncio.sleep(seconds)


def _is_setup_problem(exc: Exception) -> bool:
    """Not deployed / not logged in: retrying can't help."""
    name = type(exc).__name__
    return name in {"NotFoundError", "AuthError", "InvalidError", "ExecutionError"} or "not found" in str(exc).lower()


def _function():
    import modal

    return modal.Function.from_name(settings.scraper_modal_app, FUNCTION_NAME)


async def crawl_remote(
    key: str, max_products: int, previous: dict[str, ScrapedProduct]
) -> tuple[list[ScrapedProduct], IngestStats]:
    charts = [
        {"product_id": p.product_id, "size_chart_tag": p.size_chart_tag, "size_chart_raw": p.size_chart_raw}
        for p in previous.values()
        if p.retailer == key and p.size_chart_tag and p.size_chart_raw
    ]
    res = None
    for attempt, wait in enumerate((*RETRY_WAITS_SECONDS, None)):
        try:
            res = await _function().remote.aio(key, max_products, charts)
            break
        except Exception as exc:  # noqa: BLE001  (not deployed, not logged in, network...)
            name = type(exc).__name__
            if _is_setup_problem(exc):
                raise RuntimeError(f"cloud scraper not deployed or not logged in ({name}); run `modal deploy "
                                   f"backend/services/scraper/modal_app.py`") from exc
            if wait is None:
                raise RuntimeError(f"cloud scraper not reachable after {attempt + 1} tries ({name})") from exc
            # A dropped connection (StreamTerminatedError, timeouts) is temporary: try again.
            logger.warning("%s: cloud read failed (%s), retrying in %.0f s", key, name, wait)
            await _sleep(wait)
    if not isinstance(res, dict) or not res.get("ok"):
        kind = res.get("kind") if isinstance(res, dict) else "failed"
        message = res.get("message", "unknown error") if isinstance(res, dict) else "unexpected answer"
        if kind == "robots":
            raise RobotsDisallowed(message)
        if kind == "rate_limited":
            raise FeedRateLimited(message)
        raise RuntimeError(message)

    products: list[ScrapedProduct] = []
    invalid = 0
    for item in res.get("products") or []:
        try:
            product = ScrapedProduct.model_validate(item)
        except ValidationError:
            invalid += 1
            continue
        if product.retailer == key:  # only the brand that was asked for
            products.append(product)
    raw = res.get("stats") or {}
    stats = IngestStats(pages=int(raw.get("pages", 0)), seen=int(raw.get("seen", 0)), kept=len(products),
                        skipped=Counter({str(k): int(v) for k, v in (raw.get("skipped") or {}).items()}))
    if invalid:
        stats.skipped["invalid"] += invalid
    logger.info("%s read in the cloud: %d products, size charts %s", key, len(products), raw.get("size_charts"))
    return products, stats
