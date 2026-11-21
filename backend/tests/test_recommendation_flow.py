"""Chat recommendations: catalog search, ranking, brand variety and the live
price/stock check (spec §23.12); plus the legacy /scrape spider phases.
No network: stores are httpx MockTransports, the catalog is a fake store."""

import asyncio
import time
from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

import services.recommendation.main as rec
import services.scraper.main as scraper
from services.recommendation.local_catalog import catalog_item, is_product_page
from shared.schemas.catalog import ScrapedProduct
from shared.schemas.scrape import ScrapeJob

KURTA_REQUEST = {"profile": {"gender": "male"}, "user_message": "black kurta shalwar for eid", "max_products": 6}

SCRAPED_ITEM = {  # what the legacy /scrape spider returns
    "id": "s1",
    "brand": "Edenrobe",
    "title": "Black Embroidered Kurta Shalwar",
    "category": "kurta shalwar",
    "price_pkr": 7990,
    "currency": "PKR",
    "image_url": "https://example.com/k.jpg",
    "product_url": "https://edenrobe.com/products/black-kurta-shalwar",
    "sizes": ["S", "M", "L"],
    "colors": ["black"],
    "tags": ["kurta", "shalwar"],
    "in_stock": True,
}


CATALOG_KURTA = ScrapedProduct(
    product_id="breakout:black-kurta-shalwar-set",
    retailer="breakout",
    name="Black Kurta Shalwar Set",
    product_url="https://breakout.com.pk/products/black-kurta-shalwar-set",
    image_url="https://cdn.shopify.com/black-kurta.jpg",
    price=6990,
    sizes=["M", "L"],
    all_sizes=["S", "M", "L"],
    category="kurta shalwar",
    tryon_category="dress",
    gender="men",
    colors=["Black"],
    source="manual_csv",
    scraped_at=datetime(2026, 10, 24, tzinfo=timezone.utc),
)


@pytest.fixture(autouse=True)
def fake_catalog_store(monkeypatch):
    """The catalog fallback reads this instead of Supabase / the snapshot."""
    calls = {"n": 0, "products": [CATALOG_KURTA], "fail": False}

    async def fake_load(_client):
        calls["n"] += 1
        if calls["fail"]:
            raise httpx.ConnectError("store down")
        return list(calls["products"])

    monkeypatch.setattr(rec, "load_products", fake_load)
    monkeypatch.setattr(rec, "_catalog_items", [])
    monkeypatch.setattr(rec, "_catalog_loaded_at", None)
    return calls


def _client_with_scraper(handler):
    c = TestClient(rec.app)
    c.__enter__()
    rec._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return c


def _store(available=True, price_paisa=699000, sizes=("M", "L"), status=200):
    """A brand's store as the live check sees it: robots.txt and /products/<handle>.js."""
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        assert request.url.path.endswith(".js")
        if status != 200:
            return httpx.Response(status)
        return httpx.Response(200, json={
            "available": available,
            "options": [{"name": "Size", "values": list(sizes)}],
            "variants": [{"available": available, "price": price_paisa, "options": [s]} for s in sizes],
        })

    return handler, seen


def _post(handler, body=KURTA_REQUEST):
    c = _client_with_scraper(handler)
    try:
        return c.post("/recommend/app", json=body).json()
    finally:
        c.__exit__(None, None, None)


def test_catalog_product_is_live_checked_before_it_is_shown():
    handler, seen = _store(price_paisa=649000, sizes=("L",))
    body = _post(handler)
    [product] = body["products"]
    assert product["product_url"] == CATALOG_KURTA.product_url  # the exact product page
    assert product["price_pkr"] == 6490  # the store's price now (paisa -> rupees), not the catalog's 6990
    assert product["sizes"] == ["L"]
    assert product["price_checked_at"] and product["catalog_updated_at"]
    assert "/products/black-kurta-shalwar-set.js" in seen
    assert body["brands_searched"] == ["Breakout"]
    assert body["message"].startswith("Found ")


def test_sold_out_on_the_store_is_not_shown():
    handler, _ = _store(available=False)
    assert _post(handler)["products"] == []


def test_removed_from_the_store_is_not_shown():
    handler, _ = _store(status=404)
    assert _post(handler)["products"] == []


def test_store_unreachable_keeps_the_catalog_price_unverified():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("store down", request=request)

    [product] = _post(handler)["products"]
    assert product["id"] == CATALOG_KURTA.product_id
    assert product["price_pkr"] == 6990 and product["price_checked_at"] is None


def test_non_product_links_never_reach_the_app(fake_catalog_store):
    fake_catalog_store["products"] = [
        CATALOG_KURTA,
        CATALOG_KURTA.model_copy(update={"product_id": "breakout:collection",
                                         "product_url": "https://breakout.com.pk/collections/men-kurta"}),
    ]
    handler, _ = _store()
    urls = [p["product_url"] for p in _post(handler)["products"]]
    assert urls == [CATALOG_KURTA.product_url]


def test_diversify_spreads_brands_before_filling_by_score():
    from shared.schemas.recommendation import ProductRecommendation

    ranked = [ProductRecommendation(id=f"{b}{i}", brand=b, title="t", product_url=f"https://x/products/{b}{i}")
              for b, i in [("A", 1), ("A", 2), ("A", 3), ("A", 4), ("B", 1), ("C", 1)]]
    assert [p.id for p in rec.diversify(ranked, 4)] == ["A1", "A2", "B1", "C1"]
    assert [p.id for p in rec.diversify(ranked, 6)] == ["A1", "A2", "B1", "C1", "A3", "A4"]


@pytest.mark.parametrize(
    ("url", "ok"),
    [
        ("https://outfitters.com.pk/products/oversized-tee", True),
        ("https://breakout.com.pk/collections/men/products/denim-jacket", True),
        ("https://outfitters.com.pk/collections/men-jackets", False),
        ("https://outfitters.com.pk/", False),
        ("https://outfitters.com.pk/products/", False),
        ("http://outfitters.com.pk/products/oversized-tee", False),
        ("not a url", False),
    ],
)
def test_is_product_page(url, ok):
    assert is_product_page(url) is ok


def test_catalog_item_shape():
    item = catalog_item(CATALOG_KURTA)
    assert item["brand"] == "Breakout"
    assert item["price_pkr"] == 6990
    assert item["colors"] == ["black"]
    assert item["tags"][0] == "male"
    assert item["in_stock"] is True


def test_catalog_fallback_is_cached_and_survives_a_store_outage(fake_catalog_store, monkeypatch):
    rec._client = httpx.AsyncClient()
    try:
        first = asyncio.run(rec.catalog_fallback_items())
        again = asyncio.run(rec.catalog_fallback_items())
        assert fake_catalog_store["n"] == 1  # second call served from the cache
        assert first == again and first[0]["id"] == CATALOG_KURTA.product_id

        # cache expired and the store is down: keep the last good catalog
        monkeypatch.setattr(rec, "_catalog_loaded_at", -1e9)
        fake_catalog_store["fail"] = True
        assert asyncio.run(rec.catalog_fallback_items()) == first
    finally:
        asyncio.run(rec._client.aclose())
        rec._client = None


def test_negative_budget_message_unchanged():
    c = _client_with_scraper(_store()[0])
    try:
        res = c.post("/recommend/app", json={**KURTA_REQUEST, "user_message": "kurta under -5000 PKR"})
    finally:
        c.__exit__(None, None, None)
    body = res.json()
    assert body["products"] == []
    assert body["message"] == (
        "Budget cannot be a negative amount. Please enter a positive PKR budget, for example 5000 PKR."
    )


def test_scraper_phases_use_spiders_and_html_fallback(monkeypatch):
    calls = {"shopify": [], "html": []}

    async def fake_shopify(brands, gender, query, category, per_brand):
        calls["shopify"].append(brands[0].name)
        return []  # zero yield -> forces the HTML fallback phase

    async def fake_html(brands, gender, category, per_brand):
        calls["html"].append(brands[0].name)
        return [{**SCRAPED_ITEM, "brand": brands[0].name, "product_url": f"https://x/{brands[0].name}"}]

    async def fake_named_spider(gender, query, category, per_brand):
        calls["shopify"].append("named")
        return []

    monkeypatch.setattr(scraper, "scrape_brands_shopify", fake_shopify)
    monkeypatch.setattr(scraper, "scrape_brands_html", fake_html)
    monkeypatch.setitem(scraper.SPIDERS, "Outfitters", fake_named_spider)
    monkeypatch.setitem(scraper.SPIDERS, "Breakout", fake_named_spider)

    result = asyncio.run(scraper.run_scrape(ScrapeJob(gender="male", query="jeans", max_total=30)))
    assert result.brands_searched, "male brands should be selected"
    assert "named" in calls["shopify"]  # Outfitters/Breakout go through their own spiders
    assert len({p["product_url"] for p in result.products}) == len(result.products)  # de-duplicated


def test_slow_brands_are_cut_off_at_the_deadline(monkeypatch):
    """34 ethnic-wear brands once took 94 s, past the recommendation service's
    75 s wait, so the user got nothing. Now the search returns what answered."""
    monkeypatch.setattr(scraper.settings, "scrape_deadline_seconds", 0.5)

    async def shopify(brands, gender, query, category, per_brand):
        if brands[0].name == "Cougar":
            await asyncio.sleep(30)  # a hung retailer site
        return [{**SCRAPED_ITEM, "brand": brands[0].name, "product_url": f"https://x/products/{brands[0].name}"}]

    async def html(brands, gender, category, per_brand):
        return []

    async def named(gender, query, category, per_brand):
        return []

    monkeypatch.setattr(scraper, "scrape_brands_shopify", shopify)
    monkeypatch.setattr(scraper, "scrape_brands_html", html)
    monkeypatch.setitem(scraper.SPIDERS, "Outfitters", named)
    monkeypatch.setitem(scraper.SPIDERS, "Breakout", named)

    started = time.monotonic()
    result = asyncio.run(scraper.run_scrape(ScrapeJob(gender="male", query="t-shirt", max_total=30)))
    assert time.monotonic() - started < 3
    brands = {p["brand"] for p in result.products}
    assert "Cougar" in result.brands_searched and "Cougar" not in brands
    assert brands, "the brands that answered in time are kept"


def test_catalog_fallback_matches_colour_families(fake_catalog_store):
    """"blue jeans" must find a catalog product listed as "Indigo Blue"."""
    jeans = CATALOG_KURTA.model_copy(update={
        "product_id": "outfitters:f0751-109", "retailer": "outfitters", "name": "Regular Fit Jeans",
        "product_url": "https://outfitters.com.pk/products/f0751-109", "price": 2990, "category": "jeans",
        "colors": ["Indigo Blue"],
    })
    fake_catalog_store["products"] = [jeans]

    handler, _ = _store(price_paisa=299000)  # the store still sells it at PKR 2,990
    body = _post(handler, {**KURTA_REQUEST, "user_message": "blue jeans under 5000"})
    assert [p["product_url"] for p in body["products"]] == [jeans.product_url]


def test_a_live_price_above_the_chat_budget_is_never_shown(fake_catalog_store):
    """The catalog says PKR 2,990 but the store now charges 6,990: over a 5,000 budget."""
    jeans = CATALOG_KURTA.model_copy(update={
        "product_id": "outfitters:f0751-109", "retailer": "outfitters", "name": "Regular Fit Jeans",
        "product_url": "https://outfitters.com.pk/products/f0751-109", "price": 2990, "category": "jeans",
        "colors": ["Indigo Blue"],
    })
    fake_catalog_store["products"] = [jeans]
    handler, _ = _store(price_paisa=699000)
    body = _post(handler, {**KURTA_REQUEST, "user_message": "blue jeans under 5000"})
    assert body["products"] == []


@pytest.mark.parametrize("gender", ["male", "female"])
def test_select_brands_respects_requested_brand(gender):
    picked = scraper.select_brands(gender, None, ["Outfitters"])
    assert [b.name for b in picked] in ([], ["Outfitters"])
