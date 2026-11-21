"""Self-learning from real users (spec §23.26): impressions + reactions become
labelled training lists, a scheduled job retrains, a safety gate decides,
promotion is versioned and the services reload by themselves. Everything
runs on a generated catalog with the database faked."""

from __future__ import annotations

import asyncio
import json
import random
import uuid

import pytest

from shared import model_registry
from shared.config import settings
from shared.schemas.recommendation import ScrapeRecommendRequest, UserProfileInput
from services.recommendation import main as rec
from services.recommendation.ml import auto_retrain, real_feedback
from services.recommendation.ml.features import FEATURE_NAMES
from services.scoring import feedback_retrain
from services.scoring.formula import COMPONENTS, components_for, compute_score
from services.scoring.look_model import to_row as look_row
from tests.test_learned_ranking import make_catalog

FS = real_feedback.feature_set_id()


def imp(req, user, pid, rank, version=f"v1:{FS}", n=len(FEATURE_NAMES)):
    return {"request_id": req, "user_id": user, "product_id": pid, "rank": rank,
            "features": [0.1 * rank] * n, "model_version": version}


# ── impressions + reactions -> labelled lists ────────────────────────────

def test_reactions_label_the_lists_the_user_saw():
    impressions = [imp("r1", "u1", "a", 1), imp("r1", "u1", "b", 2), imp("r1", "u1", "c", 3),
                   imp("r2", "u2", "a", 1), imp("r2", "u2", "d", 2),  # no reaction: not used
                   imp("r3", "u1", "e", 1),  # a list of one: not used
                   imp("r4", "u3", "a", 1, version="v0:deadbeef"),  # older feature list
                   imp("r4", "u3", "f", 2, n=5)]
    feedback = [{"user_id": "u1", "product_id": "a", "feedback_type": "loved_fit"},
                {"user_id": "u1", "product_id": "c", "feedback_type": "disliked"},
                {"user_id": "u1", "product_id": "e", "feedback_type": "loved_fit"},
                {"user_id": "u3", "product_id": "a", "feedback_type": "loved_fit"},
                {"user_id": "u2", "product_id": "a", "feedback_type": "rating"}]  # not a reaction
    data = real_feedback.build_groups(impressions, feedback)
    assert data.groups == [3]
    assert data.grades == [4, 2, 0]  # loved, ignored (neutral), "not for me"
    assert data.reactions == 2
    assert data.skipped_old_features == 2
    assert all(len(r) == len(FEATURE_NAMES) for r in data.rows)


def test_reactions_belong_to_the_user_who_reacted():
    impressions = [imp("r1", "u1", "a", 1), imp("r1", "u1", "b", 2)]
    feedback = [{"user_id": "someone-else", "product_id": "a", "feedback_type": "loved_fit"}]
    assert real_feedback.build_groups(impressions, feedback).groups == []


# ── a tiny trained model to work with ────────────────────────────────────

@pytest.fixture(scope="module")
def catalog():
    return make_catalog(400, seed=5)


@pytest.fixture
def live_dir(tmp_path, catalog):
    """A model folder with a promoted first version."""
    from services.recommendation.ml import train

    data = train.build_dataset(catalog, 60, seed=1)
    staging = tmp_path / "staging"
    train.train_models(data, staging, seed=1, version="20260101T000000Z")
    live = tmp_path / "live"
    live.mkdir()
    model_registry.promote(staging, live, auto_retrain.MODEL_FILES, auto_retrain.CARD, "20260101T000000Z")
    return live


def test_impressions_are_logged_for_signed_in_users_only(monkeypatch, live_dir, catalog):
    async def fake_catalog():
        return catalog

    monkeypatch.setattr(rec, "catalog_fallback_items", fake_catalog)
    monkeypatch.setattr(rec.settings, "learned_ranking_enabled", True)
    monkeypatch.setattr(rec.settings, "live_check_enabled", False)
    monkeypatch.setattr(rec, "LEARNED_MODEL_DIR", live_dir)
    monkeypatch.setattr(rec, "_ranker_cache", [])
    monkeypatch.setattr(rec, "_ranker_stamp", [])
    monkeypatch.setattr(rec, "_client", object())

    body = ScrapeRecommendRequest(profile=UserProfileInput(gender="female", skin_tone="Olive"),
                                  user_message="I want a kurta", max_products=6)
    shown: list = []
    result = asyncio.run(rec.recommend_products(body, shown))
    assert [pid for pid, _, _ in shown] == [p.id for p in result.products]
    assert [rank for _, rank, _ in shown] == list(range(1, len(shown) + 1))
    assert all(len(f) == len(FEATURE_NAMES) for _, _, f in shown)

    inserted = []

    async def fake_insert(_client, table, rows):
        inserted.append((table, rows))

    monkeypatch.setattr(real_feedback, "service_insert", fake_insert)
    monkeypatch.setattr(rec.settings, "impression_logging_enabled", True)
    monkeypatch.setattr(rec.settings, "supabase_url", "https://x.supabase.co")
    monkeypatch.setattr(rec.settings, "supabase_service_key", "test")
    asyncio.run(rec.log_impressions(None, shown))  # a guest: nothing stored
    asyncio.run(rec.log_impressions("not-a-uuid", shown))
    assert inserted == []
    user = str(uuid.uuid4())
    asyncio.run(rec.log_impressions(user, shown))
    table, rows = inserted[0]
    assert table == "recommendation_impressions" and len(rows) == len(shown)
    assert {r["user_id"] for r in rows} == {user} and len({r["request_id"] for r in rows}) == 1
    assert rows[0]["model_version"] == f"20260101T000000Z:{FS}"
    assert set(rows[0]) == {"request_id", "user_id", "product_id", "rank", "features", "model_version"}


def test_rule_ranking_logs_nothing(monkeypatch, catalog):
    async def fake_catalog():
        return catalog

    monkeypatch.setattr(rec, "catalog_fallback_items", fake_catalog)
    monkeypatch.setattr(rec.settings, "learned_ranking_enabled", False)
    monkeypatch.setattr(rec.settings, "live_check_enabled", False)
    monkeypatch.setattr(rec, "_client", object())
    shown: list = []
    asyncio.run(rec.recommend_products(ScrapeRecommendRequest(user_message="kurta"), shown))
    assert shown == []


# ── the retraining job ────────────────────────────────────────────────────

def _real_lists(n_lists=40, seed=0):
    """Generated 'real' impressions where users love high skin-harmony items."""
    rng = random.Random(seed)
    impressions, feedback = [], []
    j = FEATURE_NAMES.index("skin_harmony")
    for i in range(n_lists):
        user = f"u{i}"
        for rank in range(1, 7):
            feats = [rng.random() for _ in FEATURE_NAMES]
            impressions.append({"request_id": f"r{i}", "user_id": user, "product_id": f"p{i}-{rank}",
                                "rank": rank, "features": feats, "model_version": f"v:{FS}"})
            if feats[j] > 0.8:
                feedback.append({"user_id": user, "product_id": f"p{i}-{rank}", "feedback_type": "loved_fit"})
            elif feats[j] < 0.2:
                feedback.append({"user_id": user, "product_id": f"p{i}-{rank}", "feedback_type": "disliked"})
    return real_feedback.build_groups(impressions, feedback)


@pytest.fixture
def fake_db(monkeypatch):
    state = {"new": 0, "real": _real_lists(), "deleted": []}

    async def count(_client, since):
        return state["new"]

    async def fetch(_client):
        return state["real"]

    async def delete(_client, table, filters):
        state["deleted"].append((table, filters))
        return 0

    monkeypatch.setattr(real_feedback, "count_new_reactions", count)
    monkeypatch.setattr(real_feedback, "fetch_real_data", fetch)
    monkeypatch.setattr(auto_retrain, "service_delete", delete)
    monkeypatch.setattr(settings, "supabase_url", "https://x.supabase.co")
    monkeypatch.setattr(settings, "supabase_service_key", "test")
    monkeypatch.setattr(settings, "auto_retrain_min_feedback", 50)
    return state


def _run(live, catalog, **kw):
    return asyncio.run(auto_retrain.run(live, catalog=catalog, synthetic_queries=40, client=object(), **kw))


def test_too_little_new_feedback_does_nothing(fake_db, live_dir, catalog):
    fake_db["new"] = 12
    before = (live_dir / "model_card.json").read_text(encoding="utf-8")
    out = _run(live_dir, catalog)
    assert out.status == "skipped" and "12 new reactions" in out.reason
    assert (live_dir / "model_card.json").read_text(encoding="utf-8") == before


def test_enough_feedback_retrains_and_promotes_a_model_that_is_not_worse(fake_db, live_dir, catalog, monkeypatch):
    fake_db["new"] = 80
    monkeypatch.setattr(auto_retrain, "holdout_ndcg", lambda d, h: 0.80 if d == live_dir else 0.86)
    out = _run(live_dir, catalog)
    assert out.status == "promoted", out.reason
    card = json.loads((live_dir / "model_card.json").read_text(encoding="utf-8"))
    assert card["version"] == out.version and card["real_training_rows"] > 0
    assert "real reactions" in card["label_source"]
    assert (live_dir / "versions" / out.version / "ranker.txt").exists()
    history = model_registry.read_history(live_dir)
    assert history[-1]["status"] == "promoted" and history[-1]["real_lists"] == len(fake_db["real"].groups) > 30
    assert fake_db["deleted"][0][0] == "recommendation_impressions"  # retention pruning ran


def test_the_safety_gate_keeps_the_live_model_when_the_new_one_is_worse(fake_db, live_dir, catalog, monkeypatch):
    fake_db["new"] = 80
    before = {n: (live_dir / n).read_bytes() for n in [*auto_retrain.MODEL_FILES, auto_retrain.CARD]}
    monkeypatch.setattr(auto_retrain, "holdout_ndcg", lambda d, h: 0.90 if d == live_dir else 0.70)
    out = _run(live_dir, catalog)
    assert out.status == "rejected" and "worse on real users" in out.reason
    assert {n: (live_dir / n).read_bytes() for n in before} == before
    assert model_registry.read_history(live_dir)[-1]["status"] == "rejected"


def test_gate_rules():
    live = {"metrics": {"ndcg10_lightgbm": 0.95}}
    new = {"metrics": {"ndcg10_lightgbm": 0.90}}
    assert auto_retrain.gate(None, new, None, None)[0]
    assert auto_retrain.gate(live, new, 0.80, 0.798)[0]  # within tolerance
    assert not auto_retrain.gate(live, new, 0.80, 0.70)[0]
    assert not auto_retrain.gate(live, new, None, None)[0]  # no real holdout: validation decides
    assert auto_retrain.gate(live, {"metrics": {"ndcg10_lightgbm": 0.96}}, None, None)[0]


def test_one_retraining_at_a_time(fake_db, live_dir, catalog):
    fake_db["new"] = 80
    with model_registry.retrain_lock(live_dir):
        assert _run(live_dir, catalog).status == "busy"


def test_no_database_means_no_learning(live_dir, catalog, monkeypatch):
    monkeypatch.setattr(settings, "supabase_service_key", "")
    assert _run(live_dir, catalog).status == "skipped"


def test_rollback_restores_the_previous_version(fake_db, live_dir, catalog, monkeypatch):
    fake_db["new"] = 80
    monkeypatch.setattr(auto_retrain, "holdout_ndcg", lambda d, h: 0.5 if d == live_dir else 0.9)
    out = _run(live_dir, catalog)
    assert out.status == "promoted"
    assert model_registry.rollback(live_dir, auto_retrain.MODEL_FILES, auto_retrain.CARD) == "20260101T000000Z"
    card = json.loads((live_dir / "model_card.json").read_text(encoding="utf-8"))
    assert card["version"] == "20260101T000000Z"
    assert not (live_dir / "versions" / out.version).exists()


def test_the_service_picks_up_a_promoted_model_without_restarting(fake_db, live_dir, catalog, monkeypatch):
    monkeypatch.setattr(rec, "LEARNED_MODEL_DIR", live_dir)
    monkeypatch.setattr(rec, "_ranker_cache", [])
    monkeypatch.setattr(rec, "_ranker_stamp", [])
    assert rec._learned_ranker().card["version"] == "20260101T000000Z"
    fake_db["new"] = 80
    monkeypatch.setattr(auto_retrain, "holdout_ndcg", lambda d, h: 0.5 if d == live_dir else 0.9)
    out = _run(live_dir, catalog)
    import os
    import time

    os.utime(live_dir / "model_card.json", (time.time() + 5, time.time() + 5))  # coarse file clocks
    assert rec._learned_ranker().card["version"] == out.version


def test_versions_are_pruned(tmp_path):
    live = tmp_path / "live"
    for v in ["a", "b", "c", "d", "e"]:
        (live / "versions" / v).mkdir(parents=True)
    model_registry.prune_versions(live)
    assert sorted(p.name for p in (live / "versions").iterdir()) == ["c", "d", "e"]


def test_status_endpoint(monkeypatch, live_dir):
    from fastapi.testclient import TestClient

    monkeypatch.setattr(rec, "LEARNED_MODEL_DIR", live_dir)
    monkeypatch.setattr(rec, "_ranker_cache", [])
    monkeypatch.setattr(rec, "_ranker_stamp", [])
    body = TestClient(rec.app).get("/ml/status").json()
    assert body["live_model"]["version"] == "20260101T000000Z"
    assert body["auto_retrain_every_hours"] == 0  # off in tests (conftest)


# ── the look score's loop ─────────────────────────────────────────────────

def _look_records(n=80, seed=3):
    """Users whose stars follow the fit far more than anything else."""
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        row = [rng.uniform(30, 100) for _ in COMPONENTS] + [1.0, 1.0, 1.0, 1.0, float(rng.random() < 0.5)]
        stars = max(1, min(5, round(1 + 4 * row[2] / 100)))
        out.append({"feedback_data": {"kind": "look", "rating": stars, "features": row}})
    return out


def test_formula_from_a_stored_row_matches_the_live_formula():
    kurta = {"id": "k", "title": "Maroon Embroidered Kurta", "colors": ["maroon"], "tags": ["male"]}
    profile = {"skin_tone": "Medium", "style_preferences": ["ethnic"]}
    for hair in (None, {"name": "Quiff", "score": 0.7}):
        parts = components_for(kurta, profile, "eid", "fits", "M", hair)
        score, _ = compute_score(parts, dict.fromkeys(COMPONENTS, 0.25))
        assert feedback_retrain.formula_from_row(look_row(parts), dict.fromkeys(COMPONENTS, 0.25)) == \
            pytest.approx(score, abs=0.1)


def test_look_ratings_retrain_weights_and_the_forest(tmp_path, monkeypatch, catalog):
    monkeypatch.setattr(feedback_retrain, "WEIGHTS_FILE", tmp_path / "weights.json")
    monkeypatch.setattr(feedback_retrain, "load_weights", lambda: dict.fromkeys(COMPONENTS, 0.25))
    out = feedback_retrain.retrain(_look_records(), catalog, tmp_path / "look", looks=800)
    assert out.status == "promoted", out.reason
    weights = json.loads((tmp_path / "weights.json").read_text(encoding="utf-8"))["weights"]
    assert weights["fit"] == max(weights.values())  # learned what these users care about
    card = json.loads((tmp_path / "look" / "look_card.json").read_text(encoding="utf-8"))
    assert card["real_rows"] == 80 and card["real_holdout"]["ratings"] == 16


def test_look_gate_rejects_a_worse_forest(tmp_path, monkeypatch, catalog):
    look = tmp_path / "look"
    monkeypatch.setattr(feedback_retrain, "WEIGHTS_FILE", tmp_path / "weights.json")
    feedback_retrain.retrain([], catalog, look, looks=600)  # first version, weak labels only
    before = (look / "look_card.json").read_bytes()
    monkeypatch.setattr(feedback_retrain, "_forest_mae", lambda d, r, y: 5.0 if d == look else 9.0)
    out = feedback_retrain.retrain(_look_records(), catalog, look, looks=600)
    assert out.status == "rejected" and (look / "look_card.json").read_bytes() == before


def test_look_auto_waits_for_enough_ratings(tmp_path, monkeypatch):
    async def few(_since):
        return 3

    monkeypatch.setattr(feedback_retrain, "_count_since", few)
    monkeypatch.setattr(settings, "supabase_url", "https://x.supabase.co")
    monkeypatch.setattr(settings, "supabase_service_key", "test")
    out = feedback_retrain.auto(tmp_path)
    assert out.status == "skipped" and "3 new look ratings" in out.reason


# ── the scheduler ─────────────────────────────────────────────────────────

def test_scheduled_job_runs_in_its_own_process_and_never_raises():
    from shared.retrain_scheduler import run_job

    # a module that exits with an error: reported as a code, not an exception
    assert asyncio.run(run_job("json.tool", timeout=60)) != 0


def test_scheduler_loop_can_be_stopped():
    from shared.retrain_scheduler import retrain_loop

    async def go():
        task = asyncio.create_task(retrain_loop("json.tool", 1, first_delay=3600))
        await asyncio.sleep(0)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(go())


def test_seeding_the_model_volume(tmp_path):
    """First boot copies the image's models; later boots keep the learned ones;
    a release with a different feature list replaces them (keeping history)."""
    from shared.seed_models import seed

    baked, volume = tmp_path / "baked", tmp_path / "volume"
    baked.mkdir()
    (baked / "ranker.txt").write_text("baked")
    (baked / "history.json").write_text("[]")
    (baked / "model_card.json").write_text(json.dumps({"features": ["a", "b"]}))
    assert "first boot" in seed(baked, volume, "model_card.json")
    assert (volume / "ranker.txt").read_text() == "baked" and not (volume / "history.json").exists()

    (volume / "ranker.txt").write_text("learned from users")
    (volume / "history.json").write_text('[{"status": "promoted"}]')
    assert seed(baked, volume, "model_card.json") == "kept the learned models"
    assert (volume / "ranker.txt").read_text() == "learned from users"

    (baked / "model_card.json").write_text(json.dumps({"features": ["a", "b", "c"]}))
    assert "feature list changed" in seed(baked, volume, "model_card.json")
    assert (volume / "ranker.txt").read_text() == "baked"
    assert json.loads((volume / "history.json").read_text()) == [{"status": "promoted"}]
