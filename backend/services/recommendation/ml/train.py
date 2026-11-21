"""Train the recommendation models (spec §23.25).

    python -m services.recommendation.ml.train                       # from backend/
    python -m services.recommendation.ml.train --feedback fb.jsonl   # + real feedback
    python -m services.recommendation.ml.train --queries 800 --seed 7

Two models, one job each:

* LightGBM LambdaRank ("ranker") orders the products for a request: a
  learning-to-rank model trained on whole result lists, optimising NDCG@10.
  Monotone constraints keep it sane: all else equal it can never prefer a
  product that is further over budget, a worse skin-tone match, a size that
  isn't in stock, a brand the user disliked, and so on.
* Random Forest classifier ("validator") answers a separate yes/no question,
  "is this a good match for this shopper?". It is a different model family
  trained on the same rows, so when it disagrees with the ranker the result
  is flagged and pulled down; its feature importances are the global
  explanation shown in the model card.

Labels (weak supervision, until enough real feedback exists):
  The catalog is real (every scraped product), the shoppers are generated
  (gender, budget, colours, skin tone, body shape, occasion, chat request,
  learned taste), and each candidate is graded 0..4 by a teacher: the
  approved stylist rules (keyword_ranking.score_product) plus HSV colour
  harmony with the skin tone and within the garment. `--feedback` adds the
  app's real "loved"/"not for me" rows (scripts/export_feedback_dataset.py):
  a loved product is graded up and a rejected one down wherever it appears,
  and the model card records how many real rows were used.

Writes models/ranker.txt, models/validator.joblib, models/model_card.json.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import math
import random
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from shared.audience import is_adult_product
from shared.schemas.recommendation import UserProfileInput
from shared.taxonomy import build_search_context, gender_garment_conflict
from services.recommendation.keyword_ranking import MINIMUM_SCORE, score_product
from services.recommendation.local_catalog import is_product_page, local_products
from services.recommendation.ml.features import FEATURE_NAMES, extract, to_row

logger = logging.getLogger("smartfit.recommendation.train")

MODEL_DIR = Path(__file__).resolve().parent / "models"
GOOD_GRADE = 3  # grade >= this is a "good match" for the validator
CANDIDATES_PER_QUERY = 120
MIN_CANDIDATES = 8

# +1: more of this feature can only raise the ranker's score, -1: only lower it,
# 0: free. Only for features whose direction is not a matter of taste.
MONOTONE = {
    "category_match": 1, "category_conflict": -1, "gender_fit": 1, "color_preference": 1,
    "style_match": 1, "occasion_match": 1, "skin_harmony": 1, "outfit_harmony": 1,
    "ethnicity_match": 1, "budget_fit": 1, "size_available": 1, "body_flatter": 1,
    "taste_brand": 1, "taste_color": 1, "taste_category": 1, "style_lean": 1, "price_point": 1,
    "in_stock": 1, "info_complete": 0,
}

GARMENTS = {
    "female": ["kurta", "lawn suit", "3 piece unstitched", "kurti", "dress", "shalwar kameez",
               "jeans", "top", "trousers", "frock", "embroidered suit", "co-ord set", "shirt"],
    "male": ["kurta", "shalwar kameez", "waistcoat", "jeans", "t-shirt", "polo", "formal shirt",
             "chinos", "suit", "hoodie", "casual shirt", "trousers", "sherwani"],
}
OCCASIONS = ["mehndi", "nikah", "eid", "office", "casual", "party", "wedding", "date", "interview", "friday"]
COLORS = ["black", "white", "navy", "blue", "maroon", "green", "pink", "beige", "olive", "mustard",
          "teal", "grey", "red", "cream", "purple", "brown", "emerald", "peach"]
STYLES = ["casual", "formal", "ethnic", "streetwear", "classic", "minimalist", "trendy", "embroidered",
          "printed", "sporty"]
SKIN = ["Fair", "Light", "Medium", "Olive", "Brown", "Dark"]
BODY = {"female": ["pear", "apple", "hourglass", "rectangle", "inverted triangle", None],
        "male": ["rectangle", "inverted triangle", "apple", "trapezoid", None]}
BUDGETS = [None, 2500, 4000, 6000, 9000, 15000, 25000]


@dataclass
class Dataset:
    rows: list[list[float]] = field(default_factory=list)
    grades: list[int] = field(default_factory=list)
    groups: list[int] = field(default_factory=list)  # rows per query, in order
    rule_scores: list[float] = field(default_factory=list)  # baseline for the evaluation
    feedback_rows: int = 0


def sample_shopper(rng: random.Random) -> tuple[UserProfileInput, str, dict, dict | None]:
    """A generated shopper: profile, chat message, dynamic prefs, taste."""
    gender = rng.choice(["female", "male"])
    chest = rng.uniform(80, 115) if rng.random() < 0.7 else None
    budget = rng.choice(BUDGETS)
    profile = UserProfileInput(
        gender=gender,
        height_cm=rng.uniform(150, 190),
        weight_kg=rng.uniform(45, 100),
        chest_cm=chest,
        waist_cm=rng.uniform(62, 100) if chest else None,
        body_type=rng.choice(BODY[gender]),
        skin_tone=rng.choice(SKIN),
        style_preferences=rng.sample(STYLES, rng.randint(0, 2)),
        preferred_colors=rng.sample(COLORS, rng.randint(0, 2)),
        budget_max=budget,
        occasions=rng.sample(OCCASIONS, rng.randint(0, 1)),
    )
    garment = rng.choice(GARMENTS[gender])
    occasion = rng.choice(OCCASIONS) if rng.random() < 0.4 else None
    r = rng.random()
    if r < 0.15:
        message = ""  # browsing (Home's "Trending for you")
    elif r < 0.30 and occasion:
        message = f"what should I wear for {occasion}"
    elif r < 0.45:
        message = f"show me a {rng.choice(COLORS)} {garment}"
    elif r < 0.55:
        message = f"{garment} under {rng.choice([3000, 5000, 8000, 12000])}"
    else:
        message = f"I want a {garment}"
    prefs = {"occasion": occasion} if occasion else {}
    taste = None
    if rng.random() < 0.5:
        taste = {
            "liked_brands": [], "disliked_brands": [],
            "liked_colors": rng.sample(COLORS, rng.randint(0, 2)),
            "disliked_colors": rng.sample(COLORS, rng.randint(0, 1)),
            "liked_categories": [], "disliked_categories": [],
            "style_lean": rng.choice([None, "eastern", "western"]),
            "price_point": rng.choice([None, 3000, 6000, 12000]),
            "excluded_product_ids": [],
        }
    return profile, message, prefs, taste


def build_context(profile: UserProfileInput, message: str, prefs: dict, taste: dict | None) -> dict:
    """Exactly what recommend_products builds for a live request."""
    context = build_search_context(profile, message, "", "", prefs)
    if taste is not None:
        context["taste"] = taste
    context["browse"] = not message.strip() and not context.get("detected_garment")
    context["occasion"] = prefs.get("occasion")
    return context


def teacher_grade(rule_score: int, feats: dict[str, float], feedback: float = 0.0) -> int:
    """0..4 relevance from the stylist rules + colour harmony (+ real feedback)."""
    utility = 0.65 * rule_score / 99 + 0.20 * feats["skin_harmony"] + 0.15 * feats["outfit_harmony"]
    utility += feedback
    for grade, cut in ((4, 0.80), (3, 0.70), (2, 0.58), (1, 0.45)):
        if utility >= cut:
            return grade
    return 0


def load_feedback(path: Path | None) -> dict[str, float]:
    """Product id/url -> utility shift from real app feedback (loved +, not for me -)."""
    if not path:
        return {}
    shift: dict[str, float] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        e = json.loads(line)
        if e.get("kind") != "product" or e.get("label") not in (0, 1):
            continue
        product = e.get("product") or {}
        delta = 0.25 if e["label"] == 1 else -0.40
        for key in (product.get("id"), product.get("product_url")):
            if key:
                shift[key] = shift.get(key, 0.0) + delta
    return shift


def build_dataset(catalog: list[dict], n_queries: int, seed: int,
                  feedback: dict[str, float] | None = None) -> Dataset:
    rng = random.Random(seed)
    feedback = feedback or {}
    data = Dataset()
    attempts = 0
    while len(data.groups) < n_queries and attempts < n_queries * 6:
        attempts += 1
        profile, message, prefs, taste = sample_shopper(rng)
        context = build_context(profile, message, prefs, taste)
        if context.get("invalid_budget"):
            continue
        garment = context.get("exact_category") or context.get("detected_garment") or ""
        if gender_garment_conflict(context["gender"], garment):
            continue
        raw = [p for p in local_products(profile, context, 2000, catalog)
               if is_product_page(p.get("product_url") or "") and is_adult_product(p)]
        floor = 1 if context.get("browse") else MINIMUM_SCORE
        scored = []
        for p in raw:
            s, _ = score_product(p, profile, context)
            if s >= floor:  # the same hard filters as production
                scored.append((p, s))
        if len(scored) < MIN_CANDIDATES:
            continue
        if len(scored) > CANDIDATES_PER_QUERY:
            scored = rng.sample(scored, CANDIDATES_PER_QUERY)
        for p, s in scored:
            feats = extract(p, profile, context)
            fb = feedback.get(p.get("id")) or feedback.get(p.get("product_url")) or 0.0
            data.feedback_rows += fb != 0.0
            data.rows.append(to_row(feats))
            data.grades.append(teacher_grade(s, feats, fb))
            data.rule_scores.append(float(s))
        data.groups.append(len(scored))
    return data


def _slices(groups: list[int]) -> list[slice]:
    out, start = [], 0
    for g in groups:
        out.append(slice(start, start + g))
        start += g
    return out


def ndcg_at(scores: np.ndarray, grades: np.ndarray, groups: list[int], k: int = 10) -> float:
    """Mean NDCG@k over queries (gain 2^grade - 1)."""
    vals = []
    for sl in _slices(groups):
        g, s = grades[sl], scores[sl]
        if g.max() == 0:
            continue
        order = np.argsort(-s, kind="stable")[:k]
        ideal = np.sort(g)[::-1][:k]
        disc = 1 / np.log2(np.arange(2, k + 2))
        dcg = float(((2.0 ** g[order] - 1) * disc[: len(order)]).sum())
        idcg = float(((2.0 ** ideal - 1) * disc[: len(ideal)]).sum())
        vals.append(dcg / idcg)
    return float(np.mean(vals)) if vals else 0.0


def train_models(data: Dataset, out_dir: Path, seed: int = 42, label_source: str = "weak",
                 extra_train: Dataset | None = None, version: str | None = None) -> dict:
    """Train both models on `data` (split by query into train/validation) plus
    `extra_train` (real users' result lists, spec §23.26), which only ever goes
    into the training side so the validation numbers stay comparable."""
    import joblib
    import lightgbm as lgb
    import sklearn
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.inspection import permutation_importance
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score, roc_auc_score

    X = np.asarray(data.rows, dtype=np.float32)
    y = np.asarray(data.grades, dtype=np.int32)
    rule = np.asarray(data.rule_scores, dtype=np.float32)
    slices = _slices(data.groups)

    # split by query (never the same shopper's list on both sides)
    rng = np.random.default_rng(seed)
    order = rng.permutation(len(slices))
    n_valid = max(1, len(slices) // 5)
    valid_q, train_q = sorted(order[:n_valid]), sorted(order[n_valid:])

    def take(qs):
        idx = np.concatenate([np.arange(slices[q].start, slices[q].stop) for q in qs])
        return idx, [data.groups[q] for q in qs]

    tr_idx, tr_groups = take(train_q)
    X_tr, y_tr = X[tr_idx], y[tr_idx]
    if extra_train is not None and extra_train.groups:
        X_tr = np.concatenate([X_tr, np.asarray(extra_train.rows, dtype=np.float32)])
        y_tr = np.concatenate([y_tr, np.asarray(extra_train.grades, dtype=np.int32)])
        tr_groups = list(tr_groups) + list(extra_train.groups)
    va_idx, va_groups = take(valid_q)

    ranker = lgb.LGBMRanker(
        objective="lambdarank",
        n_estimators=400,
        learning_rate=0.05,
        num_leaves=31,
        min_child_samples=20,
        subsample=0.8,
        subsample_freq=1,
        colsample_bytree=0.9,
        monotone_constraints=[MONOTONE[n] for n in FEATURE_NAMES],
        random_state=seed,
        verbose=-1,
    )
    ranker.fit(
        X_tr, y_tr, group=tr_groups,
        eval_X=(X[va_idx],), eval_y=(y[va_idx],), eval_group=[va_groups], eval_at=[10],
        callbacks=[lgb.early_stopping(40, verbose=False)],
    )

    good = (y >= GOOD_GRADE).astype(int)
    validator = RandomForestClassifier(
        n_estimators=200, max_depth=12, min_samples_leaf=5, class_weight="balanced",
        n_jobs=-1, random_state=seed,
    )
    validator.fit(X_tr, (y_tr >= GOOD_GRADE).astype(int))

    # calibrate the ranker's raw score into "probability of a good match" on
    # the held-out queries, so the number shown to users means something
    raw_va = ranker.predict(X[va_idx])
    calib = LogisticRegression().fit(raw_va.reshape(-1, 1), good[va_idx])

    rf_va = validator.predict_proba(X[va_idx])[:, 1]
    p_rank_va = calib.predict_proba(raw_va.reshape(-1, 1))[:, 1]
    perm = permutation_importance(validator, X[va_idx], good[va_idx], n_repeats=5,
                                  random_state=seed, scoring="roc_auc")
    has_both = len(set(good[va_idx])) == 2
    metrics = {
        "valid_queries": len(valid_q),
        "train_queries": len(train_q),
        "ndcg10_lightgbm": round(ndcg_at(raw_va, y[va_idx], va_groups), 4),
        "ndcg10_rules_only": round(ndcg_at(rule[va_idx], y[va_idx], va_groups), 4),
        "validator_auc": round(float(roc_auc_score(good[va_idx], rf_va)), 4) if has_both else None,
        "validator_accuracy": round(float(accuracy_score(good[va_idx], rf_va >= 0.5)), 4),
        "ranker_auc": round(float(roc_auc_score(good[va_idx], p_rank_va)), 4) if has_both else None,
        "ranker_validator_agreement": round(float(np.mean((p_rank_va >= 0.5) == (rf_va >= 0.5))), 4),
        "good_match_rate": round(float(good.mean()), 4),
    }
    card = {
        "version": version or datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ"),
        "trained_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "real_training_rows": len(extra_train.rows) if extra_train is not None else 0,
        "features": FEATURE_NAMES,
        "label_source": label_source,
        "feedback_rows": data.feedback_rows,
        "rows": int(len(y)),
        "queries": len(data.groups),
        "grade_counts": {str(g): int((y == g).sum()) for g in range(5)},
        "good_grade": GOOD_GRADE,
        "best_iteration": int(ranker.best_iteration_ or ranker.n_estimators),
        "calibration": {"coef": float(calib.coef_[0][0]), "intercept": float(calib.intercept_[0])},
        "blend": {"lightgbm": 0.7, "random_forest": 0.3},
        "metrics": metrics,
        "ranker_importance_gain": dict(sorted(
            ((n, round(float(v), 2)) for n, v in zip(FEATURE_NAMES,
             ranker.booster_.feature_importance("gain"))), key=lambda kv: -kv[1])),
        "validator_importance": dict(sorted(
            ((n, round(float(v), 4)) for n, v in zip(FEATURE_NAMES, validator.feature_importances_)),
            key=lambda kv: -kv[1])),
        "validator_permutation_auc_drop": dict(sorted(
            ((n, round(float(v), 4)) for n, v in zip(FEATURE_NAMES, perm.importances_mean)),
            key=lambda kv: -kv[1])),
        "versions": {"lightgbm": lgb.__version__, "scikit-learn": sklearn.__version__},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    ranker.booster_.save_model(str(out_dir / "ranker.txt"))
    joblib.dump(validator, out_dir / "validator.joblib", compress=3)
    (out_dir / "model_card.json").write_text(json.dumps(card, indent=2), encoding="utf-8")
    return card


async def _load_catalog() -> list[dict]:
    import httpx

    from shared.catalog_store import load_products
    from services.recommendation.local_catalog import catalog_item

    async with httpx.AsyncClient(timeout=60) as client:
        return [catalog_item(p) for p in await load_products(client)]


def main() -> int:
    ap = argparse.ArgumentParser(description="Train the LightGBM ranker + Random Forest validator.")
    ap.add_argument("--queries", type=int, default=600, help="generated shoppers (result lists)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--feedback", type=Path, help="JSONL from scripts/export_feedback_dataset.py")
    ap.add_argument("--out", type=Path, default=MODEL_DIR)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    t0 = time.time()
    catalog = asyncio.run(_load_catalog())
    logger.info("catalog: %d products", len(catalog))
    feedback = load_feedback(args.feedback)
    data = build_dataset(catalog, args.queries, args.seed, feedback)
    logger.info("dataset: %d queries, %d rows, %d rows with real feedback (%.0fs)",
                len(data.groups), len(data.rows), data.feedback_rows, time.time() - t0)
    source = "weak (stylist rules + HSV colour harmony)"
    if data.feedback_rows:
        source += f" + real app feedback ({data.feedback_rows} rows)"
    card = train_models(data, args.out, args.seed, source)
    m = card["metrics"]
    logger.info("NDCG@10 LightGBM %.3f vs rules only %.3f | validator AUC %s | agreement %.0f%%",
                m["ndcg10_lightgbm"], m["ndcg10_rules_only"], m["validator_auc"],
                100 * m["ranker_validator_agreement"])
    logger.info("saved to %s (%.0fs)", args.out, time.time() - t0)
    return 0 if not math.isnan(m["ndcg10_lightgbm"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
