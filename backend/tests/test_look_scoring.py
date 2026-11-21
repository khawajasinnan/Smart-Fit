"""Look score (SFR-032), comments and hints (SFR-033), feedback learning
(SFR-034), and the Random Forest look validator (spec §12, §23.25)."""

from __future__ import annotations

import random

import numpy as np
import pytest
from fastapi.testclient import TestClient

from services.scoring import feedback_retrain, look_model
from services.scoring import main as scoring_main
from services.scoring.formula import COMPONENTS, components_for, compute_score, load_weights
from services.scoring.look_model import FEATURES, LookValidator, tree_contributions

KURTA = {"id": "alpha:1", "title": "Emerald Embroidered Kurta", "category": "kurta",
         "colors": ["emerald"], "tags": ["male", "kurta", "ethnic"]}
PROFILE = {"gender": "male", "skin_tone": "Olive", "body_type": "rectangle",
           "style_preferences": ["ethnic"], "preferred_colors": ["emerald"]}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(scoring_main, "_validator_cache", [None])
    return TestClient(scoring_main.app)


def test_components_and_spec_weights():
    parts = components_for(KURTA, PROFILE, "eid", "fits", "M", None)
    assert [c.key for c in parts] == ["style", "colour", "fit", "occasion"]
    score, weights = compute_score(parts, load_weights())
    assert weights == {k: 0.25 for k in ("style", "colour", "fit", "occasion")}  # spec §12
    assert score == pytest.approx(sum(c.score for c in parts) / 4, abs=0.1)
    assert score >= 85  # ethnic emerald kurta for eid, fits, olive skin


def test_hairstyle_joins_with_renormalised_weights():
    parts = components_for(KURTA, PROFILE, "eid", "fits", "M", {"name": "Quiff", "score": 0.8, "face_shape": "Oval"})
    _, weights = compute_score(parts, load_weights())
    assert set(weights) == set(COMPONENTS)
    assert sum(weights.values()) == pytest.approx(1.0)
    assert parts[-1].note == "Quiff suits your oval face."


def test_wrong_size_and_occasion_lower_the_score_and_say_why(client):
    good = client.post("/score", json={"product": KURTA, "profile": PROFILE, "occasion": "eid",
                                       "fit_status": "fits", "fit_size": "M"}).json()
    bad = client.post("/score", json={"product": KURTA, "profile": PROFILE, "occasion": "office",
                                      "fit_status": "small", "fit_size": "S"}).json()
    assert bad["score"] < good["score"]
    fit = next(c for c in bad["components"] if c["key"] == "fit")
    assert fit["note"] == "Size S is small for you."
    assert any("one size up" in h for h in bad["hints"])
    assert any("For office" in h for h in bad["hints"])
    assert good["verdict"] and good["comments"]
    assert good["validation"] is None  # no validator loaded in this test
    assert len(good["model_features"]) == len(FEATURES)


def test_unknown_information_is_flagged_not_invented(client):
    res = client.post("/score", json={"product": {"id": "x", "title": "Kurta"}}).json()
    by_key = {c["key"]: c for c in res["components"]}
    assert not by_key["colour"]["known"] and "doesn't list" in by_key["colour"]["note"]
    assert not by_key["fit"]["known"] and not by_key["occasion"]["known"] and not by_key["style"]["known"]
    assert all(not h.startswith("Pair the") for h in res["hints"])  # no colour, no pairing advice


def test_hints_name_real_colours_and_the_right_accessories(client):
    res = client.post("/score", json={"product": KURTA, "profile": PROFILE}).json()
    pair = next(h for h in res["hints"] if h.startswith("Pair the"))
    assert "emerald" in pair and "waistcoat" in pair
    female = client.post("/score", json={"product": KURTA, "profile": {**PROFILE, "gender": "female"}}).json()
    assert "dupatta" in next(h for h in female["hints"] if h.startswith("Pair the"))


def test_request_validation(client):
    assert client.post("/score", json={}).status_code == 422
    bad_hair = {"product": KURTA, "hairstyle": {"score": 1.5}}
    assert client.post("/score", json=bad_hair).status_code == 422
    assert client.get("/health").json()["implemented"] is True


# ── Random Forest validator ──────────────────────────────────────────────

def _catalog(n=300):
    rng = random.Random(0)
    colours = ["black", "white", "maroon", "emerald", "beige", "tan", "mustard", "navy", "pink"]
    garments = ["kurta", "jeans", "lawn suit", "polo", "sherwani", "formal shirt"]
    return [{"id": f"p{i}", "title": f"{rng.choice(colours).title()} {g}", "category": g,
             "colors": [], "tags": [g]} for i, g in enumerate(rng.choice(garments) for _ in range(n))]


@pytest.fixture(scope="module")
def validator(tmp_path_factory):
    out = tmp_path_factory.mktemp("look")
    rows, labels = look_model.generate_looks(_catalog(), 2500, seed=1)
    card = look_model.train(rows, labels, out, seed=1)
    return LookValidator.load(out), card


def test_validator_trains_and_explains_exactly(validator):
    model, card = validator
    assert card["features"] == FEATURES and card["metrics"]["valid_mae"] < 8
    x = np.asarray([90, 80, 35, 95, 50, 1, 1, 1, 1, 0], dtype=float)
    bias, contrib = tree_contributions(model.forest, x)
    assert bias + contrib.sum() == pytest.approx(model.forest.predict([x])[0], abs=1e-6)


def test_validator_catches_a_size_that_sinks_the_look(validator):
    model, _ = validator
    parts = components_for(KURTA, PROFILE, "eid", "small", "S", None)
    score, _ = compute_score(parts, load_weights())
    v = model.validate(parts, score)
    assert v.predicted < score  # the stylist rule: a wrong size caps the look
    assert min(v.contributions, key=v.contributions.get) == "fit"


def test_score_endpoint_reports_the_validator(monkeypatch, validator):
    model, _ = validator
    monkeypatch.setattr(scoring_main, "_validator_cache", [model])
    res = TestClient(scoring_main.app).post("/score", json={
        "product": KURTA, "profile": PROFILE, "occasion": "eid", "fit_status": "small", "fit_size": "S"}).json()
    v = res["validation"]
    assert v["model"] == "random_forest" and 0 <= v["predicted_score"] <= 100
    if not v["agrees"]:
        assert "size & fit" in v["note"]
    assert all(c["effect"] is not None for c in res["components"])


# ── feedback (SFR-034) ───────────────────────────────────────────────────

def _features():
    return [80.0, 70.0, 95.0, 70.0, 50.0, 1.0, 1.0, 1.0, 0.0, 0.0]


def test_feedback_needs_a_signed_in_user(client):
    body = {"product_id": "alpha:1", "rating": 4, "model_features": _features()}
    assert client.post("/feedback", json=body).status_code == 401


def test_feedback_is_stored_with_what_the_user_saw(client, monkeypatch):
    saved = {}

    async def fake_upsert(_client, table, rows, on_conflict):
        saved.update(table=table, rows=rows, on_conflict=on_conflict)

    monkeypatch.setattr(scoring_main, "service_upsert", fake_upsert)
    monkeypatch.setattr(scoring_main.settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.setattr(scoring_main.settings, "supabase_service_key", "test")
    body = {"product_id": "alpha:1", "rating": 4, "score": 81, "model_features": _features(), "occasion": "eid"}
    res = client.post("/feedback", json=body, headers={"x-user-id": "u1"})
    assert res.status_code == 200 and res.json() == {"stored": True}
    row = saved["rows"][0]
    assert saved["table"] == "user_feedback" and saved["on_conflict"] == "user_id,product_id,feedback_type"
    assert row["product_id"] == "look:alpha:1" and row["feedback_type"] == "rating"
    assert row["feedback_data"]["kind"] == "look" and row["feedback_data"]["features"] == _features()

    bad = {**body, "model_features": [500.0] * len(FEATURES)}
    assert client.post("/feedback", json=bad, headers={"x-user-id": "u1"}).status_code == 422


def test_feedback_keeps_corrections_and_a_comment(client, monkeypatch):
    """SFR-034: corrections (the parts of the score that are off) and the user's own words."""
    saved = {}

    async def fake_upsert(_client, table, rows, on_conflict):
        saved.update(rows=rows)

    monkeypatch.setattr(scoring_main, "service_upsert", fake_upsert)
    monkeypatch.setattr(scoring_main.settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.setattr(scoring_main.settings, "supabase_service_key", "test")
    body = {"product_id": "alpha:1", "rating": 2, "model_features": _features(),
            "corrections": ["occasion", "colour", "occasion"], "comment": "  too formal for me  "}
    assert client.post("/feedback", json=body, headers={"x-user-id": "u1"}).status_code == 200
    data = saved["rows"][0]["feedback_data"]
    assert data["corrections"] == ["colour", "occasion"] and data["comment"] == "too formal for me"
    assert saved["rows"][0]["feedback_type"] == "rating"  # one row per look: details update it
    blank = {**body, "corrections": [], "comment": "   "}
    client.post("/feedback", json=blank, headers={"x-user-id": "u1"})
    assert saved["rows"][0]["feedback_data"]["comment"] is None
    unknown = {**body, "corrections": ["price"]}
    assert client.post("/feedback", json=unknown, headers={"x-user-id": "u1"}).status_code == 422


def test_ridge_reweighting_needs_enough_ratings_and_stays_near_equal():
    rng = random.Random(2)
    records = []
    for _ in range(80):
        row = [rng.uniform(30, 100) for _ in COMPONENTS] + [1.0] * len(COMPONENTS)
        rating = 1 + 4 * (0.7 * row[2] + 0.3 * row[1]) / 100  # these users care about fit most
        records.append({"feedback_data": {"kind": "look", "rating": rating, "features": row}})
    rows, labels = feedback_retrain.rating_rows(records)
    assert len(rows) == 80
    assert feedback_retrain.fit_weights(rows[:10], labels[:10]) is None  # too few
    w = feedback_retrain.fit_weights(rows, labels)
    assert sum(w.values()) == pytest.approx(1.0, abs=1e-3)
    assert w["fit"] == max(w.values())
    assert all(v >= 0.5 / len(COMPONENTS) - 1e-6 for v in w.values())  # shrunk towards equal


def test_rating_rows_skip_other_feedback():
    rows, _ = feedback_retrain.rating_rows([
        {"feedback_data": {"quiz": "q1", "choice": "a"}},
        {"feedback_data": {"kind": "look", "rating": 9, "features": _features()}},
        {"feedback_data": {"kind": "look", "rating": 3, "features": [1.0]}},
    ])
    assert rows == []


def test_style_words_mean_more_than_the_literal_word(client):
    """An embroidered kurta is ethnic wear even when the title doesn't say "ethnic"."""
    kurta = {"id": "k", "title": "Maroon Embroidered Kurta Pajama", "colors": ["maroon"], "tags": ["male"]}
    res = client.post("/score", json={"product": kurta, "profile": {"gender": "male",
                                                                   "style_preferences": ["ethnic"]}}).json()
    style = next(c for c in res["components"] if c["key"] == "style")
    assert style["score"] == 85 and style["note"] == "It matches your ethnic style."
    jeans = {"id": "j", "title": "Slim Fit Jeans", "tags": ["male"]}
    res = client.post("/score", json={"product": jeans, "profile": {"style_preferences": ["ethnic"]}}).json()
    assert next(c for c in res["components"] if c["key"] == "style")["score"] == 45


def test_body_tips_fit_the_wearer(client):
    look = {"product": KURTA, "profile": {**PROFILE, "body_type": "rectangle"}}
    men = client.post("/score", json=look).json()["hints"]
    assert any("waistcoat or an open jacket" in h for h in men) and not any("peplum" in h for h in men)
    look["profile"]["gender"] = "female"
    women = client.post("/score", json=look).json()["hints"]
    assert any("peplum" in h for h in women)
