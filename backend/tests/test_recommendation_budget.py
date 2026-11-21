"""Budget rules (spec §23.17): a budget asked for in the chat is a hard
limit; the onboarding profile's budget only ranks, so a low profile budget
can't hide whole categories (the "no hoodie" bug)."""

from datetime import UTC, datetime

import httpx
from fastapi.testclient import TestClient

import services.recommendation.main as rec
from shared.schemas.catalog import ScrapedProduct


def product(handle, price, name="Relaxed Fit Hoodie", retailer="outfitters"):
    return ScrapedProduct(product_id=f"{retailer}:{handle}", retailer=retailer, name=name,
                          product_url=f"https://{retailer}.com.pk/products/{handle}", image_url="https://cdn.shopify.com/h.jpg",
                          price=price, sizes=["M"], category="sweatshirts", tryon_category="upper", gender="men",
                          colors=["Black"], source="shopify_feed", scraped_at=datetime(2026, 11, 8, tzinfo=UTC))


def recommend(monkeypatch, body):
    async def fake_load(_client):
        return [product("relaxed", 6490), product("graphic", 3249, "Graphic Hoodie", "breakout"),
                product("slogan", 7490, "Slogan Print Hoodie")]

    monkeypatch.setattr(rec, "load_products", fake_load)
    monkeypatch.setattr(rec, "_catalog_items", [])
    monkeypatch.setattr(rec, "_catalog_loaded_at", None)
    monkeypatch.setattr(rec.settings, "live_check_enabled", False)
    with TestClient(rec.app) as c:
        rec._client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(404)))
        return c.post("/recommend/app", json={"max_products": 6, **body}).json()


def test_a_low_profile_budget_no_longer_hides_hoodies(monkeypatch):
    body = recommend(monkeypatch, {"profile": {"gender": "male", "budget_min": 1000, "budget_max": 3000},
                                   "user_message": "hoodie", "dynamic_prefs": {"garment": "hoodie"}})
    assert len(body["products"]) == 3
    assert "above your usual budget of PKR 3,000" in body["message"]
    assert body["products"][0]["price_pkr"] == 3249  # the closest to the budget ranks first
    assert any("above your usual budget" in r for r in body["products"][-1]["match_reasons"])


def test_a_budget_asked_for_in_the_chat_is_a_hard_limit(monkeypatch):
    body = recommend(monkeypatch, {"profile": {"gender": "male"}, "user_message": "hoodie under 7000",
                                   "dynamic_prefs": {"garment": "hoodie", "budget_max": 7000}})
    assert sorted(p["price_pkr"] for p in body["products"]) == [3249, 6490]


def test_nothing_under_the_chat_budget_says_what_the_cheapest_costs(monkeypatch):
    body = recommend(monkeypatch, {"profile": {"gender": "male"}, "user_message": "hoodie under 2000",
                                   "dynamic_prefs": {"garment": "hoodie", "budget_max": 2000}})
    assert body["products"] == []
    assert "No hoodie under PKR 2,000" in body["message"] and "PKR 3,249 at Breakout" in body["message"]


def test_an_empty_message_returns_picks_for_the_profile(monkeypatch):
    """Home's "Trending for you" asks without a message; it used to crash (500)."""
    body = recommend(monkeypatch, {"profile": {"gender": "male"}, "user_message": ""})
    assert body["products"], body
    assert "No products matched" not in body["message"]


def test_browsing_ranks_the_whole_catalog_but_keeps_hard_exclusions(monkeypatch):
    """No message: every (non-excluded) item is a candidate, not only ones matching a default garment."""
    body = recommend(monkeypatch, {"profile": {"gender": "male", "budget_max": 3000}, "user_message": "",
                                   "taste": {"excluded_product_ids": ["outfitters:slogan"]}})
    ids = {p["id"] for p in body["products"]}
    assert ids == {"outfitters:relaxed", "breakout:graphic"}  # the rejected one stays out
