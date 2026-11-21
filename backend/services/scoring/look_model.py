"""Random Forest look validator (spec §23.25): an interpretable second opinion
on the formula's look score.

The formula (formula.py) is a fixed weighted sum: easy to read, but it can't
learn that one weak part can sink a whole look (a size that's too small makes
a perfect colour irrelevant). The Random Forest regressor learns 0..100 from
the component scores, and every prediction is decomposed into exact
per-component contributions by walking each tree's decision path (the Saabas
method: prediction = average leaf value = bias + sum of contributions), so the
app can say *which* part of the look raised or lowered it.

Until real ratings exist it is trained on weak labels: generated looks over
the real catalog, rated by the formula plus the stylist's "one weak part caps
the look" rules below (`expert_rating`). feedback_retrain.py retrains it with
real ratings mixed in (SFR-034).
"""

from __future__ import annotations

import json
import logging
import random
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from services.scoring.formula import COMPONENTS, Component, components_for, compute_score

logger = logging.getLogger("smartfit.scoring.model")

MODEL_DIR = Path(__file__).resolve().parent / "models"
# component scores + "is it known" flags (an unknown part scored neutral is
# different evidence from a measured one)
FEATURES = [f"{k}_score" for k in COMPONENTS] + [f"{k}_known" for k in COMPONENTS]
AGREE_WITHIN = 10.0  # formula and forest within this many points = they agree


def to_row(components: list[Component]) -> list[float]:
    by_key = {c.key: c for c in components}
    row = [by_key[k].score if k in by_key else 50.0 for k in COMPONENTS]
    row += [1.0 if (k in by_key and by_key[k].known) else 0.0 for k in COMPONENTS]
    return row


def expert_rating(components: list[Component], formula_score: float) -> float:
    """A stylist's overall rating: the formula, but one bad part caps the look."""
    by_key = {c.key: c for c in components}
    rating = formula_score
    fit = by_key["fit"]
    if fit.score <= 35:
        rating = min(rating, 55.0)  # too small: it won't look right whatever the colour
    elif fit.score <= 45:
        rating = min(rating, 62.0)  # too big
    colour = by_key["colour"]
    if colour.known and colour.score < 40:
        rating -= 8.0
    occasion = by_key["occasion"]
    if occasion.known and occasion.score <= 30:
        rating = min(rating, 50.0)  # wrong for the event
    hair = by_key.get("hairstyle")
    if hair and hair.score < 35:
        rating -= 5.0
    if all(c.score >= 80 for c in components if c.known) and sum(c.known for c in components) >= 3:
        rating += 4.0  # everything works together
    return max(0.0, min(100.0, rating))


@dataclass
class Validation:
    predicted: float
    agrees: bool
    contributions: dict[str, float]  # component -> points it added/removed vs the average look
    baseline: float  # the average look's score (the forest's bias)


class LookValidator:
    def __init__(self, forest, card: dict) -> None:
        self.forest = forest
        self.card = card

    @classmethod
    def load(cls, model_dir: Path = MODEL_DIR) -> LookValidator | None:
        card_path = model_dir / "look_card.json"
        if not card_path.exists():
            return None
        try:
            import joblib

            card = json.loads(card_path.read_text(encoding="utf-8"))
            if card.get("features") != FEATURES:
                logger.warning("Look model trained on other features: retrain it")
                return None
            return cls(joblib.load(model_dir / "look_rf.joblib"), card)
        except Exception:
            logger.exception("Couldn't load the look model")
            return None

    def validate(self, components: list[Component], formula_score: float) -> Validation:
        x = np.asarray(to_row(components), dtype=np.float64)
        bias, contrib = tree_contributions(self.forest, x)
        predicted = float(bias + contrib.sum())
        per_component: dict[str, float] = {}
        for i, name in enumerate(FEATURES):
            key = name.rsplit("_", 1)[0]
            per_component[key] = per_component.get(key, 0.0) + float(contrib[i])
        present = {c.key for c in components}
        per_component = {k: round(v, 1) for k, v in per_component.items() if k in present}
        return Validation(round(predicted, 1), abs(predicted - formula_score) <= AGREE_WITHIN,
                          per_component, round(float(bias), 1))


def tree_contributions(forest, x: np.ndarray) -> tuple[float, np.ndarray]:
    """Saabas decomposition for a RandomForestRegressor: (bias, contribution
    per feature), with bias + contributions.sum() == forest.predict([x])."""
    contrib = np.zeros(x.shape[0])
    bias = 0.0
    for est in forest.estimators_:
        t = est.tree_
        node = 0
        bias += float(t.value[0].ravel()[0])
        while t.children_left[node] != -1:
            f = t.feature[node]
            nxt = t.children_left[node] if x[f] <= t.threshold[node] else t.children_right[node]
            contrib[f] += float(t.value[nxt].ravel()[0] - t.value[node].ravel()[0])
            node = nxt
    n = len(forest.estimators_)
    return bias / n, contrib / n


# ── training ─────────────────────────────────────────────────────────────
SKIN = ["Fair", "Light", "Medium", "Olive", "Brown", "Dark", None]
STYLES = ["casual", "formal", "ethnic", "streetwear", "classic", "embroidered", "printed", "minimalist"]
COLOURS = ["black", "white", "navy", "maroon", "green", "pink", "beige", "olive", "mustard", "teal", "red"]
OCCASIONS = [None, "mehndi", "nikah", "eid", "office", "casual", "party", "wedding", "date", "interview"]
FITS = ["fits", "fits", "fits", "unknown", "small", "big"]


def generate_looks(catalog: list[dict], n: int, seed: int) -> tuple[list[list[float]], list[float]]:
    rng = random.Random(seed)
    rows, labels = [], []
    for _ in range(n):
        product = rng.choice(catalog)
        profile = {
            "skin_tone": rng.choice(SKIN),
            "style_preferences": rng.sample(STYLES, rng.randint(0, 2)),
            "preferred_colors": rng.sample(COLOURS, rng.randint(0, 2)),
        }
        hair = {"name": "Style", "score": rng.uniform(0.2, 0.95), "face_shape": "oval"} \
            if rng.random() < 0.5 else None
        comps = components_for(product, profile, rng.choice(OCCASIONS), rng.choice(FITS), None, hair)
        formula, _ = compute_score(comps)
        rows.append(to_row(comps))
        labels.append(expert_rating(comps, formula) + rng.gauss(0, 3))
    return rows, labels


def train(rows: list[list[float]], labels: list[float], out_dir: Path = MODEL_DIR, seed: int = 42,
          label_source: str = "weak", sample_weight: list[float] | None = None, version: str | None = None,
          real_rows: int = 0) -> dict:
    import joblib
    import sklearn
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.metrics import mean_absolute_error, r2_score
    from sklearn.model_selection import train_test_split

    X, y = np.asarray(rows), np.asarray(labels)
    w = np.asarray(sample_weight) if sample_weight is not None else np.ones(len(y))
    Xtr, Xva, ytr, yva, wtr, _ = train_test_split(X, y, w, test_size=0.2, random_state=seed)
    forest = RandomForestRegressor(n_estimators=150, max_depth=10, min_samples_leaf=5,
                                   n_jobs=-1, random_state=seed)
    forest.fit(Xtr, ytr, sample_weight=wtr)
    pred = forest.predict(Xva)
    from datetime import UTC, datetime

    card = {
        "version": version or datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ"),
        "trained_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "real_rows": real_rows,
        "features": FEATURES,
        "label_source": label_source,
        "rows": int(len(y)),
        "metrics": {"valid_mae": round(float(mean_absolute_error(yva, pred)), 2),
                    "valid_r2": round(float(r2_score(yva, pred)), 4)},
        "importance": dict(sorted(((f, round(float(v), 4)) for f, v in
                                   zip(FEATURES, forest.feature_importances_)), key=lambda kv: -kv[1])),
        "versions": {"scikit-learn": sklearn.__version__},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump(forest, out_dir / "look_rf.joblib", compress=3)
    (out_dir / "look_card.json").write_text(json.dumps(card, indent=2), encoding="utf-8")
    return card
