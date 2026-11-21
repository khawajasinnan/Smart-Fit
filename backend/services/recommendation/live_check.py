"""Live price and stock check of the products about to be shown (spec §23.12).

The catalog is refreshed every few hours; just before the chat shows a
product, its store page's JSON (Shopify's /products/<handle>.js, the data
the product page itself loads) is read once:

* sold out or gone (404)  -> the product is dropped;
* available               -> price and in-stock sizes are updated and
                             price_checked_at is set (the app shows it);
* no answer in time / 429 -> kept as it was, price_checked_at stays empty
                             (the app says the price is from the catalog).

Same politeness as the catalog sync: our own user agent, robots.txt, a pause
between requests to one store, no retries.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime
from urllib.parse import urlparse

import httpx

from shared.schemas.recommendation import ProductRecommendation
from services.scraper.polite import PoliteClient, RobotsDisallowed

logger = logging.getLogger("smartfit.recommendation.live_check")

CHECK_TIMEOUT_SECONDS = 5.0
STORE_DELAY_SECONDS = 0.5  # between two checks on the same store (one chat message)
SIZE_OPTION_NAMES = {"size", "sizes", "talla"}

DROP = object()  # sentinel: the store says the product is gone or sold out


def _size_index(data: dict) -> int | None:
    for i, opt in enumerate(data.get("options") or []):
        name = opt.get("name") if isinstance(opt, dict) else opt
        if isinstance(name, str) and name.strip().lower() in SIZE_OPTION_NAMES:
            return i
    return None


def apply_store_data(product: ProductRecommendation, data: dict, now: datetime):
    """The updated product, or DROP. Shopify's .js prices are in paisa."""
    if not data.get("available"):
        return DROP
    available = [v for v in data.get("variants") or [] if v.get("available")]
    if not available:
        return DROP
    prices = [v["price"] for v in available if isinstance(v.get("price"), (int, float))]
    size_idx = _size_index(data)
    sizes: list[str] = []
    if size_idx is not None:
        for v in available:
            opts = v.get("options") or [v.get("option1"), v.get("option2"), v.get("option3")]
            if size_idx < len(opts) and isinstance(opts[size_idx], str) and opts[size_idx] not in sizes:
                sizes.append(opts[size_idx])
    return product.model_copy(update={
        "price_pkr": round(min(prices) / 100) if prices else product.price_pkr,
        "sizes": sizes or product.sizes,
        "in_stock": True,
        "price_checked_at": now,
    })


async def _check_one(polite: PoliteClient, product: ProductRecommendation):
    url = product.product_url.split("?")[0].rstrip("/") + ".js"
    try:
        res = await polite.get(url, timeout=CHECK_TIMEOUT_SECONDS, headers={"Accept": "application/json"})
    except (httpx.HTTPError, RobotsDisallowed) as exc:
        logger.info("live check skipped for %s (%s)", product.product_url, type(exc).__name__)
        return product
    if res.status_code == 404:
        return DROP
    if res.status_code != 200 or "json" not in res.headers.get("content-type", ""):
        return product  # 429, maintenance page, ...: show the catalog data
    try:
        return apply_store_data(product, res.json(), datetime.now(UTC))
    except (ValueError, TypeError, KeyError):
        return product


async def live_check(
    client: httpx.AsyncClient,
    candidates: list[ProductRecommendation],
    keep: int,
    budget_seconds: float = 8.0,
    user_agent: str | None = None,
) -> list[ProductRecommendation]:
    """Check candidates (best first) in parallel across stores; return the
    first `keep` that aren't sold out, in the original order."""
    if not candidates:
        return []
    polite = PoliteClient(client, user_agent=user_agent, delay=STORE_DELAY_SECONDS)
    tasks = [asyncio.create_task(_check_one(polite, p)) for p in candidates]
    done, pending = await asyncio.wait(tasks, timeout=budget_seconds)
    for task in pending:
        task.cancel()
    results = []
    for product, task in zip(candidates, tasks):
        if task in done and not task.cancelled() and task.exception() is None:
            results.append(task.result())
        else:
            results.append(product)  # ran out of time: keep, unverified
    kept = [r for r in results if r is not DROP]
    stores = {urlparse(p.product_url).hostname for p in candidates}
    logger.info("live check: %d candidates from %d stores -> %d kept (%d verified)", len(candidates), len(stores),
                len(kept), sum(1 for r in kept if r.price_checked_at))
    return kept[:keep]
