"""The 504 of 18 Nov 2026: loading the 25k-product catalog took ~47 s inside a
user's request. Now pages load in parallel, the cache is refreshed in the
background, and concurrent requests share one load."""

from __future__ import annotations

import asyncio
import time

import httpx
import pytest

import services.recommendation.main as rec
from shared import catalog_store
from shared.config import settings


def row(i: int) -> dict:
    return {"product_id": f"outfitters:p{i:05d}", "retailer": "outfitters", "name": f"Tee {i}",
            "product_url": f"https://outfitters.com.pk/products/p{i}", "image_url": "https://cdn.example/a.jpg",
            "price": 1000 + i, "sizes": ["M"], "category": "t-shirts", "tryon_category": "upper", "gender": "men",
            "source": "shopify_feed", "scraped_at": "2026-11-18T00:00:00+00:00"}


def test_load_products_fetches_pages_in_parallel_and_returns_each_product_once(monkeypatch):
    rows = [row(i) for i in range(2500)]
    calls, in_flight, peak = [], [0], [0]

    async def fake_select(_client, table, params):
        assert table == "products"
        calls.append(int(params["offset"]))
        in_flight[0] += 1
        peak[0] = max(peak[0], in_flight[0])
        await asyncio.sleep(0.05)
        in_flight[0] -= 1
        off, lim = int(params["offset"]), int(params["limit"])
        return rows[off:off + lim]

    monkeypatch.setattr(catalog_store, "uses_supabase", lambda: True)
    monkeypatch.setattr(catalog_store, "service_select", fake_select)
    products = asyncio.run(catalog_store.load_products(httpx.AsyncClient()))
    assert len(products) == 2500 and len({p.product_id for p in products}) == 2500
    assert peak[0] > 1  # really in parallel
    assert peak[0] <= catalog_store.PARALLEL_PAGES


def test_load_products_keeps_paging_past_full_batches(monkeypatch):
    n = catalog_store.PAGE_ROWS * catalog_store.PARALLEL_PAGES + 10  # one full batch + a bit
    rows = [row(i) for i in range(n)]

    async def fake_select(_client, _table, params):
        off, lim = int(params["offset"]), int(params["limit"])
        return rows[off:off + lim]

    monkeypatch.setattr(catalog_store, "uses_supabase", lambda: True)
    monkeypatch.setattr(catalog_store, "service_select", fake_select)
    assert len(asyncio.run(catalog_store.load_products(httpx.AsyncClient()))) == n


@pytest.fixture
def cache(monkeypatch):
    monkeypatch.setattr(rec, "_catalog_items", [])
    monkeypatch.setattr(rec, "_catalog_loaded_at", None)
    monkeypatch.setattr(rec, "_catalog_task", None)
    rec._client = httpx.AsyncClient()
    yield
    rec._client = None


def test_an_expired_cache_answers_at_once_and_reloads_in_the_background(cache, monkeypatch):
    old = [{"id": "old"}]
    monkeypatch.setattr(rec, "_catalog_items", old)
    monkeypatch.setattr(rec, "_catalog_loaded_at", -1e9)  # long expired
    loads = []

    async def slow_load(_client):
        loads.append(1)
        await asyncio.sleep(60)  # a store as slow as the one that caused the 504
        return []

    monkeypatch.setattr(rec, "load_products", slow_load)

    async def run():
        t = time.monotonic()
        items = await rec.catalog_fallback_items()
        took = time.monotonic() - t
        await asyncio.sleep(0)  # let the background reload start
        return items, took

    items, took = asyncio.run(run())
    assert items == old and took < 1.0
    assert loads == [1]


def test_concurrent_first_requests_share_one_load(cache, monkeypatch):
    from services.recommendation.local_catalog import catalog_item  # noqa: F401  (shape used by the cache)
    from shared.schemas.catalog import ScrapedProduct

    loads = []

    async def load(_client):
        loads.append(1)
        await asyncio.sleep(0.2)
        return [ScrapedProduct.model_validate(row(1))]

    monkeypatch.setattr(rec, "load_products", load)

    async def run():
        return await asyncio.gather(*(rec.catalog_fallback_items() for _ in range(5)))

    results = asyncio.run(run())
    assert loads == [1]
    assert all(r and r[0]["id"] == "outfitters:p00001" for r in results)


def test_the_first_request_never_waits_past_the_limit(cache, monkeypatch):
    monkeypatch.setattr(rec, "CATALOG_FIRST_WAIT_SECONDS", 0.3)

    async def never(_client):
        await asyncio.sleep(60)
        return []

    monkeypatch.setattr(rec, "load_products", never)

    async def run():
        t = time.monotonic()
        items = await rec.catalog_fallback_items()
        return items, time.monotonic() - t

    items, took = asyncio.run(run())
    assert items == [] and took < 2.0  # answers (empty: "no products") instead of a gateway timeout


def test_first_wait_stays_below_the_gateway_timeout():
    assert rec.CATALOG_FIRST_WAIT_SECONDS + 15 < settings.proxy_timeout_seconds
