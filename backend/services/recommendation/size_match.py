"""Each product's own size for this user, and only products made in it (21 Nov 2026).

The user's report: a man whose measurements are XL/XXL saw "Trending for you"
products sold only in S and M, and every card said the same size, worked out
from chest alone with one generic table (trousers "30, 34" and unstitched
fabric got a letter size too).

Now, per product (shared/size_fit.py, the try-on's own check):
- the product's own size chart when it has one (Outfitters),
- otherwise the user's letter size (shared/size_estimate.py: men's or women's
  table, the largest of chest / waist / hip) read against the store's labels
  ("L (14)", "X-Large", "S-M" ...),
- never a conversion between size systems: collar "15.5", inches '40"', jeans
  "W 34" and fabric are shown with their own sizes and no "Your size".
A product known not to be made, or not in stock, in the user's size is left
out; the card shows the product's own label for the user's size.
"""

from __future__ import annotations

from types import SimpleNamespace

from shared.brands import normalize_gender
from shared.schemas.recommendation import UserProfileInput
from shared.size_estimate import estimate_size, letter_sizes
from shared.size_fit import SizeFit, clean_body, size_fit


def user_letter_size(profile: UserProfileInput, requested: str | None = None) -> str | None:
    """The size asked for in the chat, else the size the user says they buy, else the one
    their measurements give (None with none of these)."""
    if requested:
        return next(iter(letter_sizes(requested)), requested.strip().upper())
    if profile.usual_size and letter_sizes(profile.usual_size):
        return next(iter(letter_sizes(profile.usual_size)))
    has_body = any(v and v > 0 for v in (profile.chest_cm, profile.waist_cm, profile.hip_cm))
    has_bmi = bool(profile.height_cm and profile.weight_kg)
    if not (has_body or has_bmi):
        return None
    gender = "female" if normalize_gender(profile.gender) == "female" else "male"
    label, source = estimate_size({}, gender, profile.chest_cm or None, profile.height_cm, profile.weight_kg,
                                  profile_waist=profile.waist_cm or None, profile_hip=profile.hip_cm or None)
    return None if source == "default_fallback" else label


def body_of(profile: UserProfileInput) -> dict[str, float]:
    return clean_body({"chest_cm": profile.chest_cm, "waist_cm": profile.waist_cm, "hip_cm": profile.hip_cm})


def product_fit(item: dict, letter: str | None, body: dict[str, float]) -> SizeFit:
    product = SimpleNamespace(sizes=list(item.get("sizes") or []), all_sizes=list(item.get("all_sizes") or []),
                              size_chart=item.get("size_chart") or {})
    return size_fit(product, letter, body)  # type: ignore[arg-type]  (duck-typed: sizes, all_sizes, size_chart)


def fit_products(raw: list[dict], profile: UserProfileInput, requested: str | None = None) -> tuple[list[dict], int]:
    """Each item gets item["fit"]; items known not to come in the user's size are
    dropped. Returns (kept items, how many were dropped)."""
    letter = user_letter_size(profile, requested)
    body = body_of(profile)
    if not letter and not body:
        return raw, 0
    kept: list[dict] = []
    for item in raw:
        fit = product_fit(item, letter, body)
        if fit.compatible is False:
            continue
        kept.append({**item, "fit": fit})
    return kept, len(raw) - len(kept)


def shown_size(item: dict) -> str | None:
    """The size the card shows ("Your size: ..."): the product's own label, only when known."""
    fit = item.get("fit")
    return fit.recommended_size if isinstance(fit, SizeFit) and fit.compatible else None
