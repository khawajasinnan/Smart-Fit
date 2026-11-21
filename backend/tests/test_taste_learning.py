"""Learning from feedback (spec §23.15): the taste profile built from loves,
"not for me" and quiz answers re-ranks recommendations; a rejected product
never comes back."""

from fastapi.testclient import TestClient

import services.recommendation.main as rec
from services.recommendation.keyword_ranking import rank_products, taste_adjustment
from shared.schemas.recommendation import UserProfileInput
from shared.taxonomy import build_search_context

PROFILE = UserProfileInput(gender="female")


def item(pid, brand, title, colors=("black",), category="kurta", price=4990):
    return {"id": pid, "brand": brand, "title": title, "category": category, "price_pkr": price,
            "product_url": f"https://{brand.lower()}.pk/products/{pid}", "colors": list(colors),
            "tags": ["female"], "sizes": ["M"], "in_stock": True}


def ranked(products, taste):
    context = build_search_context(PROFILE, "show me kurtas", "", "", {})
    context["taste"] = taste
    return [p.id for p in rank_products(products, PROFILE, context, 10)]


def test_liked_brand_and_colour_rank_first_disliked_last():
    products = [item("a", "Zeen", "Lawn Kurta", ("blue",)), item("b", "Lulusar", "Lawn Kurta", ("pink",)),
                item("c", "Saya", "Lawn Kurta", ("black",))]
    taste = {"liked_brands": ["Lulusar"], "liked_colors": ["pink"], "disliked_brands": ["Zeen"]}
    order = ranked(products, taste)
    assert order[0] == "b" and order[-1] == "a"


def test_rejected_product_is_never_shown_by_id_or_link():
    products = [item("a", "Zeen", "Lawn Kurta"), item("b", "Saya", "Lawn Kurta")]
    assert ranked(products, {"excluded_product_ids": ["a"]}) == ["b"]
    assert ranked(products, {"excluded_product_ids": ["https://saya.pk/products/b"]}) == ["a"]


def test_style_lean_and_price_point():
    eastern = item("e", "Saya", "Embroidered Lawn Kurta", category="kurta")
    western = item("w", "Saya", "Graphic Tee", category="tees")
    assert taste_adjustment(eastern, "embroidered lawn kurta", {"style_lean": "eastern"})[0] > 0
    assert taste_adjustment(western, "graphic tee", {"style_lean": "eastern"})[0] < 0
    near = taste_adjustment(item("p", "Saya", "Kurta", price=5200), "kurta", {"price_point": 5000})[0]
    far = taste_adjustment(item("q", "Saya", "Kurta", price=25000), "kurta", {"price_point": 5000})[0]
    assert near > far


def test_no_taste_changes_nothing():
    assert taste_adjustment(item("a", "Zeen", "Kurta"), "kurta", None) == (0, [])


def test_app_endpoint_accepts_a_taste_profile(monkeypatch):
    from datetime import UTC, datetime

    import httpx

    from shared.schemas.catalog import ScrapedProduct

    def product(handle, retailer):
        return ScrapedProduct(product_id=f"{retailer}:{handle}", retailer=retailer, name="Lawn Kurta",
                              product_url=f"https://{retailer}.pk/products/{handle}", image_url="https://cdn.x/k.jpg",
                              price=4990, sizes=["M"], category="kurta", tryon_category="upper", gender="women",
                              colors=["Black"], source="shopify_feed", scraped_at=datetime(2026, 11, 8, tzinfo=UTC))

    async def fake_load(_client):
        return [product("one", "zeen"), product("two", "saya")]

    monkeypatch.setattr(rec, "load_products", fake_load)
    monkeypatch.setattr(rec, "_catalog_items", [])
    monkeypatch.setattr(rec, "_catalog_loaded_at", None)
    monkeypatch.setattr(rec.settings, "live_check_enabled", False)
    with TestClient(rec.app) as c:
        rec._client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(404)))
        body = c.post("/recommend/app", json={
            "profile": {"gender": "female"}, "user_message": "lawn kurta", "max_products": 6,
            "taste": {"excluded_product_ids": ["zeen:one"], "liked_brands": ["Saya"], "style_lean": "eastern"},
        }).json()
    assert [p["id"] for p in body["products"]] == ["saya:two"]


def test_feedback_rows_become_labelled_examples():
    import importlib.util
    from pathlib import Path

    spec = importlib.util.spec_from_file_location(
        "export_feedback_dataset", Path(__file__).resolve().parents[1] / "scripts" / "export_feedback_dataset.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    love = mod.to_example({"user_id": "u1", "product_id": "saya:x", "feedback_type": "loved_fit",
                           "feedback_data": {"brand": "Saya", "title": "Kurta", "price_pkr": 4990}}, "s")
    nope = mod.to_example({"user_id": "u1", "product_id": "zeen:y", "feedback_type": "disliked",
                           "feedback_data": {"brand": "Zeen", "source": "notification"}}, "s")
    vote = mod.to_example({"user_id": "u1", "product_id": "quiz:eastern_western", "feedback_type": "rating",
                           "feedback_data": {"quiz": "eastern_western", "choice": "eastern"}}, "s")
    assert love["label"] == 1 and love["product"]["id"] == "saya:x" and love["product"]["brand"] == "Saya"
    assert nope["label"] == 0 and nope["source"] == "notification"
    assert vote == {"user": love["user"], "source": "app", "at": None, "kind": "quiz", "quiz": "eastern_western",
                    "label": "eastern"}
    assert love["user"] != "u1" and len(love["user"]) == 16  # pseudonymised
    assert mod.to_example({"user_id": "u1", "feedback_type": "comment"}, "s") is None
