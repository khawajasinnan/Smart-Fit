"""Culture outfit guide (21 Nov 2026): every Pakistani culture in the profile, for men and women."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from services.chat_orchestrator.system_prompt import SYSTEM_PROMPT
from shared.culture_styles import CULTURES, culture_guide, culture_key, culture_words
from shared.taxonomy import ETHNICITY_KEYWORDS


@pytest.mark.parametrize("name, key", [
    ("Punjabi", "punjabi"), ("Sindhi", "sindhi"), ("Balochi", "balochi"), ("Baloch", "balochi"),
    ("Pathan", "pathan"), ("Pashtun", "pathan"), ("Pakhtun", "pathan"), ("Saraiki", "saraiki"), ("Siraiki", "saraiki"),
    ("Gilgiti", "gilgiti"), ("Gilgit-Baltistan", "gilgiti"), ("Balti", "gilgiti"), ("Hunza", "gilgiti"),
    ("South Punjab", "punjabi"),
])
def test_culture_names_people_use(name, key):
    assert culture_key(name) == key


def test_unknown_or_empty_culture_has_no_guide():
    assert culture_key("") is None and culture_key(None) is None
    assert culture_guide("Kashmiri", "male") is None


def test_every_culture_has_looks_for_men_and_women():
    for key, c in CULTURES.items():
        assert c["men"] and c["women"], key
        for outfit in c["men"] + c["women"]:
            assert outfit["name"] and len(outfit["pieces"]) >= 2 and outfit["when"] and outfit["search"], (key, outfit)


def test_the_guide_shows_the_users_own_gender():
    men = culture_guide("Punjabi", "male")
    assert men["gender"] == "men" and any("Pagg" in p for o in men["outfits"] for p in o["pieces"])
    women = culture_guide("Punjabi", "female")
    assert women["gender"] == "women" and any("Phulkari dupatta" in o["pieces"] for o in women["outfits"])
    both = culture_guide("Sindhi", None)
    assert both["gender"] is None and len(both["outfits"]) == len(CULTURES["sindhi"]["men"]) + len(CULTURES["sindhi"]["women"])


def test_the_users_request_in_the_issue():
    """Punjabi: kurta, dhoti/tehmat and turban suggestions."""
    pieces = " ".join(p for o in culture_guide("Punjabi", "male")["outfits"] for p in o["pieces"]).lower()
    assert "kurta" in pieces and "tehmat" in pieces and "dhoti" in pieces and "turban" in pieces


def test_recommendations_know_each_cultures_real_products():
    for key in CULTURES:
        assert culture_words(key) <= ETHNICITY_KEYWORDS[key], key
    assert {"ajrak", "rilli"} <= ETHNICITY_KEYWORDS["sindhi"]
    assert "gilgiti" in ETHNICITY_KEYWORDS


def test_zayn_knows_every_culture_from_the_same_guide():
    assert "__CULTURE_GUIDE__" not in SYSTEM_PROMPT
    for c in CULTURES.values():
        assert f"{c['label'].upper()} men:" in SYSTEM_PROMPT and f"{c['label'].upper()} women:" in SYSTEM_PROMPT


def test_the_guide_endpoint():
    import services.recommendation.main as rec

    client = TestClient(rec.app)  # no lifespan: the route needs no model or catalog
    res = client.get("/culture/guide", params={"culture": "Pashtun", "gender": "male"}).json()
    assert res["guide"]["key"] == "pathan" and res["guide"]["gender"] == "men"
    assert client.get("/culture/guide", params={"culture": "Kashmiri"}).json() == {"guide": None}
