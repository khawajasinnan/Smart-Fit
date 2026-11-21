"""Beyond face shape (spec §23.27): can the user wear this style today, and
does it suit the occasion?

* Length: a style longer than the user's hair can't be worn without growing
  it out, so it ranks lower (shorter is always possible: a cut).
* Texture: a wavy style suits naturally wavy hair, a sleek one straight hair;
  the other way round needs daily styling, so a small penalty.
* Occasion (from the chat or the hairstyle screen): neat styles for formal
  events (nikah, walima, office, interview ...), volume or waves for festive
  ones (mehndi, wedding, party ...).
* Outfit (SFR-029, the try-on's "Find a matching hairstyle"): the chosen
  outfit's style category, read from its name and type: formal (suit,
  sherwani, prince coat ...) -> neat; festive (lehenga, sharara, bridal ...) ->
  volume or waves; casual (tee, hoodie, jeans ...) -> relaxed (waves, fringe
  or short); sporty (activewear, track ...) -> short and easy.

Small, explainable adjustments added to the face-shape suitability
(shape_classifier.suitability); each one that helps comes with a reason.
"""

from __future__ import annotations

from services.hairstyle.shape_classifier import HIGH_TOP, WIDE_SIDES, StyleFeatures

import re

LENGTHS = {"short": 0, "medium": 1, "long": 2}
FORMAL = {"nikah", "walima", "baraat", "office", "interview", "funeral", "formal"}
FESTIVE = {"mehndi", "mayun", "wedding", "party", "eid", "date", "festive"}

# The outfit's style category, from its product name / type (first match wins:
# "embroidered kurta set for a wedding" is festive before it is eastern casual).
OUTFIT_STYLES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("festive", re.compile(r"\b(lehenga|lehnga|sharara|gharara|bridal|maxi|anarkali|peshwas|party ?wear|formals?|"
                           r"festive|wedding|mehndi|chiffon|organza|embellished)\b", re.I)),
    # everyday eastern fabrics before "suit": a 2-piece lawn suit is day wear, not formal
    ("casual", re.compile(r"\b(lawn|khaddar|khaddi|cotton|cambric|linen|kurtis?)\b", re.I)),
    ("formal", re.compile(r"\b(sherwani|prince ?coat|pent ?coat|suit|blazer|tuxedo|waistcoat|formal shirt|"
                          r"dress shirt|three ?piece|two ?piece suit)\b", re.I)),
    ("sporty", re.compile(r"\b(active ?wear|activewear|track ?suit|tracksuit|trackpants?|gym|sports?|athletic|"
                          r"running|training)\b", re.I)),
    ("casual", re.compile(r"\b(t-?shirts?|tees?|hoodies?|sweatshirts?|jeans|denim|joggers?|shorts|polo|graphic|"
                          r"casual|cargo|lawn|kurti|button ?up|shirt)\b", re.I)),
)


def outfit_style(outfit: str | None) -> str | None:
    """"Embroidered Sherwani" -> "formal"; None when the outfit text says nothing we know."""
    for style, rx in OUTFIT_STYLES:
        if outfit and rx.search(outfit):
            return style
    return None


def personal_fit(f: StyleFeatures, hair_length: str | None, hair_wavy: bool | None,
                 occasion: str | None, outfit: str | None = None) -> tuple[float, list[str]]:
    delta, reasons = 0.0, []
    if hair_length in LENGTHS:
        grow = LENGTHS[f.length] - LENGTHS[hair_length]
        if grow > 0:
            delta -= 0.12 * grow  # needs months of growing out
        elif grow == 0:
            delta += 0.06
            reasons.append("works with your current length")
        else:
            delta += 0.03
            reasons.append("easy to get from your current hair with a cut")
    if hair_wavy is not None:
        if f.wavy == hair_wavy:
            delta += 0.08
            reasons.append("suits your natural waves" if hair_wavy else "works with your straight hair")
        else:
            delta -= 0.04
    occ = (occasion or "").lower().strip()
    if occ in FORMAL:
        if not f.wavy and f.top_volume < HIGH_TOP * 1.5 and f.side_width < WIDE_SIDES:
            delta += 0.08
            reasons.append(f"neat enough for {occ}")
    elif occ in FESTIVE:
        if f.wavy or f.top_volume >= HIGH_TOP:
            delta += 0.08
            reasons.append(f"has the volume for {occ}")
    style = outfit_style(outfit)
    neat = not f.wavy and f.top_volume < HIGH_TOP * 1.5 and f.side_width < WIDE_SIDES
    if style == "formal" and neat:
        delta += 0.07
        reasons.append("neat enough for your formal outfit")
    elif style == "festive" and (f.wavy or f.top_volume >= HIGH_TOP):
        delta += 0.07
        reasons.append("has the volume to match your festive outfit")
    elif style == "casual" and (f.wavy or f.bangs or f.length == "short"):
        delta += 0.05
        reasons.append("relaxed, like your casual outfit")
    elif style == "sporty" and f.length == "short":
        delta += 0.05
        reasons.append("short and easy with your sporty outfit")
    return delta, reasons
