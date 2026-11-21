"""SmartFit is for men and women 18+: children's wear never reaches the app,
from the live chat search or the catalog, and adult styles that merely
contain "boy", "baby" or "mini" survive."""

import asyncio

import httpx
import pytest

import services.scraper.generic_spider as spider
from shared.audience import is_age_size, is_kids_item
from shared.brands import PAKISTANI_BRANDS


@pytest.mark.parametrize(
    "kwargs",
    [
        {"title": "Kids Printed Kurta"},
        {"title": "Boys Denim Jacket"},
        {"title": "Embroidered Frock", "category": "girls"},
        {"title": "Cotton Romper", "tags": ["Baby"]},
        {"title": "Graphic Tee", "product_url": "https://x.pk/products/junior-graphic-tee"},
        {"title": "Shalwar Kameez", "sizes": ["2-3Y", "3-4Y", "4-5Y"]},
        {"title": "Party Dress", "sizes": ["6-12M", "12-18 months"]},
        {"title": "Eid Collection for Toddlers"},
    ],
)
def test_childrens_wear_is_flagged(kwargs):
    assert is_kids_item(**kwargs)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"title": "Boyfriend Fit Jeans"},
        {"title": "Baby Pink Lawn Suit"},
        {"title": "Babydoll Dress"},
        {"title": "Denim Mini Skirt"},
        {"title": "Girlfriend Jeans", "category": "jeans"},
        {"title": "Men's Polo", "sizes": ["S", "M", "L", "XL"]},
        {"title": "Kurta", "sizes": ["S", "M", "L", "10Y"]},  # one odd size isn't a children's run
        {"title": "Waist 30 Chinos", "sizes": ["30", "32", "34"]},
    ],
)
def test_adult_styles_are_kept(kwargs):
    assert not is_kids_item(**kwargs)


def test_age_sizes():
    assert all(is_age_size(s) for s in ("3-4Y", "3 - 4 years", "6-12M", "2T", "8Y", "10 yrs", "3 to 4 Y"))
    assert not any(is_age_size(s) for s in ("M", "XL", "32", "UK 8", "Free Size"))


def test_no_kids_brand_is_searched():
    assert "Minnie Minors" not in {b.name for b in PAKISTANI_BRANDS}
    for b in PAKISTANI_BRANDS:
        for slugs in b.collection_slugs.values():
            assert not any(is_kids_item(category=s) for s in slugs), (b.name, slugs)


def _feed(*products):
    return httpx.MockTransport(lambda r: httpx.Response(200, json={"products": list(products)}))


def _product(handle, title, tags=(), sizes=("S", "M")):
    return {"id": handle, "handle": handle, "title": title, "tags": list(tags), "product_type": "Kurta",
            "images": [{"src": f"https://cdn.x/{handle}.jpg"}],
            "variants": [{"price": "2990", "available": True, "option1": s, "title": s} for s in sizes]}


def test_live_shopify_search_drops_kids_items():
    brand = next(b for b in PAKISTANI_BRANDS if not b.html_only)
    feed = _feed(
        _product("lawn-kurta", "Lawn Kurta", ["women"]),
        _product("kids-kurta", "Kids Kurta"),
        _product("boys-kurta", "Kurta", ["Boys"]),
        _product("little-kurta", "Kurta", sizes=("2-3Y", "4-5Y")),
    )

    async def run():
        async with httpx.AsyncClient(transport=feed) as client:
            return await spider.fetch_shopify_collection(client, brand, "women", "kurta", None, 10)

    titles = [(p["title"], p["product_url"].rsplit("/", 1)[1]) for p in asyncio.run(run())]
    assert titles == [("Lawn Kurta", "lawn-kurta")]
