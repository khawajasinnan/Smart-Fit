"""Realistic sizes in recommendations (21 Nov 2026, the user's report: a man with
XL/XXL measurements was shown products sold only in small sizes)."""

from __future__ import annotations

import pytest

from services.recommendation.size_match import fit_products, shown_size, user_letter_size
from shared.schemas.recommendation import UserProfileInput
from shared.size_estimate import estimate_size, letter_sizes, size_kind

BIG_MAN = UserProfileInput(gender="male", height_cm=180, weight_kg=95, chest_cm=112, waist_cm=100, hip_cm=108)


@pytest.mark.parametrize("label, letters", [
    ("M", {"M"}), ("Small", {"S"}), ("X-Large", {"XL"}), ("Extra Small", {"XS"}), ("XX-Large", {"XXL"}),
    ("L (14)", {"L"}), ("10 (S)", {"S"}), ("XL RGF", {"XL"}), ("M SLF", {"M"}),
    ("S-M", {"S", "M"}), ("SM", {"S", "M"}), ("ML", {"M", "L"}), ("L/XL", {"L", "XL"}), ("SMALL MEDIUM", {"S", "M"}),
    ("2XL", {"XXL"}), ("3 XL", {"3XL"}), ("XXXL", {"3XL"}), ("4XL", {"4XL"}),
    # other size systems are never converted
    ("W 34 / L 31", set()), ("15.5", set()), ('40"', set()), ("UNSTITCHED", set()), ("FREE SIZE", set()), ("2-3Y", set()),
])
def test_store_size_labels_are_read_as_sizes(label, letters):
    assert letter_sizes(label) == letters


def test_size_kinds():
    assert size_kind("Free Size") == "one" and size_kind("F.S") == "one"
    assert size_kind("Customized") == "custom" and size_kind("Make To Order") == "custom"
    assert size_kind("4.5 METERS") == "fabric" and size_kind("Unstitched") == "fabric"
    assert size_kind("L (14)") == "letter" and size_kind("15.5") == "other"


def test_the_size_follows_the_largest_measurement():
    assert estimate_size({}, "male", profile_chest=112, profile_waist=100) == ("XXL", "profile_measurements")
    # M chest and waist, XL hips: XL ("go by your larger measurement")
    assert estimate_size({}, "female", profile_chest=90, profile_waist=72, profile_hip=110)[0] == "XL"
    # hips don't decide men's sizes (the men's chart has no hip)
    assert estimate_size({}, "male", profile_chest=95, profile_hip=120)[0] == "M"


def test_bigger_bodies_get_3xl_and_4xl_not_xxl():
    assert estimate_size({}, "male", profile_chest=122)[0] == "3XL"
    assert estimate_size({}, "male", profile_chest=140)[0] == "4XL"
    assert estimate_size({}, "female", profile_chest=118)[0] == "3XL"
    assert estimate_size({}, "male", height_cm=170, weight_kg=110)[0] == "3XL"  # BMI 38


def test_user_size_from_profile_or_chat():
    assert user_letter_size(BIG_MAN) == "XXL"
    assert user_letter_size(BIG_MAN, requested="Large") == "L"  # the chat's size wins
    assert user_letter_size(UserProfileInput(gender="female")) is None  # nothing to go on: no guess


def item(sizes, all_sizes=None, chart=None, title="Shirt"):
    return {"id": title, "title": title, "sizes": sizes, "all_sizes": all_sizes or sizes, "size_chart": chart or {}}


def test_products_not_made_in_the_users_size_are_left_out():
    raw = [item(["S", "M"], title="small only"), item(["S", "M", "XL", "XXL"], title="has XXL"),
           item(["Small", "Medium", "Large", "XL", "XXL"], title="words"), item(["XL", "2XL"], title="2XL")]
    kept, dropped = fit_products(raw, BIG_MAN)
    assert [i["title"] for i in kept] == ["has XXL", "words", "2XL"] and dropped == 1
    assert [shown_size(i) for i in kept] == ["XXL", "XXL", "2XL"]  # the store's own label


def test_sold_out_in_the_users_size_is_left_out():
    kept, dropped = fit_products([item(["S", "M"], all_sizes=["S", "M", "XXL"])], BIG_MAN)
    assert kept == [] and dropped == 1


def test_other_size_systems_stay_without_a_made_up_size():
    raw = [item(["30", "32", "34"], title="jeans"), item(["15.5", "16"], title="formal shirt"),
           item(["UNSTITCHED"], title="fabric"), item(["8", "10", "12"], title="uk sizes")]
    kept, dropped = fit_products(raw, BIG_MAN)
    assert dropped == 0 and [shown_size(i) for i in kept] == [None, None, None, None]


def test_one_size_and_made_to_measure_fit_everyone():
    kept, _ = fit_products([item(["Free Size"]), item(["Customized"], title="custom")], BIG_MAN)
    assert [shown_size(i) for i in kept] == ["Free Size", "Customized"]


def test_the_products_own_chart_decides_when_it_has_one():
    chart = {"S": {"chest_cm": 110.0}, "M": {"chest_cm": 116.0}, "L": {"chest_cm": 122.0}}  # Outfitters' relaxed fit
    kept, _ = fit_products([item(["S", "M", "L"], chart=chart)], BIG_MAN)
    assert shown_size(kept[0]) == "M"  # 112 cm chest + 4 cm room fits its M, not "XXL"


def test_without_measurements_nothing_is_filtered():
    raw = [item(["S", "M"])]
    assert fit_products(raw, UserProfileInput(gender="male")) == (raw, 0)


def test_the_size_the_user_says_they_buy_comes_before_the_estimate():
    told = BIG_MAN.model_copy(update={"usual_size": "XL"})
    assert user_letter_size(told) == "XL"
    assert user_letter_size(told, requested="M") == "M"  # the chat still wins
    assert user_letter_size(BIG_MAN.model_copy(update={"usual_size": "nonsense"})) == "XXL"
