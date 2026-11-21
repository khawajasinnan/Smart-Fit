"""Features for the learned recommendation models (spec §23.25).

One row per (shopper, product) pair. Every feature is a number with a plain
meaning, so a model's decision can be turned back into a sentence
(`explain`). The same function builds training rows and live rows, so the
models never see a feature computed differently in production.

Hard rules are NOT features: wrong gender, over a budget asked for in chat,
"not for me", wrong brand/colour asked for ... are filtered out before any
model runs (keyword_ranking.score_product returns 0 for them). The models
only order what is allowed.
"""

from __future__ import annotations

import re

from shared.color_harmony import extract_colors, outfit_harmony, skin_harmony
from shared.schemas.recommendation import UserProfileInput
from shared.occasion import EASTERN_WORDS, WESTERN_WORDS, find_occasion, occasion_match
from shared.style_match import style_hit
from shared.taxonomy import (
    ETHNICITY_KEYWORDS,
    product_conflicts_with_category,
    product_matches_category,
)
from services.recommendation.keyword_ranking import infer_clothing_size
from shared.size_estimate import letter_sizes
from shared.culture_styles import culture_key

# (name, what it means for the shopper). The order is the model's column order:
# never reorder without retraining (the model card stores it and is checked).
FEATURES: list[tuple[str, str]] = [
    ("category_match", "the garment type you asked for"),
    ("category_conflict", "a different garment type than you asked for"),
    ("gender_fit", "made for your gender"),
    ("color_preference", "your preferred colours"),
    ("style_match", "your style preferences"),
    ("occasion_match", "suits your occasion"),
    ("skin_harmony", "colours that suit your skin tone"),
    ("outfit_harmony", "colours that work together"),
    ("ethnicity_match", "your cultural style"),
    ("budget_fit", "fits your budget"),
    ("size_available", "your size is in stock"),
    ("body_flatter", "a cut that flatters your body shape"),
    ("taste_brand", "a brand you loved before"),
    ("taste_color", "a colour you loved before"),
    ("taste_category", "a type you loved before"),
    ("style_lean", "your eastern/western lean"),
    ("price_point", "your usual price range"),
    ("in_stock", "in stock"),
    ("info_complete", "full colour and size details"),
]
FEATURE_NAMES = [name for name, _ in FEATURES]
FEATURE_TEXT = dict(FEATURES)

_FEMALE_WORDS = re.compile(r"\b(women|womens|ladies|girls|female)\b")
_MALE_WORDS = re.compile(r"\b(men|mens|boys|male)\b")


def _norm(values) -> set[str]:
    return {v.lower().strip() for v in values or [] if isinstance(v, str) and v.strip()}


def product_text(product: dict) -> str:
    tags = product.get("tags") or []
    tags = " ".join(t for t in tags if isinstance(t, str)) if isinstance(tags, list) else str(tags)
    return f"{product.get('title') or ''} {tags} {product.get('category') or ''}".lower()


def occasion_of(profile: UserProfileInput, context: dict) -> str | None:
    """The occasion for this request: the chatbot's (dynamic prefs), else one
    named in the message, else the first one on the profile."""
    occasion = context.get("occasion")
    if occasion:
        return str(occasion).lower().strip()
    named = find_occasion(context.get("combined_text") or "")
    if named:
        return named
    occasions = [o for o in (profile.occasions or []) if isinstance(o, str) and o.strip()]
    return occasions[0].lower().strip() if occasions else None


def body_flatter(text: str, body_type: str | None) -> float:
    body = (body_type or "").lower()
    if not body:
        return 0.0
    rules = {  # checked in this order: "inverted triangle" must not read as "triangle"
        "inverted": ("a-line", "wide leg", "v-neck", "flared", "straight leg", "relaxed fit"),
        "pear": ("a-line", "flared", "wide leg", "boat neck"),
        "apple": ("empire", "v-neck", "straight", "a-line"),
        "hourglass": ("fitted", "belted", "wrap"),
        "rectangle": ("peplum", "belted", "layered", "ruffle", "waistcoat"),
        # men's shapes in onboarding (21 Nov 2026)
        "triangle": ("waistcoat", "blazer", "structured", "vertical stripe"),
        "oval": ("straight", "kurta", "longline", "vertical stripe", "regular fit"),
        "trapezoid": ("slim fit", "fitted", "polo", "tailored"),
    }
    shape = next((name for name in rules if name in body), None)
    return 1.0 if shape and any(w in text for w in rules[shape]) else 0.0


def extract(product: dict, profile: UserProfileInput, context: dict) -> dict[str, float]:
    """The feature row for one product, as {name: value}."""
    text = product_text(product)
    title = (product.get("title") or "").lower()
    tags = product.get("tags") or []
    category = (product.get("category") or "").lower()
    exact = context.get("exact_category")
    gender = context.get("gender") or (profile.gender or "").lower() or "female"
    taste = context.get("taste") or {}
    colors = extract_colors(product)
    product_colors = _norm(product.get("colors"))

    f: dict[str, float] = {}
    if exact:
        f["category_match"] = 1.0 if product_matches_category(title, tags, category, exact) else -1.0
        f["category_conflict"] = 1.0 if product_conflicts_with_category(title, tags, exact) else 0.0
    else:
        f["category_match"] = 0.0
        f["category_conflict"] = 0.0

    wrong = _MALE_WORDS if gender == "female" else _FEMALE_WORDS
    right = _FEMALE_WORDS if gender == "female" else _MALE_WORDS
    f["gender_fit"] = 0.0 if wrong.search(text) else (1.0 if right.search(text) else 0.5)

    wanted = _norm(context.get("colors")) | _norm(profile.preferred_colors)
    if wanted:
        hit = any(c in text or any(c in pc for pc in product_colors) for c in wanted)
        f["color_preference"] = 1.0 if hit else -1.0
    else:
        f["color_preference"] = 0.0

    f["style_match"] = 1.0 if style_hit(text, profile.style_preferences) else 0.0
    f["occasion_match"] = occasion_match(text, occasion_of(profile, context))
    f["skin_harmony"] = skin_harmony(colors, profile.skin_tone, profile.skin_undertone).score
    f["outfit_harmony"] = outfit_harmony(colors).score

    ethnicity = (context.get("ethnicity") or "").lower().strip()
    keywords = ETHNICITY_KEYWORDS.get(culture_key(ethnicity) or ethnicity, set())
    f["ethnicity_match"] = 1.0 if keywords and any(k in text for k in keywords) else 0.0

    price = product.get("price_pkr")
    budget = context.get("budget_max") or context.get("profile_budget_max") or profile.budget_max
    if price and budget:
        ratio = price / budget
        f["budget_fit"] = 1.0 if ratio <= 1 else max(0.0, 1.0 - (ratio - 1.0))
    else:
        f["budget_fit"] = 0.5

    fit = product.get("fit")  # the product's own size check (size_match.py), when it ran
    if fit is not None and getattr(fit, "compatible", None) is not None:
        f["size_available"] = 1.0 if fit.compatible else 0.0
    else:
        size = context.get("requested_size") or infer_clothing_size(profile)
        offered = {x for s in (product.get("sizes") or []) for x in letter_sizes(str(s))}
        if not offered or not size:
            f["size_available"] = 0.5
        else:  # whole sizes: "L" is not in an XL-only product (it used to match as text)
            wanted = letter_sizes(size) or {size.upper()}
            f["size_available"] = 1.0 if wanted & offered else 0.0

    f["body_flatter"] = body_flatter(text, profile.body_type)

    brand = (product.get("brand") or "").lower().strip()
    f["taste_brand"] = (1.0 if brand in _norm(taste.get("liked_brands"))
                        else -1.0 if brand in _norm(taste.get("disliked_brands")) else 0.0)
    words = product_colors | set(text.split())
    liked_c, disliked_c = _norm(taste.get("liked_colors")), _norm(taste.get("disliked_colors"))
    f["taste_color"] = (1.0 if any(any(c in w for w in words) for c in liked_c)
                        else -1.0 if product_colors & disliked_c else 0.0)
    f["taste_category"] = (1.0 if category and category in _norm(taste.get("liked_categories"))
                           else -1.0 if category and category in _norm(taste.get("disliked_categories")) else 0.0)
    lean = taste.get("style_lean")
    eastern, western = bool(EASTERN_WORDS.search(text)), bool(WESTERN_WORDS.search(text))
    if lean and (eastern or western):
        f["style_lean"] = 1.0 if (lean == "eastern" and eastern) or (lean == "western" and western) else -1.0
    else:
        f["style_lean"] = 0.0
    point = taste.get("price_point")
    f["price_point"] = 1.0 if price and point and 0.6 * point <= price <= 1.4 * point else 0.0

    f["in_stock"] = 1.0 if product.get("in_stock", True) else 0.0
    f["info_complete"] = (0.5 * bool(product_colors or colors)) + (0.5 * bool(product.get("sizes")))
    return f


def to_row(features: dict[str, float]) -> list[float]:
    return [float(features[name]) for name in FEATURE_NAMES]
