"""SFR-040: the admin's scraping settings per store (public.scraper_config) are obeyed
by the catalog refresh: brands switched off are skipped, each brand has its own limit."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import httpx

import services.scraper.catalog_service as svc
from shared.config import settings
from shared.feed_brands import FEED_BRANDS


def _fake_crawl(seen: list):
    async def crawl(_polite, retailer, limit, sleep=None):
        seen.append((retailer.key, limit))
        return [], SimpleNamespace(skipped={}, seen=0, pages=1)
    return crawl


def _run(monkeypatch, config, retailers=None, max_products=None):
    seen: list = []

    async def settings_rows(_client):
        return config

    async def no_products(_client):
        return []

    async def save(_client, batch):
        return "snapshot"

    monkeypatch.setattr(svc, "scraper_settings", settings_rows)
    monkeypatch.setattr(svc, "load_products", no_products)
    monkeypatch.setattr(svc, "save_products", save)
    monkeypatch.setattr(svc, "crawl_shopify_feed", _fake_crawl(seen))
    monkeypatch.setattr(settings, "scraper_backend", "local")

    async def attach(*_a, **_k):
        return {}

    monkeypatch.setattr(svc, "attach_size_charts", attach)

    async def go():
        async with httpx.AsyncClient() as c:
            return await svc.refresh_feeds(c, retailers, max_products, notify=False)

    return asyncio.run(go()), seen


def test_a_scheduled_refresh_skips_brands_switched_off_and_uses_each_limit(monkeypatch):
    config = {"zeen": {"retailer": "zeen", "enabled": False, "max_products": 600},
              "lulusar": {"retailer": "lulusar", "enabled": True, "max_products": 50}}
    result, seen = _run(monkeypatch, config)
    keys = [k for k, _ in seen]
    assert "zeen" not in keys and result.disabled == ["zeen"]
    assert len(keys) == len(FEED_BRANDS) - 1  # every other brand, once
    limits = dict(seen)
    assert limits["lulusar"] == 50  # the admin's limit
    assert limits["outfitters"] == settings.catalog_max_products  # no row: the default


def test_run_now_on_a_brand_switched_off_still_runs(monkeypatch):
    config = {"zeen": {"retailer": "zeen", "enabled": False, "max_products": 120}}
    result, seen = _run(monkeypatch, config, retailers=["zeen"])
    assert seen == [("zeen", 120)] and result.disabled == []


def test_a_requested_limit_wins_and_no_settings_means_the_old_behaviour(monkeypatch):
    _, seen = _run(monkeypatch, {"lulusar": {"retailer": "lulusar", "enabled": True, "max_products": 50}},
                   retailers=["lulusar"], max_products=10)
    assert seen == [("lulusar", 10)]
    result, seen = _run(monkeypatch, {})
    assert len(seen) == len(FEED_BRANDS) and result.disabled == []


def test_unreadable_settings_are_ignored(monkeypatch):
    async def boom(*_a, **_k):
        raise httpx.ConnectError("down")

    monkeypatch.setattr(svc, "uses_supabase", lambda: True)
    monkeypatch.setattr(svc, "service_select", boom)

    async def go():
        async with httpx.AsyncClient() as c:
            return await svc.scraper_settings(c)

    assert asyncio.run(go()) == {}
    assert svc.brand_limit("x", None, {"x": {"max_products": 0}}) == settings.catalog_max_products
