"""Spec §7.3-7.4 ranking: natural-language query -> FashionCLIP text vector
-> hard filters (gender, budget, size in stock) -> cosine similarity -> top N.

(The app's older keyword ranker lives in keyword_ranking.py.)
"""

from __future__ import annotations

import re
from collections import Counter

import numpy as np

from shared.schemas.catalog import ScrapedProduct
from shared.schemas.recommendation import CvSummary, RecommendProfile, SessionInputs

# Size / fit check (SFR-025): shared with the try-on service.
from shared.size_fit import (  # noqa: F401  (re-exported for existing imports)
    LETTER_SIZES,
    LOOSE_EASE_CM,
    MIN_EASE_CM,
    ONE_SIZE,
    SizeFit,
    fit_from_chart,
    size_fit,
)

GENDER_TO_CATALOG = {"male": "men", "man": "men", "men": "men", "female": "women", "woman": "women", "women": "women"}


def catalog_gender(gender: str | None) -> str | None:
    return GENDER_TO_CATALOG.get((gender or "").strip().lower())


def _clean(text: str | None) -> str:
    return re.sub(r"\s+", " ", (text or "").strip())


def _article(word: str) -> str:
    """a/an by sound: vowels and silent-h words ("an hourglass")."""
    return "an" if word[:1] in "aeiou" or word.startswith(("hour", "honest", "heir")) else "a"


def build_query_text(profile: RecommendProfile, session: SessionInputs, cv: CvSummary) -> str:
    """Spec §7.3: one readable sentence from profile + session + CV, e.g.
    "elegant navy outfit for a wedding for a woman with an hourglass body
    type, medium skin tone, size M, budget under 5000 PKR, style: casual"."""
    who = {"men": "a man", "women": "a woman"}.get(catalog_gender(profile.gender) or "", "")
    body = _clean(cv.body_type or profile.body_type).replace("_", " ").lower()
    skin = _clean(cv.skin_tone or profile.skin_tone).lower()
    size = _clean(cv.estimated_size).upper()

    head = " ".join(x for x in (_clean(session.mood), _clean(session.color_pref), "outfit") if x)
    occasion = _clean(session.occasion).lower()
    if occasion:
        head += f" for {_article(occasion)} {occasion}"
    parts = [head + (f" for {who}" if who else "")]
    if body:
        parts[0] += f" with {_article(body)} {body} body type"
    if skin:
        parts.append(f"{skin} skin tone")
    if size:
        parts.append(f"size {size}")
    if session.budget_max:
        parts.append(f"budget under {int(session.budget_max)} PKR")
    styles = [s for s in (_clean(x).lower() for x in profile.style_preferences) if s]
    if styles:
        parts.append("style: " + ", ".join(styles[:4]))
    return ", ".join(parts)


def rank(
    products: list[ScrapedProduct],
    matrix: np.ndarray,
    query_vector: np.ndarray,
    *,
    gender: str | None,
    size: str | None,
    budget_max: float | None,
    top_n: int,
    body: dict[str, float] | None = None,
) -> tuple[list[tuple[ScrapedProduct, float, SizeFit]], Counter]:
    """Hard filters first (spec §7.4), then cosine similarity, descending.

    Size: a product is removed only when we *know* the user's size isn't
    available (fit False); unknown fit is kept and flagged. products[i]
    matches matrix[i]; vectors are L2-normalised (dot = cosine).
    """
    body = {k: v for k, v in (body or {}).items() if v}
    removed: Counter = Counter()
    want_gender = catalog_gender(gender)
    keep: list[int] = []
    fits: dict[int, SizeFit] = {}
    for i, p in enumerate(products):
        if want_gender and p.gender not in (want_gender, "unisex"):
            removed["gender"] += 1
            continue
        if budget_max is not None and p.price > budget_max:
            removed["budget"] += 1
            continue
        fit = size_fit(p, size, body)
        if fit.compatible is False:
            removed["size"] += 1
            continue
        fits[i] = fit
        keep.append(i)
    if not keep:
        return [], removed
    scores = matrix[keep] @ query_vector
    order = np.argsort(-scores)[:top_n]
    return [(products[keep[j]], float(scores[j]), fits[keep[j]]) for j in order], removed
