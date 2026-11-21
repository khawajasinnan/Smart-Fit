"""Learned recommendation ranking (spec §23.25): HSV colour harmony, features,
LightGBM ranker + Random Forest validator training, live re-ranking,
explanations and the rule fallback. Models are trained on a small generated
catalog in a temp folder, so these tests never depend on the real catalog."""

from __future__ import annotations

import json
import random

import numpy as np
import pytest

from shared.color_harmony import extract_colors, outfit_harmony, pairing_suggestions, skin_bucket, skin_harmony
from shared.schemas.recommendation import UserProfileInput
from services.recommendation.keyword_ranking import rank_products
from services.recommendation.ml import train as ml_train
from services.recommendation.ml.features import FEATURE_NAMES, extract
from services.recommendation.ml.ranker import LearnedRanker
from shared.taxonomy import build_search_context

# ── colour harmony ─────────────────────────────────────────────────────────


@pytest.mark.parametrize(("label", "bucket"), [
    ("Fair", "fair"), ("Light", "light"), ("Medium", "medium"), ("Olive", "tan"), ("tan", "tan"),
    ("Brown", "brown"), ("Dark", "deep"), ("Type IV", "tan"), ("wheatish", "medium"), ("", None), (None, None),
])
def test_skin_bucket_accepts_app_and_cv_labels(label, bucket):
    assert skin_bucket(label) == bucket


def test_colours_come_from_the_list_then_the_title():
    assert extract_colors({"colors": ["Navy"], "title": "Off White Kurta"}) == ["navy", "off white"]
    assert extract_colors({"title": "Sky Blue Lawn Suit", "tags": ["women"]}) == ["sky blue"]
    assert extract_colors({"title": "Kurta"}) == []


def test_skin_harmony_prefers_contrast_and_flattering_colours():
    # beige on medium/olive skin washes out; emerald flatters it
    assert skin_harmony(["emerald"], "Olive").score > skin_harmony(["beige"], "Olive").score + 0.25
    good = skin_harmony(["royal blue"], "Dark")
    assert good.known and good.score >= 0.7 and "flatters" in good.reason
    washed = skin_harmony(["tan"], "Medium")
    assert washed.score <= 0.4 and "wash" in washed.reason
    assert not skin_harmony(["navy"], None).known  # no skin tone: neutral, not a guess
    assert skin_harmony([], "Fair").score == 0.5


def test_outfit_harmony_rules():
    assert outfit_harmony(["black", "red"]).score >= 0.8  # neutral + anything
    assert outfit_harmony(["blue", "orange"]).score >= 0.8  # complementary
    assert outfit_harmony(["magenta", "orange"]).score < 0.5  # two loud colours fighting
    assert outfit_harmony(["green"]).score == 0.75
    assert not outfit_harmony([]).known


def test_pairing_suggestions_are_new_colours():
    pairs = pairing_suggestions(["maroon"], "Medium")
    assert len(pairs) == 2 and "maroon" not in pairs and "burgundy" not in pairs  # no near-duplicates
    assert not set(pairing_suggestions(["navy"], "Olive")) & {"beige", "khaki", "tan", "camel", "peach"}


# ── a small generated catalog ─────────────────────────────────────────────

COLOURS = ["black", "white", "navy", "maroon", "emerald", "beige", "mustard", "pink", "teal", "tan", "olive"]
GARMENTS = {"female": ["Kurta", "Lawn Suit", "Dress", "Kurti", "Jeans", "Top"],
            "male": ["Kurta", "Shalwar Kameez", "Jeans", "Polo", "Formal Shirt", "Waistcoat"]}


def make_catalog(n: int = 500, seed: int = 1) -> list[dict]:
    rng = random.Random(seed)
    items = []
    for i in range(n):
        gender = rng.choice(["female", "male"])
        garment = rng.choice(GARMENTS[gender])
        colour = rng.choice(COLOURS)
        brand = rng.choice(["Alpha", "Bravo", "Charlie", "Delta"])
        items.append({
            "id": f"{brand.lower()}:{i}",
            "brand": brand,
            "title": f"{colour.title()} {garment}",
            "category": garment.lower(),
            "price_pkr": rng.choice([1500, 2500, 4000, 6000, 9000, 14000]),
            "currency": "PKR",
            "image_url": f"https://cdn.example.com/{i}.jpg",
            "product_url": f"https://{brand.lower()}.pk/products/item-{i}",
            "sizes": rng.choice([["S", "M", "L"], ["XL"], [], ["M"]]),
            "colors": [colour],
            "tags": [gender, garment.lower(), colour],
            "in_stock": True,
        })
    return items


@pytest.fixture(scope="module")
def trained(tmp_path_factory):
    out = tmp_path_factory.mktemp("models")
    catalog = make_catalog()
    data = ml_train.build_dataset(catalog, n_queries=120, seed=3)
    card = ml_train.train_models(data, out, seed=3)
    return out, card, catalog


def test_dataset_uses_the_production_hard_filters(trained):
    catalog = make_catalog()
    data = ml_train.build_dataset(catalog, n_queries=20, seed=9)
    assert len(data.groups) == 20
    assert sum(data.groups) == len(data.rows) == len(data.grades)
    assert all(len(r) == len(FEATURE_NAMES) for r in data.rows)
    assert set(data.grades) <= {0, 1, 2, 3, 4}
    assert all(s > 0 for s in data.rule_scores)  # hard-excluded products never become rows


def test_training_writes_models_and_an_honest_card(trained):
    out, card, _ = trained
    assert (out / "ranker.txt").exists() and (out / "validator.joblib").exists()
    saved = json.loads((out / "model_card.json").read_text(encoding="utf-8"))
    assert saved["features"] == FEATURE_NAMES
    assert saved["label_source"].startswith("weak")
    m = saved["metrics"]
    assert 0 <= m["ndcg10_lightgbm"] <= 1 and 0 <= m["ndcg10_rules_only"] <= 1
    assert m["validator_auc"] is None or m["validator_auc"] > 0.6
    assert set(saved["validator_importance"]) == set(FEATURE_NAMES)


def test_ranker_is_monotone_in_budget_and_skin_tone(trained):
    out, _, _ = trained
    model = LearnedRanker.load(out)
    base = np.asarray([[0.0] * len(FEATURE_NAMES)])
    base[0, FEATURE_NAMES.index("gender_fit")] = 1
    base[0, FEATURE_NAMES.index("in_stock")] = 1
    worse, better = base.copy(), base.copy()
    worse[0, FEATURE_NAMES.index("budget_fit")] = 0.2
    better[0, FEATURE_NAMES.index("budget_fit")] = 1.0
    assert model.ranker.predict(better)[0] >= model.ranker.predict(worse)[0]
    worse, better = base.copy(), base.copy()
    worse[0, FEATURE_NAMES.index("skin_harmony")] = 0.2
    better[0, FEATURE_NAMES.index("skin_harmony")] = 0.9
    assert model.ranker.predict(better)[0] >= model.ranker.predict(worse)[0]


def _request(catalog, message="I want a kurta", **profile):
    prof = UserProfileInput(gender="female", skin_tone="Olive", budget_max=6000, chest_cm=90, **profile)
    context = build_search_context(prof, message, "", "", {})
    context["browse"] = False
    context["occasion"] = None
    from services.recommendation.local_catalog import local_products

    raw = local_products(prof, context, 2000, catalog)
    return prof, context, raw


def test_rerank_orders_by_the_shown_score_and_explains_every_item(trained):
    out, _, catalog = trained
    model = LearnedRanker.load(out)
    prof, context, raw = _request(catalog)
    rules = rank_products(raw, prof, context, len(raw))
    learned = model.rerank(raw, rules, prof, context)
    assert {r.id for r in learned} == {r.id for r in rules}  # filtering is untouched
    scores = [r.match_score for r in learned]
    assert scores == sorted(scores, reverse=True)
    for r in learned:
        assert r.ranking_model == "lightgbm+random_forest"
        assert 0 <= r.ranker_score <= 1 and 0 <= r.validator_score <= 1
        assert r.match_reasons and len(r.match_reasons) <= 4
        assert set(r.suitability) == {"skin_tone", "colours", "size", "body_shape", "occasion", "budget"}
        for f in r.explanation:
            assert f.feature in FEATURE_NAMES and f.text and f.impact != 0


def test_explanations_are_true_to_the_product(trained):
    out, _, catalog = trained
    model = LearnedRanker.load(out)
    prof, context, raw = _request(catalog)
    learned = model.rerank(raw, rank_products(raw, prof, context, len(raw)), prof, context)
    by_id = {p["id"]: p for p in raw}
    for r in learned:
        p = by_id[r.id]
        for f in r.explanation:
            if f.text == "within your budget":
                assert p["price_pkr"] <= 6000
            if f.text == "above your budget":
                assert p["price_pkr"] > 6000
            if f.feature == "skin_harmony":
                assert p["colors"][0] in f.text


def test_validator_disagreement_is_never_ranked_above_agreement(trained):
    out, _, catalog = trained
    model = LearnedRanker.load(out)
    prof, context, raw = _request(catalog)
    learned = model.rerank(raw, rank_products(raw, prof, context, len(raw)), prof, context)
    agreed = [r.match_score for r in learned if r.validated]
    rejected = [r.match_score for r in learned if r.validated is False]
    if agreed and rejected:
        assert max(rejected) <= 49


def test_extract_matches_feature_order():
    prof = UserProfileInput(gender="male", skin_tone="Brown", budget_max=5000)
    ctx = build_search_context(prof, "kurta", "", "", {})
    f = extract({"title": "Emerald Kurta", "colors": ["emerald"], "price_pkr": 7500, "tags": ["male"]}, prof, ctx)
    assert list(f) == FEATURE_NAMES
    assert f["budget_fit"] == pytest.approx(0.5)  # 1.5x the budget
    assert f["skin_harmony"] > 0.6


def test_missing_or_mismatched_models_fall_back_to_rules(tmp_path, trained):
    assert LearnedRanker.load(tmp_path) is None
    out, _, _ = trained
    card = json.loads((out / "model_card.json").read_text(encoding="utf-8"))
    bad = tmp_path / "bad"
    bad.mkdir()
    for name in ("ranker.txt", "validator.joblib"):
        (bad / name).write_bytes((out / name).read_bytes())
    card["features"] = card["features"][:-1]
    (bad / "model_card.json").write_text(json.dumps(card), encoding="utf-8")
    assert LearnedRanker.load(bad) is None


def test_service_keeps_rule_order_when_disabled(monkeypatch, trained):
    from services.recommendation import main as rec_main

    out, _, catalog = trained
    prof, context, raw = _request(catalog)
    monkeypatch.setattr(rec_main.settings, "learned_ranking_enabled", False)
    rules = rec_main.rank_candidates(raw, prof, context)
    assert all(r.ranking_model == "rules" for r in rules)

    monkeypatch.setattr(rec_main.settings, "learned_ranking_enabled", True)
    monkeypatch.setattr(rec_main, "_ranker_cache", [LearnedRanker.load(out)])
    learned = rec_main.rank_candidates(raw, prof, context)
    assert all(r.ranking_model == "lightgbm+random_forest" for r in learned)


def test_a_broken_model_never_breaks_recommendations(monkeypatch, trained):
    from services.recommendation import main as rec_main

    _, _, catalog = trained
    prof, context, raw = _request(catalog)

    class Broken:
        def rerank(self, *a, **k):
            raise RuntimeError("corrupt model")

    monkeypatch.setattr(rec_main.settings, "learned_ranking_enabled", True)
    monkeypatch.setattr(rec_main, "_ranker_cache", [Broken()])
    assert rec_main.rank_candidates(raw, prof, context)  # rule ranking, no exception


def test_feedback_file_shifts_grades(tmp_path):
    fb = tmp_path / "fb.jsonl"
    fb.write_text("\n".join(json.dumps(e) for e in [
        {"kind": "product", "label": 1, "product": {"id": "alpha:1"}},
        {"kind": "product", "label": 0, "product": {"product_url": "https://bravo.pk/products/item-2"}},
        {"kind": "quiz", "label": "a"},
    ]), encoding="utf-8")
    shift = ml_train.load_feedback(fb)
    assert shift == {"alpha:1": 0.25, "https://bravo.pk/products/item-2": -0.40}
    feats = {"skin_harmony": 0.5, "outfit_harmony": 0.5}
    assert ml_train.teacher_grade(60, feats, 0.25) > ml_train.teacher_grade(60, feats)
    assert ml_train.teacher_grade(60, feats, -0.40) == 0


@pytest.mark.parametrize("tone", ["Olive", "Brown", "Tan"])
def test_skin_tone_is_never_a_colour_preference(tone):
    """'Olive' / 'Brown' skin used to become a preference for olive / brown clothes."""
    prof = UserProfileInput(gender="male", skin_tone=tone, budget_max=8000)
    ctx = build_search_context(prof, "I want a kurta", "", "", {})
    assert ctx["colors"] == [] and ctx["requested_colors"] == []
    f = extract({"title": f"{tone} Kurta", "colors": [tone.lower()], "tags": ["male"]}, prof, ctx)
    assert f["color_preference"] == 0.0
    chosen = UserProfileInput(gender="male", skin_tone=tone, preferred_colors=["navy"])
    assert build_search_context(chosen, "kurta", "", "", {})["colors"] == ["navy"]


def test_style_preference_understands_garment_words():
    from shared.style_match import style_hit

    assert style_hit("embroidered kurta pajama", ["ethnic"]) == "ethnic"
    assert style_hit("slim fit jeans", ["ethnic"]) is None
    assert style_hit("navy two piece suit", ["casual", "formal"]) == "formal"
    assert style_hit("oversized graphic hoodie", ["Streetwear"]) == "Streetwear"
    assert style_hit("anything", []) is None


def test_reasons_never_contradict_their_direction(trained):
    """A good fact ("size M in stock") is never shown as a watch-out, and a bad
    one ("above your budget") never as a reason it ranked high."""
    from services.recommendation.ml.ranker import favourable

    out, _, catalog = trained
    model = LearnedRanker.load(out)
    for message in ("I want a kurta", "show me jeans", ""):
        prof, context, raw = _request(catalog, message)
        if not raw:
            continue
        for r in model.rerank(raw, rank_products(raw, prof, context, len(raw)), prof, context):
            for f in r.explanation:
                good = favourable(f.feature, f.value)
                assert good is None or good == (f.impact > 0), (f.feature, f.value, f.impact, f.text)
            watch = [x for x in r.match_reasons if x.startswith("Watch out: ")]
            assert all(x[len("Watch out: "):] in {f.text for f in r.explanation if f.impact < 0} for x in watch)


def test_diversify_never_gives_a_rejected_pick_a_brand_slot():
    from services.recommendation.main import diversify
    from shared.schemas.recommendation import ProductRecommendation

    def rec(i, brand, score, ok=True):
        return ProductRecommendation(id=str(i), brand=brand, title=f"t{i}", product_url=f"https://x.pk/products/{i}",
                                     match_score=score, validated=ok)

    ranked = [rec(1, "A", 95), rec(2, "A", 94), rec(3, "A", 93), rec(4, "B", 49, ok=False), rec(5, "B", 40)]
    picked = diversify(ranked, 3)
    assert [p.id for p in picked] == ["1", "2", "5"]  # B's validated item, not its rejected one
    assert [p.id for p in diversify(ranked, 5)][-1] == "4"  # rejected only fills what's left
