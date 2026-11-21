"""Catalog sync when the stores rate-limit this IP (spec §23.17): stop the
run instead of hammering every other brand, back off, and resume with the
brands that weren't reached. A failed save only affects that brand."""

import asyncio
from datetime import UTC, datetime, timedelta

import httpx
import pytest

pytest.importorskip("protego")

from shared import catalog_store  # noqa: E402
from shared.config import settings  # noqa: E402
from shared.feed_brands import BY_KEY  # noqa: E402
from services.scraper import catalog_service  # noqa: E402
from services.scraper.catalog import parse_shopify_product  # noqa: E402
from services.scraper.catalog_service import refresh_feeds, refresh_order  # noqa: E402
from services.scraper.main import RATE_LIMIT_BACKOFF_SECONDS, next_refresh_delay  # noqa: E402

NOW = datetime(2026, 11, 8, tzinfo=UTC)


def feed_item(handle="kurta"):
    return {"id": 1, "handle": handle, "title": "Embroidered Lawn Kurta", "product_type": "Kurta",
            "tags": ["women"], "published_at": "2026-11-01T00:00:00Z",
            "images": [{"src": "https://cdn.shopify.com/s/files/k.jpg"}],
            "variants": [{"option1": "M", "price": "4990.00", "available": True}],
            "options": [{"name": "Size", "values": ["M"]}]}


async def no_sleep(_):
    pass


@pytest.fixture
def snapshot(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_store", "snapshot")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    monkeypatch.setattr(settings, "scraper_rate_limit_seconds", 0.0)


def test_rate_limit_stops_the_run_and_leaves_the_rest_for_later(snapshot):
    requests = []

    def handler(req: httpx.Request):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        requests.append(req.url.host)
        if req.url.host == "zarashahjahan.com":  # first brand works
            return httpx.Response(200, json={"products": [feed_item()] if req.url.params["page"] == "1" else []})
        return httpx.Response(429, headers={"Retry-After": "1"})  # then the IP is limited

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
            return await refresh_feeds(c, ["zara-shahjahan", "lulusar", "saya", "zeen"], 10, notify=False, sleep=no_sleep)

    result = asyncio.run(run())
    assert result.kept == {"zara-shahjahan": 1}
    assert result.rate_limited and "lulusar" in result.errors
    assert result.not_reached == ["saya", "zeen"]
    # lulusar: one request, one wait as asked, one retry. Saya and Zeen are never contacted.
    assert requests.count("lulusar.com") == 2 and "saya.pk" not in requests and "zeenwoman.com" not in requests
    saved = asyncio.run(catalog_store.load_products(httpx.AsyncClient()))
    assert [p.product_id for p in saved] == ["zara-shahjahan:kurta"]


def test_next_run_starts_with_brands_never_or_least_recently_refreshed():
    def prod(retailer, at, source="shopify_feed"):
        p, _ = parse_shopify_product(feed_item(handle=retailer), BY_KEY[retailer], at)
        return p.model_copy(update={"source": source})

    products = [prod("lulusar", NOW), prod("saya", NOW - timedelta(days=2)), prod("zeen", NOW - timedelta(days=1)),
                prod("zara-shahjahan", NOW - timedelta(days=9), source="manual_csv")]  # CSV rows don't count
    assert refresh_order(["lulusar", "saya", "zeen", "zara-shahjahan"], products) == [
        "zara-shahjahan", "saya", "zeen", "lulusar"]


def test_a_failed_save_only_skips_that_brand(snapshot, monkeypatch):
    real_save = catalog_store.save_products

    async def flaky_save(client, batch):
        if batch and batch[0].retailer == "lulusar":
            raise httpx.HTTPStatusError("400 check constraint", request=httpx.Request("POST", "https://x"),
                                        response=httpx.Response(400))
        return await real_save(client, batch)

    monkeypatch.setattr(catalog_service, "save_products", flaky_save)

    def handler(req: httpx.Request):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(200, json={"products": [feed_item(handle=req.url.host)] if req.url.params["page"] == "1" else []})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
            return await refresh_feeds(c, ["lulusar", "saya"], 10, notify=False, sleep=no_sleep)

    result = asyncio.run(run())
    assert "save failed" in result.errors["lulusar"] and result.kept == {"saya": 1}


def test_backoff_grows_then_caps_and_resets_after_a_clean_run(monkeypatch):
    monkeypatch.setattr(settings, "catalog_refresh_hours", 6.0)  # tests turn the schedule off by default
    delays = [next_refresh_delay(True, strikes, 0) for strikes in range(1, 8)]
    assert delays[:5] == list(RATE_LIMIT_BACKOFF_SECONDS) and delays[5:] == [RATE_LIMIT_BACKOFF_SECONDS[-1]] * 2
    assert next_refresh_delay(False, 0, 600) == 6 * 3600 - 600
