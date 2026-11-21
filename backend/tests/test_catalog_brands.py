"""Multi-brand catalog (spec §23.12): Pakistani garment types, gender from a
product's own labels before the brand's audience, the brand registry, and a
brand's stale products removed only after a successful refresh."""

import asyncio
from datetime import UTC, datetime, timedelta

import httpx
import pytest

pytest.importorskip("protego")

from shared import catalog_store  # noqa: E402
from shared.config import settings  # noqa: E402
from shared.feed_brands import BY_KEY, FEED_BRANDS, brand_name  # noqa: E402
from services.scraper.catalog import classify_garment, parse_shopify_product, product_gender  # noqa: E402
from services.scraper.catalog_service import refresh_feeds  # noqa: E402

NOW = datetime(2026, 11, 8, tzinfo=UTC)


@pytest.mark.parametrize(
    ("ptype", "title", "kind"),
    [
        ("Kurta", "Embroidered Cotton Kurta", "upper"),
        ("", "Lawn Kurti", "upper"),
        ("Kameez", "Printed Kameez", "upper"),
        ("", "Men's Waistcoat", "upper"),
        ("Bottoms", "Cotton Shalwar", "lower"),
        ("", "Straight Trouser", "lower"),
        ("", "Silk Palazzo", "lower"),
        ("Stitched", "Embroidered 3 Piece Suit", "dress"),
        ("", "2pc Lawn Kameez Trouser", "dress"),
        ("", "Chiffon Frock", "dress"),
        ("", "Bridal Lehenga", "dress"),
        ("", "Men Kurta Shalwar", "dress"),
        ("Unstitched", "Printed Lawn 3 Piece Unstitched", "fabric"),
        ("", "Khaddar Fabric 2.5 Metre", "fabric"),
        ("Dress Shirts", "Pink Dress Shirt", "upper"),  # a dress shirt is a shirt
        ("SUITS", "Two Piece Suit", "excluded"),  # a Western jacket + trousers suit (the type decides)
        ("", "Embroidered Gharara", "dress"),
        ("SUITS", "Navy Suit", "excluded"),  # a men's suit: not tried on
        ("Footwear", "Leather Khussa", "excluded"),
        ("", "Embroidered Shawl", "excluded"),
        ("Makeup", "Liquid Foundation", "excluded"),
        ("Home", "Cotton Bed Sheet Set", "excluded"),
        ("", "Gift Card", "excluded"),
        ("Eid Collection", "Rose", None),  # no clothing word: skipped, not guessed
    ],
)
def test_pakistani_garment_kinds(ptype, title, kind):
    assert classify_garment(ptype, title) == kind


# Real products from the 8 Nov 2026 dry run that the first rules got wrong.
@pytest.mark.parametrize(
    ("ptype", "title", "tags", "gender", "kind"),
    [
        ("Ready to Wear", "Shab", ["3 Piece", "dhldes:Women stitched shirt dupatta and trouser"], "women", "dress"),
        ("", "Stitched Embroidered Lawn Suit", ["3-piece"], "women", "dress"),
        ("Solid", "Premium Blended Wear Stitched Suit", [], "women", "dress"),
        ("Printed", "Printed Linen Stitched 2 Piece (Shirt/Dupatta)", [], "women", "dress"),
        ("Embroidered", "Printed Embroidered Stitched Self Lawn 3 Piece With Chiffon Dupatta", [], "women", "dress"),
        ("Embroidered", "Unstitched Printed Embroidered Lawn 3 Piece With Chiffon Dupatta", [], "women", "fabric"),
        ("Designer Suit", "Chikan Kurta Pajama 1", [], "men", "dress"),
        ("Sherwani", "Andaaz Short Sherwani 003", [], "men", "upper"),
        ("Men Division", "Cream Jubba", ["men"], "men", "dress"),
        ("Men", "Regular Fit Basic Suits", ["Men Suits"], "men", "excluded"),  # Western suit
        ("Women", "Acrylic Dobby Embroidered Shawl", ["Shawls"], "women", "excluded"),
        ("Accessories", "Tan Mens Peshawari", ["Men Peshawari Chappal"], "men", "excluded"),
        ("island_generated", "Gift Packaging", [], "men", "excluded"),
    ],
)
def test_real_dry_run_cases(ptype, title, tags, gender, kind):
    assert classify_garment(ptype, title, tags, gender) == kind


@pytest.mark.parametrize(
    ("tags", "title", "ptype", "audience", "gender"),
    [
        (["Women"], "Kurta", "", "men", "women"),  # the product's own tag wins over the brand
        ([], "Men's Kurta", "", "both", "men"),
        ([], "Ladies Lawn Suit", "", "both", "women"),
        ([], "Kurta", "Menswear", "both", "men"),
        ([], "Kurta", "", "women", "women"),  # nothing on the product: the brand's audience
        ([], "Kurta", "", "both", None),  # mixed brand, no clue: skipped, not guessed
        ([], "Couple Hoodie for Men and Women", "", "both", "unisex"),
    ],
)
def test_gender_from_the_product_before_the_brand(tags, title, ptype, audience, gender):
    assert product_gender(tags, title, ptype, "x", audience) == gender


def _feed_item(**over):
    base = {"title": "Embroidered Lawn Kurta", "handle": "lawn-kurta", "product_type": "Kurta", "tags": [],
            "options": [{"name": "Size", "values": ["S", "M"]}],
            "variants": [{"option1": "S", "price": "4990.00", "available": True},
                         {"option1": "M", "price": "4990.00", "available": False}],
            "images": [{"src": "https://cdn.shopify.com/k.jpg"}]}
    return base | over


def test_unstitched_fabric_is_kept_without_a_tryon_slot():
    p, reason = parse_shopify_product(_feed_item(title="Lawn 3 Piece Unstitched", product_type="Unstitched"),
                                      BY_KEY["sana-safinaz"], NOW)
    assert reason == "" and p.tryon_category is None and p.gender == "women"


def test_womens_brand_kurta_and_kids_item():
    p, _ = parse_shopify_product(_feed_item(), BY_KEY["zara-shahjahan"], NOW)
    assert (p.gender, p.tryon_category, p.retailer) == ("women", "upper", "zara-shahjahan")
    assert p.product_url == "https://zarashahjahan.com/products/lawn-kurta"
    _, reason = parse_shopify_product(_feed_item(title="Girls Kurta"), BY_KEY["zara-shahjahan"], NOW)
    assert reason == "kids_or_ungendered"


def test_brand_registry():
    keys = [b.key for b in FEED_BRANDS]
    assert len(keys) == len(set(keys)) >= 60
    assert all(b.base_url.startswith("https://") and b.audience in ("men", "women", "both") for b in FEED_BRANDS)
    assert brand_name("maryum-n-maria") == "Maryum N Maria" and brand_name("breakout") == "Breakout"


def _store_transport(pages: dict):
    def handler(req: httpx.Request):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        if req.url.path == "/products.json":
            items = pages.get(req.url.host, [])
            return httpx.Response(200, json={"products": items if int(req.url.params["page"]) == 1 else []})
        return httpx.Response(404)
    return httpx.MockTransport(handler)


def test_refresh_saves_and_removes_only_that_brands_stale_feed_products(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_store", "snapshot")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    old = NOW - timedelta(days=1)
    zara = BY_KEY["zara-shahjahan"]
    stale, _ = parse_shopify_product(_feed_item(handle="sold-out"), zara, old)
    other_brand, _ = parse_shopify_product(_feed_item(handle="keep-me"), BY_KEY["lulusar"], old)
    admin_added = stale.model_copy(update={"product_id": "zara-shahjahan:admin", "source": "admin"})
    asyncio.run(catalog_store.save_products(httpx.AsyncClient(), [stale, other_brand, admin_added]))

    async def run():
        transport = _store_transport({"zarashahjahan.com": [_feed_item(handle="new-kurta")]})
        async with httpx.AsyncClient(transport=transport) as c:
            return await refresh_feeds(c, ["zara-shahjahan", "not-a-brand"], 10, notify=False)

    result = asyncio.run(run())
    assert result.kept == {"zara-shahjahan": 1} and result.removed == {"zara-shahjahan": 1}
    assert "not-a-brand" in result.errors
    ids = {p.product_id for p in asyncio.run(catalog_store.load_products(httpx.AsyncClient()))}
    assert ids == {"zara-shahjahan:new-kurta", "lulusar:keep-me", "zara-shahjahan:admin"}


def test_a_failed_brand_keeps_its_previous_products(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_store", "snapshot")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    before, _ = parse_shopify_product(_feed_item(handle="still-here"), BY_KEY["lulusar"], NOW)
    asyncio.run(catalog_store.save_products(httpx.AsyncClient(), [before]))

    def down(req):
        if req.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(503)

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(down)) as c:
            return await refresh_feeds(c, ["lulusar"], 10, notify=False)

    result = asyncio.run(run())
    assert "lulusar" in result.errors and "previous products kept" in result.errors["lulusar"]
    assert [p.product_id for p in asyncio.run(catalog_store.load_products(httpx.AsyncClient()))] == ["lulusar:still-here"]


def test_zero_price_placeholder_is_skipped_not_a_crash():
    zero = _feed_item(variants=[{"option1": "S", "price": "0.00", "available": True}])
    assert parse_shopify_product(zero, BY_KEY["zara-shahjahan"], NOW) == (None, "no_price")
