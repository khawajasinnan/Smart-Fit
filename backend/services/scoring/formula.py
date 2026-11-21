"""Look score formula (SFR-032, spec §12).

    score = w_style * style + w_colour * colour_harmony + w_fit * fit
          + w_occasion * occasion [+ w_hair * hairstyle]

Each component is 0..100 and comes with the sentence that explains it. The
spec's weights are 0.25 each; the hairstyle (when the user chose one) joins
as a fifth component with the same weight, and the weights are renormalised
over the components that are present. feedback_retrain.py can replace the
weights from real user ratings (SFR-034); they live in weights.json.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from shared.color_harmony import extract_colors, outfit_harmony, skin_harmony
from shared.occasion import occasion_clash, occasion_match
from shared.style_match import style_hit

# in the models folder: on the persistent volume when hosted (spec §23.26)
WEIGHTS_FILE = Path(__file__).resolve().parent / "models" / "weights.json"
DEFAULT_WEIGHTS = {"style": 0.25, "colour": 0.25, "fit": 0.25, "occasion": 0.25, "hairstyle": 0.25}
COMPONENTS = ("style", "colour", "fit", "occasion", "hairstyle")
LABELS = {
    "style": "Style match",
    "colour": "Colour harmony",
    "fit": "Size & fit",
    "occasion": "Occasion",
    "hairstyle": "Hairstyle",
}
FIT_SCORES = {"fits": 95.0, "unknown": 65.0, "big": 45.0, "small": 35.0}


@dataclass
class Component:
    key: str
    score: float  # 0..100
    note: str
    known: bool = True  # False: not enough information, a neutral score was used


def load_weights(path: Path = WEIGHTS_FILE) -> dict[str, float]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        weights = {k: float(data["weights"][k]) for k in COMPONENTS}
        if all(w >= 0 for w in weights.values()) and sum(weights.values()) > 0:
            return weights
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return dict(DEFAULT_WEIGHTS)


def _text(product: dict) -> str:
    tags = product.get("tags") or []
    tags = " ".join(t for t in tags if isinstance(t, str)) if isinstance(tags, list) else str(tags)
    return f"{product.get('title') or ''} {tags} {product.get('category') or ''}".lower()


def style_component(product: dict, profile: dict) -> Component:
    text = _text(product)
    styles = [s for s in profile.get("style_preferences") or [] if isinstance(s, str) and s.strip()]
    colours = [c for c in profile.get("preferred_colors") or [] if isinstance(c, str) and c.strip()]
    product_colours = " ".join(c.lower() for c in product.get("colors") or [] if isinstance(c, str))
    matched_style = style_hit(text, styles)
    colour_hit = next((c for c in colours if c.lower() in text or c.lower() in product_colours), None)
    if not styles and not colours:
        return Component("style", 65.0, "Add style preferences to your profile for a sharper style match.", False)
    score = 60.0 + (25.0 if matched_style else 0.0) + (15.0 if colour_hit else 0.0)
    if not matched_style and not colour_hit:
        score = 45.0
    parts = []
    if matched_style:
        parts.append(f"matches your {matched_style} style")
    if colour_hit:
        parts.append(f"is in {colour_hit}, a colour you prefer")
    note = ("It " + " and ".join(parts) + ".") if parts else "It is a step away from your usual style preferences."
    return Component("style", score, note)


def colour_component(product: dict, profile: dict) -> Component:
    colours = extract_colors(product)
    skin = skin_harmony(colours, profile.get("skin_tone"), profile.get("skin_undertone"))
    combo = outfit_harmony(colours)
    if not skin.known and not combo.known:
        return Component("colour", 60.0, "The store doesn't list this item's colour, so colour harmony is a guess.",
                         False)
    if skin.known and combo.known:
        score = 100 * (0.65 * skin.score + 0.35 * combo.score)
        note = f"{skin.reason[0].upper()}{skin.reason[1:]}; {combo.reason}."
    elif skin.known:
        score, note = 100 * skin.score, f"{skin.reason[0].upper()}{skin.reason[1:]}."
    else:
        score = 100 * combo.score
        note = f"{combo.reason[0].upper()}{combo.reason[1:]} (add your skin tone for a personal colour check)."
    return Component("colour", score, note)


def fit_component(fit_status: str, size: str | None) -> Component:
    status = fit_status if fit_status in FIT_SCORES else "unknown"
    label = f"size {size}" if size else "this size"
    notes = {
        "fits": f"{label[0].upper()}{label[1:]} fits your measurements.",
        "small": f"{label[0].upper()}{label[1:]} is small for you.",
        "big": f"{label[0].upper()}{label[1:]} is big for you.",
        "unknown": "The fit couldn't be checked against your measurements.",
    }
    return Component("fit", FIT_SCORES[status], notes[status], status != "unknown")


def occasion_component(product: dict, occasion: str | None) -> Component:
    if not occasion:
        return Component("occasion", 70.0, "No occasion given — scored as everyday wear.", False)
    colours = " ".join(c for c in product.get("colors") or [] if isinstance(c, str))
    text = f"{_text(product)} {colours}".lower()
    m = occasion_match(text, occasion)
    if m >= 1:
        return Component("occasion", 95.0, f"Right for {occasion}.")
    if m >= 0.5:
        return Component("occasion", 72.0, f"Fits the {occasion} dress code.")
    clash = occasion_clash(text, occasion)
    if clash:
        article = "an" if occasion[:1].lower() in "aeiou" else "a"
        return Component("occasion", 15.0, f"{clash[0].upper()}{clash[1:]} doesn't suit {article} {occasion}.")
    return Component("occasion", 30.0, f"Not typical {occasion} wear.")


def hairstyle_component(hairstyle: dict | None) -> Component | None:
    if not hairstyle or hairstyle.get("score") is None:
        return None
    score = max(0.0, min(1.0, float(hairstyle["score"]))) * 100
    name = hairstyle.get("name") or "This hairstyle"
    shape = (hairstyle.get("face_shape") or "").lower()
    face = f"your {shape} face" if shape else "your face shape"
    if score >= 65:
        note = f"{name} suits {face}."
    elif score >= 45:
        note = f"{name} is a neutral choice for {face}."
    else:
        note = f"{name} is not the most flattering choice for {face}."
    return Component("hairstyle", score, note)


def components_for(product: dict, profile: dict, occasion: str | None, fit_status: str,
                   fit_size: str | None, hairstyle: dict | None) -> list[Component]:
    parts = [
        style_component(product, profile),
        colour_component(product, profile),
        fit_component(fit_status, fit_size),
        occasion_component(product, occasion),
    ]
    hair = hairstyle_component(hairstyle)
    if hair:
        parts.append(hair)
    return parts


def compute_score(components: list[Component], weights: dict[str, float] | None = None
                  ) -> tuple[float, dict[str, float]]:
    """(0..100 score, the normalised weights actually used)."""
    weights = weights or load_weights()
    used = {c.key: weights.get(c.key, 0.0) for c in components}
    total = sum(used.values()) or 1.0
    used = {k: w / total for k, w in used.items()}
    score = sum(used[c.key] * c.score for c in components)
    return round(score, 1), {k: round(w, 4) for k, w in used.items()}
