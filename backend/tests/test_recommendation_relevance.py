"""Relevance rules found by the live check of 18 Nov 2026:
"jeans" showed denim shirts/sweaters, and "something casual" showed
PKR 500,000 bridal sets on a PKR 8,000 profile."""

from __future__ import annotations

import pytest

from services.recommendation.main import everyday_filter
from shared.taxonomy import product_conflicts_with_category, product_matches_category


@pytest.mark.parametrize("title", [
    "Black Denim Shirt (CSD-046)", "Blue Button Down Denim Casual Shirt", "D-Denim V-Neck Full Sleeves Sweater",
    "Denim Jacket", "Denim Skirt", "Washed Denim Top", "Denim Hoodie",
])
def test_denim_tops_are_not_jeans(title):
    assert product_matches_category(title, ["men"], None, "jeans")  # "denim" is a jeans word ...
    assert product_conflicts_with_category(title, ["men"], "jeans")  # ... but a top is never jeans


@pytest.mark.parametrize("title", ["Denim Trousers", "BLACK REGULAR FIT JEANS", "Loose Fit Jeans - FMBP6-037",
                                   "Slim Fit Denim Pant", "Mom Jeans"])
def test_real_jeans_are_kept(title):
    assert product_matches_category(title, ["men"], None, "jeans")
    assert not product_conflicts_with_category(title, ["men"], "jeans")


def test_trousers_request_drops_shirts_but_keeps_trousers():
    assert product_conflicts_with_category("Cotton Shirt & Trouser Co-ord", [], "trouser")
    assert not product_conflicts_with_category("Cotton Dress Pant Trouser", [], "trouser")


def item(title, price, category=""):
    return {"title": title, "price_pkr": price, "category": category}


BRIDAL = [item("Ivory Nikah Bridal Peshwas Set (D-02)", 500000), item("Burgundy Lehenga Set", 4499),
          item("Ivory Sherwani", 60000, "groom")]
EVERYDAY = [item(f"Cotton Kurti {i}", 2000 + i) for i in range(10)]


def test_bridal_wear_only_when_asked_for():
    casual = everyday_filter(BRIDAL + EVERYDAY, {"combined_text": "something casual"}, 8)
    assert casual == EVERYDAY
    for asked in ({"combined_text": "show me a bridal lehenga"}, {"combined_text": "x", "exact_category": "sherwani"},
                  {"combined_text": "outfit please", "occasion": "nikah"}, {"combined_text": "my baraat"}):
        assert everyday_filter(BRIDAL + EVERYDAY, asked, 8)[:3] == BRIDAL, asked


def test_far_over_the_profile_budget_is_left_out_when_enough_remain():
    ctx = {"combined_text": "kurti", "profile_budget_max": 3000}
    pricey = [item("Luxury Kurti", 20000)]
    assert everyday_filter(pricey + EVERYDAY, ctx, 8) == EVERYDAY  # 20,000 > 3 x 3,000
    assert everyday_filter(pricey + EVERYDAY[:2], ctx, 8) == pricey + EVERYDAY[:2]  # too few otherwise: kept
    # a budget named in the chat is handled (strictly) elsewhere: no extra cut here
    assert everyday_filter(pricey + EVERYDAY, {**ctx, "budget_max": 50000}, 8) == pricey + EVERYDAY
