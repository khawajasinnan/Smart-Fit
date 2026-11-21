"""Occasion judgement shared by the look score and the recommendation ranker.
Found 18 Nov 2026: a hoodie "fit the office dress code" and a red sequin party
frock "fit the funeral dress code" (both 72/100)."""

from __future__ import annotations

import pytest

from services.scoring.formula import occasion_component
from shared.occasion import occasion_clash, occasion_match


@pytest.mark.parametrize("text, occasion", [
    ("oversized graphic hoodie", "office"),
    ("fleece joggers", "interview"),
    ("red sequin party frock", "funeral"),
    ("embellished chiffon lawn suit", "funeral"),
    ("graphic print t-shirt", "nikah"),
    ("ivory bridal lehenga", "casual"),
    ("gym shorts", "eid"),
])
def test_clashes_score_zero(text, occasion):
    assert occasion_match(text, occasion) == 0.0
    assert occasion_clash(text, occasion) is not None


@pytest.mark.parametrize("text, occasion", [
    ("navy cotton kurta", "eid"),
    ("white formal shirt", "office"),
    ("fleece hoodie grey", "casual"),
    ("yellow printed lawn 3pc", "mehndi"),
    ("ivory embroidered sherwani", "nikah"),
    ("plain white shalwar kameez", "funeral"),
    ("black velvet maxi dress", "party"),
    ("cotton kurti", "casual"),
])
def test_right_choices_score_one(text, occasion):
    assert occasion_match(text, occasion) == 1.0


def test_colour_hint_alone_needs_the_right_garment_family():
    assert occasion_match("yellow denim jacket", "mehndi") < 1.0  # yellow, but western
    assert occasion_match("yellow lawn suit", "mehndi") == 1.0


def test_no_occasion_is_neutral():
    assert occasion_match("anything", None) == 0.5
    assert occasion_clash("hoodie", None) is None


def test_look_score_names_the_clash_and_uses_the_colours():
    c = occasion_component({"title": "Party Frock", "colors": ["Red"]}, "funeral")
    assert c.score < 30 and c.note in ("Party doesn't suit a funeral.", "Red doesn't suit a funeral.")
    assert occasion_component({"title": "Chiffon Frock", "colors": ["Red"]}, "funeral").note == "Red doesn't suit a funeral."
    c = occasion_component({"title": "Graphic Hoodie"}, "office")
    assert c.note == "Graphic doesn't suit an office."
    c = occasion_component({"title": "Printed Lawn 3pc", "colors": ["Yellow"]}, "mehndi")
    assert c.score == 95.0
