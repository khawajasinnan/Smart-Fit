"""Re-checking one product at its brand's store (try-on of items the catalog
refresh dropped). A fake store via httpx.MockTransport: no network."""

from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from services.scraper import product_lookup as pl
from shared.config import settings


@pytest.fixture(autouse=True)
def no_wait(monkeypatch):
    monkeypatch.setattr(settings, "scraper_rate_limit_seconds", 0.0)


def js_product(handle="relaxed-hoodie", available=True, product_type="Hoodies", tags=("Men",)) -> dict:
    """Shopify's /products/<handle>.js: prices in paisa, images as //cdn strings."""
    return {
        "title": "Relaxed Hoodie", "handle": handle, "type": product_type, "tags": list(tags),
        "images": ["//cdn.shopify.com/s/files/hoodie.jpg"],
        "options": [{"name": "Color", "values": ["Black"]}, {"name": "Size", "values": ["S", "M"]}],
        "variants": [
            {"option1": "Black", "option2": "S", "option3": None, "available": available, "price": 499000},
            {"option1": "Black", "option2": "M", "option3": None, "available": False, "price": 499000},
        ],
    }


def run(handler, product_id):
    async def go():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await pl.lookup_product(client, product_id)
    return asyncio.run(go())


def store(js=None, js_status=200, js_type="text/javascript", feed_pages=None, calls=None):
    def handler(req: httpx.Request) -> httpx.Response:
        if calls is not None:
            calls.append(str(req.url))
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        if req.url.path.endswith(".js"):
            if js_status == 200:
                return httpx.Response(200, json=js, headers={"content-type": js_type})
            return httpx.Response(js_status, text="<html>not found</html>", headers={"content-type": js_type})
        if req.url.path == "/products.json":
            page = int(req.url.params.get("page", "1"))
            items = (feed_pages or {}).get(page, [])
            return httpx.Response(200, json={"products": items})
        return httpx.Response(500)
    return handler


def test_split_product_id_only_accepts_known_brands_and_plain_handles():
    assert pl.split_product_id("outfitters:f0566-303")[1] == "f0566-303"
    for bad in ("evil.com:x", "outfitters", "outfitters:", "outfitters:../../admin", "outfitters:a/b", "custom:abc"):
        assert pl.split_product_id(bad) is None, bad


def test_js_is_converted_to_the_feed_shape():
    item = pl.feed_item_from_js(js_product())
    assert item["product_type"] == "Hoodies"
    assert item["images"] == [{"src": "https://cdn.shopify.com/s/files/hoodie.jpg"}]
    assert item["variants"][0]["price"] == "4990.00"  # paisa -> rupees
    assert [o["name"] for o in item["options"]] == ["Color", "Size"]


def test_a_product_still_sold_comes_back_with_only_in_stock_sizes():
    product, status = run(store(js_product()), "outfitters:relaxed-hoodie")
    assert status == "available"
    assert product.product_id == "outfitters:relaxed-hoodie"
    assert product.price == 4990 and product.sizes == ["S"] and product.all_sizes == ["S", "M"]
    assert product.tryon_category == "upper" and product.gender == "men"
    assert product.product_url == "https://outfitters.com.pk/products/relaxed-hoodie"


def test_shopifys_own_404_means_gone():
    def handler(req):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(404, json={"error": "not found"})
    assert run(handler, "outfitters:old") == (None, "gone")


def test_sold_out_everywhere_is_sold_out():
    assert run(store(js_product(available=False)), "outfitters:relaxed-hoodie") == (None, "sold_out")


def test_kids_items_are_not_restored():
    kid = js_product(tags=("Boys", "all-baby-boys"), product_type="T-Shirts")
    assert run(store(kid), "outfitters:relaxed-hoodie") == (None, "not_clothing")


def test_a_redirect_to_another_product_is_gone():
    assert run(store(js_product(handle="something-else")), "outfitters:relaxed-hoodie") == (None, "gone")


def test_unknown_brand_never_touches_the_network():
    calls: list[str] = []
    assert run(store(calls=calls), "evil.com:x") == (None, "unknown_brand")
    assert calls == []


def test_a_headless_store_without_js_is_searched_in_its_feed():
    """Cougar answers /products/<handle>.js with an HTML 404: the feed is read instead."""
    feed_item = {"title": "Ottoman Sweat", "handle": "msw642", "product_type": "Sweatshirts", "tags": ["Men"],
                 "images": [{"src": "https://cdn.shopify.com/a.jpg"}], "options": [{"name": "Size"}],
                 "variants": [{"option1": "M", "available": True, "price": "4549.00"}]}
    filler = [{"handle": f"x{i}"} for i in range(pl.FEED_PAGE_SIZE)]
    handler = store(js_status=404, js_type="text/html", feed_pages={1: filler, 2: [feed_item]})
    product, status = run(handler, "cougar:msw642")
    assert status == "available" and product.name == "Ottoman Sweat" and product.sizes == ["M"]


def test_a_headless_store_without_the_product_is_gone():
    handler = store(js_status=404, js_type="text/html", feed_pages={1: [{"handle": "other"}]})
    assert run(handler, "cougar:msw642") == (None, "gone")


@pytest.mark.parametrize("status", [429, 500, 503])
def test_store_trouble_is_unreachable_not_gone(status):
    def handler(req):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(status, text="busy")
    assert run(handler, "outfitters:x") == (None, "unreachable")


def test_network_error_is_unreachable():
    def handler(req):
        raise httpx.ConnectError("down")
    assert run(handler, "outfitters:x") == (None, "unreachable")


def test_robots_disallow_is_respected():
    def handler(req):
        if req.url.path == "/robots.txt":
            return httpx.Response(200, text="User-agent: *\nDisallow: /products/")
        raise AssertionError(f"fetched {req.url} although robots.txt disallows it")
    assert run(handler, "outfitters:x") == (None, "unreachable")


def test_recheck_endpoint_saves_a_restored_product(monkeypatch):
    from fastapi.testclient import TestClient

    import services.scraper.main as scraper

    saved = []
    restored, _ = run(store(js_product()), "outfitters:relaxed-hoodie")

    async def lookup(_client, pid):
        return restored, "available"

    async def save(_client, products):
        saved.extend(products)
        return "snapshot"

    monkeypatch.setattr(scraper, "lookup_product", lookup)
    monkeypatch.setattr(scraper, "save_products", save)
    monkeypatch.setattr(settings, "catalog_refresh_hours", 0)
    with TestClient(scraper.app) as client:
        res = client.post("/catalog/products/outfitters:relaxed-hoodie/recheck")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "available" and body["product"]["product_id"] == "outfitters:relaxed-hoodie"
    assert [p.product_id for p in saved] == ["outfitters:relaxed-hoodie"]
    json.dumps(body)  # plain JSON for the try-on service
