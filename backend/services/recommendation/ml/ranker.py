"""Live use of the trained models (spec §23.25): rank, validate, explain.

    hard filters (rules)  ->  LightGBM ranks  ->  Random Forest validates
                          ->  per-product explanation (SHAP contributions)

* Filtering stays rule-based and exact (keyword_ranking.rank_products drops
  every hard exclusion first); the models only order what is allowed.
* match_score shown in the app = 99 x (0.7 x calibrated LightGBM probability
  + 0.3 x Random Forest probability). Products are sorted by that same
  number, so the order and the percentages always agree.
* Explanations come from LightGBM's exact per-feature contributions
  (TreeSHAP, `pred_contrib=True`): the features that pushed this product up
  become its reasons, the strongest one that pulled it down becomes a
  "watch out". Each is a fixed sentence about a real attribute of the
  product, never generated text.
* No model files, or files trained on a different feature list: the service
  keeps the rule ranking (and says so in `ranking_model`).
"""

from __future__ import annotations

import json
import logging
import math
from pathlib import Path

import numpy as np

from shared.color_harmony import extract_colors, outfit_harmony, skin_harmony
from shared.schemas.recommendation import ExplanationFactor, ProductRecommendation, UserProfileInput
from services.recommendation.keyword_ranking import infer_clothing_size
from services.recommendation.size_match import shown_size
from shared.style_match import style_hit
from services.recommendation.ml.features import (
    FEATURE_NAMES,
    FEATURE_TEXT,
    extract,
    occasion_of,
    product_text,
    to_row,
)

logger = logging.getLogger("smartfit.recommendation.ml")

MODEL_DIR = Path(__file__).resolve().parent / "models"
VALIDATOR_DISAGREES = 0.25  # RF probability under this = the validator rejects the ranker's pick
MAX_REASONS = 4


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-x))


class LearnedRanker:
    def __init__(self, ranker, validator, card: dict) -> None:
        self.ranker = ranker
        self.validator = validator
        self.card = card
        cal = card["calibration"]
        self._coef, self._intercept = float(cal["coef"]), float(cal["intercept"])
        blend = card.get("blend") or {}
        self._w_rank = float(blend.get("lightgbm", 0.7))
        self._w_rf = float(blend.get("random_forest", 0.3))

    @classmethod
    def load(cls, model_dir: Path = MODEL_DIR) -> LearnedRanker | None:
        card_path = model_dir / "model_card.json"
        if not card_path.exists():
            logger.info("No trained recommendation models in %s: rule ranking only", model_dir)
            return None
        try:
            import joblib
            import lightgbm as lgb

            card = json.loads(card_path.read_text(encoding="utf-8"))
            if card.get("features") != FEATURE_NAMES:
                logger.warning("Recommendation models were trained on other features: retrain them")
                return None
            ranker = lgb.Booster(model_file=str(model_dir / "ranker.txt"))
            validator = joblib.load(model_dir / "validator.joblib")
            return cls(ranker, validator, card)
        except Exception:
            logger.exception("Couldn't load the recommendation models: rule ranking only")
            return None

    # ── scoring ──────────────────────────────────────────────────────────
    def predict(self, rows: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """(final 0..1, calibrated ranker 0..1, validator 0..1) per row."""
        raw = self.ranker.predict(rows)
        p_rank = _sigmoid(self._coef * raw + self._intercept)
        p_rf = self.validator.predict_proba(rows)[:, 1]
        final = self._w_rank * p_rank + self._w_rf * p_rf
        return final, p_rank, p_rf

    def rerank(self, raw_items: list[dict], recs: list[ProductRecommendation],
               profile: UserProfileInput, context: dict) -> list[ProductRecommendation]:
        """Re-order the rule-filtered recommendations with the models."""
        if not recs:
            return recs
        by_id = {p.get("id"): p for p in raw_items}
        items = [by_id.get(r.id) or r.model_dump() for r in recs]
        feats = [extract(p, profile, context) for p in items]
        rows = np.asarray([to_row(f) for f in feats], dtype=np.float64)
        final, p_rank, p_rf = self.predict(rows)
        contrib = self.ranker.predict(rows, pred_contrib=True)  # (n, features + bias)

        out: list[tuple[float, ProductRecommendation]] = []
        for i, rec in enumerate(recs):
            score = float(final[i])
            disagrees = p_rank[i] >= 0.5 and p_rf[i] < VALIDATOR_DISAGREES
            if disagrees:  # second opinion says no: never above the agreed ones
                score = min(score, 0.49)
            factors = explain(contrib[i][:-1], feats[i], items[i], profile, context)
            reasons = [f.text for f in factors if f.impact > 0][:MAX_REASONS - 1]
            watch = next((f.text for f in factors if f.impact < 0), None)
            if watch:
                reasons.append(f"Watch out: {watch}")
            if not reasons:
                reasons = rec.match_reasons or ["curated for your SmartFit profile"]
            out.append((score, rec.model_copy(update={
                "match_score": max(1, min(99, round(99 * score))),
                "match_reasons": reasons[:MAX_REASONS],
                "ranking_model": "lightgbm+random_forest",
                "ranker_score": round(float(p_rank[i]), 3),
                "validator_score": round(float(p_rf[i]), 3),
                "validated": not disagrees,
                "explanation": factors[:6],
                "suitability": suitability(feats[i], items[i], profile, context),
            })))
        out.sort(key=lambda t: t[0], reverse=True)
        return [r for _, r in out]


# ── explanations ─────────────────────────────────────────────────────────
def _describe(name: str, value: float, positive: bool, product: dict,
              profile: UserProfileInput, context: dict) -> str | None:
    """A sentence for a feature that moved the score, or None when there is
    nothing true and useful to say (e.g. a neutral value)."""
    colors = extract_colors(product)
    garment = context.get("detected_garment") or context.get("exact_category") or "what you asked for"
    if name == "category_match":
        return f"exact match for {garment}" if value > 0 else (None if value == 0 else f"not exactly {garment}")
    if name == "category_conflict":
        return None if value == 0 else f"a different type of garment than {garment}"
    if name == "gender_fit":
        who = "women" if (context.get("gender") or profile.gender or "female") == "female" else "men"
        return f"made for {who}" if value == 1 else None
    if name == "color_preference":
        if value > 0:
            return "in a colour you prefer"
        return "not in your preferred colours" if value < 0 else None
    if name == "style_match":
        style = style_hit(product_text(product), profile.style_preferences)
        return f"matches your {style} style" if value > 0 and style else None
    if name == "occasion_match":
        occasion = occasion_of(profile, context)
        if not occasion:
            return None
        if value >= 1:
            return f"right for {occasion}"
        if value >= 0.5:
            return f"fits the {occasion} dress code"
        return f"not typical {occasion} wear"
    if name == "skin_harmony":
        h = skin_harmony(colors, profile.skin_tone, profile.skin_undertone)
        if not h.known:
            return None
        return h.reason if (positive and h.score >= 0.6) or (not positive and h.score <= 0.45) else None
    if name == "outfit_harmony":
        h = outfit_harmony(colors)
        if not h.known:
            return None
        return h.reason if (positive and h.score >= 0.75) or (not positive and h.score <= 0.45) else None
    if name == "ethnicity_match":
        return f"matches your {context.get('ethnicity', '').title()} style" if value > 0 else None
    if name == "budget_fit":
        if value >= 1:
            return "within your budget"
        return "above your budget" if value < 0.5 else None
    if name == "size_available":
        # the product's own label for the user's size (size_match.py), as on the card;
        # it used to say the generic chest-only size ("XXXL") while the card said "XXL"
        own = shown_size(product)
        size = own or context.get("requested_size") or infer_clothing_size(profile)
        if value >= 1:
            return f"size {size} in stock"
        return f"size {size} isn't listed" if value == 0 else None
    if name == "body_flatter":
        return f"a cut that flatters your {profile.body_type} shape" if value > 0 else None
    if name == "taste_brand":
        if value > 0:
            return f"you loved {product.get('brand')} before"
        return f"you passed on {product.get('brand')} before" if value < 0 else None
    if name == "taste_color":
        if value > 0:
            return "a colour you loved before"
        return "a colour you passed on before" if value < 0 else None
    if name == "taste_category":
        if value > 0:
            return "a type you loved before"
        return "a type you passed on before" if value < 0 else None
    if name == "style_lean":
        lean = (context.get("taste") or {}).get("style_lean")
        if not lean:
            return None
        return f"fits your {lean} style" if value > 0 else f"not your usual {lean} style"
    if name == "price_point":
        return "in your usual price range" if value > 0 else None
    if name == "in_stock":
        return None if value else "may be sold out"
    return None  # info_complete: not a reason a shopper cares about


def favourable(name: str, value: float) -> bool | None:
    """Is this feature value good news for the shopper? None = neutral, or
    judged by its own sentence (the colour features check their own scores)."""
    if name in ("skin_harmony", "outfit_harmony", "info_complete"):
        return None
    if name == "category_conflict":
        return False if value > 0 else None
    if name == "occasion_match":
        return True if value >= 0.5 else False
    if name == "budget_fit":
        return True if value >= 1 else (False if value < 0.5 else None)
    if name in ("gender_fit", "size_available", "in_stock"):
        return True if value >= 1 else (False if value == 0 else None)
    if value > 0:
        return True
    if value < 0:
        return False
    return None


def explain(contributions: np.ndarray, feats: dict[str, float], product: dict,
            profile: UserProfileInput, context: dict) -> list[ExplanationFactor]:
    """Features ordered by how much they moved this product's score, each with
    its sentence and signed impact (LightGBM raw-score units, rounded)."""
    order = np.argsort(-np.abs(contributions))
    factors: list[ExplanationFactor] = []
    for j in order:
        impact = float(contributions[j])
        if abs(impact) < 1e-3 or math.isnan(impact):
            continue
        name = FEATURE_NAMES[j]
        good = favourable(name, feats[name])
        if good is not None and good != (impact > 0):
            # e.g. "size in stock" with a slightly negative contribution (a
            # model interaction): saying it as a "watch out" would be wrong
            continue
        text = _describe(name, feats[name], impact > 0, product, profile, context)
        if text:
            factors.append(ExplanationFactor(feature=name, label=FEATURE_TEXT[name], text=text,
                                             value=round(feats[name], 3), impact=round(impact, 3)))
    return factors


def suitability(feats: dict[str, float], product: dict, profile: UserProfileInput,
                context: dict) -> dict[str, int | None]:
    """Suitability matching, 0..100 per aspect (None: not enough information)."""
    colors = extract_colors(product)
    skin = skin_harmony(colors, profile.skin_tone, profile.skin_undertone)
    combo = outfit_harmony(colors)
    size = feats["size_available"]
    return {
        "skin_tone": round(100 * skin.score) if skin.known else None,
        "colours": round(100 * combo.score) if combo.known else None,
        "size": None if size == 0.5 else round(100 * size),
        "body_shape": 100 if feats["body_flatter"] else None,
        "occasion": round(100 * feats["occasion_match"]) if occasion_of(profile, context) else None,
        "budget": None if feats["budget_fit"] == 0.5 else round(100 * feats["budget_fit"]),
    }
