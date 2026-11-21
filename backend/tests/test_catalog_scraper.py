"""Catalog scraping (spec §10): feed parsing, politeness, manual CSV, store.
No network: httpx MockTransport everywhere."""

import asyncio
import time
from datetime import UTC, datetime

import httpx
import pytest

pytest.importorskip("protego")

from shared import catalog_store  # noqa: E402
import services.scraper.catalog as catalog  # noqa: E402
from shared.config import settings  # noqa: E402
from services.scraper.catalog import (  # noqa: E402
    FEED_RETAILERS,
    adult_gender,
    attach_size_charts,
    crawl_shopify_feed,
    parse_shopify_product,
    tryon_slot,
)
from services.scraper.catalog_service import refresh_feeds  # noqa: E402
from services.scraper.manual_import import parse_manual_csv  # noqa: E402
from services.scraper.polite import PoliteClient, RobotsDisallowed  # noqa: E402
from services.scraper.size_chart import chart_tag, parse_chart  # noqa: E402

OUTFITTERS = FEED_RETAILERS["outfitters"]
NOW = datetime(2026, 10, 23, tzinfo=UTC)


def item(**over):
    base = {
        "title": "Striped T-Shirt",
        "handle": "f1612-106",
        "product_type": "TEES",
        "tags": ["Men", "2025", "menspecialprices"],
        "options": [{"name": "Color", "values": ["Royal Blue"]}, {"name": "Size", "values": ["S", "M", "L"]}],
        "variants": [
            {"option1": "Royal Blue", "option2": "S", "price": "1390.00", "available": False},
            {"option1": "Royal Blue", "option2": "M", "price": "1390.00", "available": True},
            {"option1": "Royal Blue", "option2": "L", "price": "1290.00", "available": True},
        ],
        "images": [{"src": "https://cdn.shopify.com/a.jpg"}, {"src": "https://cdn.shopify.com/b.jpg"}],
    }
    return base | over


# Every product type seen in Outfitters' real feed (Oct 2026) -> expected slot.
@pytest.mark.parametrize(
    ("ptype", "slot"),
    [
        ("TEES", "upper"), ("SHIRTS/BLOUSES", "upper"), ("SHIRTS", "upper"), ("POLOS", "upper"),
        ("SWEATSHIRTS", "upper"), ("SWEATERS", "upper"), ("OUTERWEAR", "upper"), ("ACTIVEWEAR (TOP)", "upper"),
        ("JEANS", "lower"), ("TROUSERS", "lower"), ("SHORTS", "lower"), ("ACTIVEWEAR (BOTTOM)", "lower"),
        ("DRESSES & JUMP SUITS", "dress"),
        ("CLOSED SHOES", None), ("OPEN SHOES", None), ("JEWELLERY", None), ("BELTS & BRACES", None),
        ("SOCKS", None), ("SUITS", None), ("FRAGRANCES", None), ("UNDERWEAR", None), ("WALLETS", None),
        ("WATCHES", None), ("BAGS & WALLETS", None), ("CAPS & HATS", None), ("SUNGLASSES", None),
        ("CAPRI PANTS", "lower"), ("BAGGY JEANS", "lower"),  # whole-word exclusions only
    ],
)
def test_tryon_slot_for_real_product_types(ptype, slot):
    assert tryon_slot(ptype) == slot


@pytest.mark.parametrize(
    ("tags", "gender"),
    [
        (["Men", "menspecialprices"], "men"),
        (["Women", "Women-Lab-25"], "women"),
        (["Men", "Women"], "unisex"),
        (["Kids", "Boys", "Men"], None),  # kids' item even if "Men" appears
        (["all-baby-boys"], None),
        (["Girls Toddler"], None),
        (["JuniorSpecialPrices", "Women"], None),
        (["2025"], None),
    ],
)
def test_adult_gender(tags, gender):
    assert adult_gender(tags) == gender


def test_parse_keeps_adult_tryon_clothing():
    p, reason = parse_shopify_product(item(), OUTFITTERS, NOW)
    assert reason == ""
    assert p.product_id == "outfitters:f1612-106"
    assert p.product_url == "https://outfitters.com.pk/products/f1612-106"
    assert p.sizes == ["M", "L"] and p.all_sizes == ["S", "M", "L"]
    assert p.price == 1290.0  # cheapest in-stock variant
    assert p.image_url == "https://cdn.shopify.com/a.jpg" and len(p.image_urls) == 2
    assert (p.gender, p.tryon_category, p.category, p.colors) == ("men", "upper", "tees", ["Royal Blue"])


@pytest.mark.parametrize(
    ("over", "reason"),
    [
        ({"tags": ["Kids", "Boys"]}, "kids_or_ungendered"),
        ({"product_type": "CLOSED SHOES"}, "not_tryon_clothing"),
        ({"images": []}, "no_image"),
        ({"variants": [{"option1": "x", "option2": "M", "price": "100", "available": False}]}, "out_of_stock"),
        ({"handle": ""}, "missing_title_or_handle"),
    ],
)
def test_parse_skips_with_reason(over, reason):
    assert parse_shopify_product(item(**over), OUTFITTERS, NOW) == (None, reason)


def _transport(routes: dict, seen: list | None = None):
    def handler(req: httpx.Request):
        if seen is not None:
            seen.append(req)
        key = req.url.path + (f"?{req.url.query.decode()}" if req.url.query else "")
        for prefix, response in routes.items():
            if key.startswith(prefix):
                return response(req) if callable(response) else response
        return httpx.Response(404)

    return httpx.MockTransport(handler)


ROBOTS_OK = httpx.Response(200, text="User-agent: *\nDisallow: /cart\nDisallow: /collections/*sort_by*\n")


def test_polite_client_obeys_robots_and_identifies_itself():
    seen = []

    async def run():
        routes = {"/robots.txt": ROBOTS_OK, "/products.json": httpx.Response(200, json={"products": []})}
        async with httpx.AsyncClient(transport=_transport(routes, seen)) as c:
            polite = PoliteClient(c, user_agent="SmartFitTest/1.0", delay=0)
            await polite.get("https://shop.test/products.json")
            with pytest.raises(RobotsDisallowed):
                await polite.get("https://shop.test/cart/add")
            with pytest.raises(RobotsDisallowed):
                await polite.get("https://shop.test/collections/men?sort_by=price")

    asyncio.run(run())
    assert all(r.headers["user-agent"] == "SmartFitTest/1.0" for r in seen)
    assert [r.url.path for r in seen].count("/robots.txt") == 1  # cached per host


def test_polite_client_waits_between_requests():
    async def run():
        routes = {"/robots.txt": httpx.Response(404), "/p": httpx.Response(200)}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            polite = PoliteClient(c, delay=0.2)
            start = time.monotonic()
            for _ in range(3):
                await polite.get("https://shop.test/p")
            return time.monotonic() - start

    # robots (no wait) + 3 gets, each at least 0.2 s after the previous request. The 0.05 s slack is
    # Windows clock granularity (~15 ms ticks; sleeps can wake a tick early); a missing delay would be 0.4 s short.
    assert asyncio.run(run()) >= 0.6 - 0.05


def test_robots_server_error_means_hands_off():
    async def run():
        async with httpx.AsyncClient(transport=_transport({"/robots.txt": httpx.Response(503)})) as c:
            await PoliteClient(c, delay=0).get("https://shop.test/products.json")

    with pytest.raises(RobotsDisallowed):
        asyncio.run(run())


def test_crawl_pages_until_empty_and_counts_skips(monkeypatch):
    monkeypatch.setattr(catalog, "FEED_PAGE_SIZE", 2)  # a full page = 2 products
    pages = {
        1: [item(handle="a"), item(handle="b", tags=["Kids"])],
        2: [item(handle="c", product_type="SOCKS"), item(handle="d", product_type="CLOSED SHOES")],
        3: [],
    }

    def products(req):
        return httpx.Response(200, json={"products": pages[int(req.url.params["page"])]})

    async def run():
        routes = {"/robots.txt": ROBOTS_OK, "/products.json": products}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            return await crawl_shopify_feed(PoliteClient(c, delay=0), OUTFITTERS, max_products=10)

    found, stats = asyncio.run(run())
    assert [p.product_id for p in found] == ["outfitters:a"]
    assert stats.pages == 3 and stats.seen == 4
    assert stats.skipped == {"kids_or_ungendered": 1, "not_tryon_clothing": 2}


def test_a_short_page_is_the_last_page():
    seen = []

    async def run():
        routes = {"/robots.txt": ROBOTS_OK,
                  "/products.json": lambda r: httpx.Response(200, json={"products": [item(handle="a")]})}
        async with httpx.AsyncClient(transport=_transport(routes, seen)) as c:
            return await crawl_shopify_feed(PoliteClient(c, delay=0), OUTFITTERS, max_products=10)

    found, stats = asyncio.run(run())
    assert len(found) == 1 and stats.pages == 1
    assert sum(r.url.path == "/products.json" for r in seen) == 1


def test_crawl_keeps_the_newest_products_and_stops_at_the_page_limit(monkeypatch):
    monkeypatch.setattr(catalog, "FEED_PAGE_SIZE", 3)

    def products(req):
        page = int(req.url.params["page"])
        return httpx.Response(200, json={"products": [
            item(handle=f"p{page}-{i}", published_at=f"2026-0{page}-0{i + 1}T00:00:00Z") for i in range(3)]})

    async def run():
        routes = {"/robots.txt": ROBOTS_OK, "/products.json": products}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            return await crawl_shopify_feed(PoliteClient(c, delay=0), OUTFITTERS, max_products=2, max_pages=3)

    found, stats = asyncio.run(run())
    assert stats.pages == 3  # never more than max_pages
    assert [p.product_id for p in found] == ["outfitters:p3-2", "outfitters:p3-1"]  # newest published first
    assert stats.kept == 2 and stats.skipped["over_brand_limit"] == 7


def test_rate_limit_waits_as_asked_then_continues():
    calls, waits = [], []

    def products(req):
        calls.append(1)
        if len(calls) <= 1:
            return httpx.Response(429, headers={"Retry-After": "7"}, text="local_rate_limited")
        return httpx.Response(200, json={"products": [item(handle="a")]})

    async def fake_sleep(seconds):
        waits.append(seconds)

    async def run():
        routes = {"/robots.txt": ROBOTS_OK, "/products.json": products}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            return await crawl_shopify_feed(PoliteClient(c, delay=0), OUTFITTERS, max_products=5, sleep=fake_sleep)

    found, _ = asyncio.run(run())
    assert waits == [7.0] and len(found) == 1  # one wait as asked, then it continues


def test_persistent_rate_limit_gives_up_for_this_refresh():
    async def no_sleep(_):
        pass

    async def run():
        routes = {"/robots.txt": ROBOTS_OK,
                  "/products.json": httpx.Response(429, headers={"Retry-After": "600"})}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            return await crawl_shopify_feed(PoliteClient(c, delay=0), OUTFITTERS, max_products=5, sleep=no_sleep)

    with pytest.raises(catalog.FeedRateLimited):
        asyncio.run(run())


CSV_HEADER = "name,product_url,image_url,extra_image_urls,price,sizes_in_stock,all_sizes,category,tryon_category,gender,colors\n"


def test_manual_csv_valid_and_invalid_rows():
    rows = [
        "Graphic Tee,https://www.breakout.com.pk/products/5bsts1-blk,https://cdn.shopify.com/s/files/1.jpg,"
        "https://cdn.shopify.com/s/files/2.jpg,\"2,999\",S|M,XS|S|M|L,t-shirts,upper,men,Black",
        "Bad host,https://evil.example/products/x,https://cdn.shopify.com/1.jpg,,100,M,,tees,upper,men,",
        "Bad image,https://www.breakout.com.pk/products/y,http://cdn.shopify.com/1.jpg,,100,M,,tees,upper,men,",
        "Bad price,https://www.breakout.com.pk/products/z,https://cdn.shopify.com/1.jpg,,abc,M,,tees,upper,men,",
        "Bad slot,https://www.breakout.com.pk/products/w,https://cdn.shopify.com/1.jpg,,100,M,,tees,hat,men,",
        "Dup,https://www.breakout.com.pk/products/5bsts1-blk,https://cdn.shopify.com/1.jpg,,100,M,,tees,upper,men,",
    ]
    products, problems = parse_manual_csv(CSV_HEADER + "\n".join(rows), "breakout")
    assert len(products) == 1
    p = products[0]
    assert p.product_id == "breakout:5bsts1-blk" and p.price == 2999 and p.sizes == ["S", "M"]
    assert p.image_urls == ["https://cdn.shopify.com/s/files/1.jpg", "https://cdn.shopify.com/s/files/2.jpg"]
    assert p.source == "manual_csv"
    assert [m.split(":")[0] for m in problems] == ["row 3", "row 4", "row 5", "row 6", "row 7"]


def test_manual_csv_requires_columns_and_known_retailer():
    assert parse_manual_csv("name,price\n", "breakout")[1][0].startswith("Missing columns")
    assert parse_manual_csv(CSV_HEADER, "outfitters")[1][0].startswith("Unknown retailer")


def test_snapshot_store_round_trip(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "supabase_service_key", "")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    a, _ = parse_shopify_product(item(handle="a"), OUTFITTERS, NOW)
    b, _ = parse_shopify_product(item(handle="b"), OUTFITTERS, NOW)
    a2 = a.model_copy(update={"price": 999.0})

    async def run():
        async with httpx.AsyncClient() as c:
            assert await catalog_store.save_products(c, [a, b]) == "snapshot"
            await catalog_store.save_products(c, [a2])  # upsert by product_id
            return await catalog_store.load_products(c)

    loaded = {p.product_id: p for p in asyncio.run(run())}
    assert set(loaded) == {"outfitters:a", "outfitters:b"}
    assert loaded["outfitters:a"].price == 999.0


def test_refresh_reports_robots_block_instead_of_working_around_it(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "supabase_service_key", "")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    monkeypatch.setattr(settings, "scraper_rate_limit_seconds", 0)
    blocked = httpx.Response(200, text="User-agent: *\nDisallow: /\n")

    async def run():
        async with httpx.AsyncClient(transport=_transport({"/robots.txt": blocked})) as c:
            return await refresh_feeds(c, ["outfitters"], 5, notify=False)

    result = asyncio.run(run())
    assert "robots.txt forbids" in result.errors["outfitters"]
    assert result.kept == {}


# ── product size charts ──────────────────────────────────────────────────

REAL_JEANS_ROWS = [  # Outfitters f0647-109, as published
    ["SIZE", "30", "32", "34", "36", "38"],
    ["Inseam Length", "78", "78", "78", "78", "78"],
    ["Round Waist Width ", "87", "92", "97", "102", "107"],
    ["Round Hip Width", "105", "110", "115", "120", "125"],
    ["Round Thigh At Crotch", "64", "66.5", "69", "71.5", "74"],
]
REAL_TEE_ROWS = [  # Outfitters f1465-106, as published
    ["SIZE", "S", "M", "L", "XL"],
    ["Body Length", "62", "64", "66", "68"],
    ["Chest Width", "55", "58", "61", "64"],
    ["Across Shoulder", "52", "54", "56", "58"],
    ["Sleeve Length", "21", "22", "23", "24"],
]


def test_parse_round_rows_as_circumference():
    chart = parse_chart(REAL_JEANS_ROWS)
    assert chart["30"] == {"waist_cm": 87.0, "hip_cm": 105.0}
    assert chart["38"] == {"waist_cm": 107.0, "hip_cm": 125.0}


def test_parse_flat_width_is_doubled():
    assert parse_chart(REAL_TEE_ROWS) == {
        "S": {"chest_cm": 110.0}, "M": {"chest_cm": 116.0}, "L": {"chest_cm": 122.0}, "XL": {"chest_cm": 128.0},
    }


@pytest.mark.parametrize(
    "rows",
    [
        [["SIZE", "S", "M"], ["Waist", "80", "84"]],  # flat or round? ambiguous -> not guessed
        [["SIZE", "S", "M"], ["Chest Width", "15", "16"]],  # x2 = 30 cm: implausible -> dropped
        [["SIZE", "S", "M"], ["Round Waist Width", "80"]],  # ragged row
        [["SIZE", "S", "M"], ["Body Length", "62", "64"]],  # nothing comparable
        [["Inseam", "78"]],  # no SIZE header
        [],
    ],
)
def test_parse_never_guesses(rows):
    assert parse_chart(rows) is None


def test_chart_tag_found_in_tags():
    assert chart_tag(["Men", "f0647-109-SimplifiedSizechart"]) == "f0647-109-SimplifiedSizechart"
    assert chart_tag(["Men"]) is None


def test_size_charts_fetched_once_then_reused():
    calls = []

    def chart(req):
        calls.append(req.url.params["tags"])
        return httpx.Response(200, json={"size_chart": {"is_active": True, "size_chart_data": REAL_JEANS_ROWS}})

    a, _ = parse_shopify_product(item(handle="a", tags=["Men", "a-SimplifiedSizechart"]), OUTFITTERS, NOW)
    b, _ = parse_shopify_product(item(handle="b"), OUTFITTERS, NOW)  # no chart tag

    async def run(products, previous):
        routes = {"/robots.txt": httpx.Response(200, text="User-agent: *\nDisallow:\n"), "/api/product_size_charts": chart}
        async with httpx.AsyncClient(transport=_transport(routes)) as c:
            counts = await attach_size_charts(PoliteClient(c, delay=0), OUTFITTERS, products, previous)
            return products, counts

    first, counts = asyncio.run(run([a, b], {}))
    assert counts == {"fetched": 1, "no_chart_tag": 1}
    assert first[0].size_chart["32"]["waist_cm"] == 92.0 and first[1].size_chart is None

    again, counts = asyncio.run(run([a, b], {p.product_id: p for p in first}))
    assert counts == {"reused": 1, "no_chart_tag": 1}
    assert calls == ["a-SimplifiedSizechart"]  # only the first refresh asked
    assert again[0].size_chart == first[0].size_chart


def test_elastic_waist_keeps_relaxed_and_stretched():
    rows = [  # Outfitters f0672-108 jogger, as published
        ["SIZE", "S", "M", "L", "XL"],
        ["Round Waist Width Relaxed", "70", "76", "82", "88"],
        ["Round Waist Width Stretched", "90", "96", "102", "108"],
        ["Round Hip Width", "100", "106", "112", "118"],
    ]
    assert parse_chart(rows)["S"] == {"waist_relaxed_cm": 70.0, "waist_stretched_cm": 90.0, "hip_cm": 100.0}
