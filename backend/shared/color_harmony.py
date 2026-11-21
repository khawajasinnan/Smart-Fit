"""Colour harmony with HSV rules (spec §12: "colour harmony via HSV rules").

Used by both the recommendation ranker (as model features) and the look score
(SFR-032), so the two never disagree about what "flatters your skin tone" means.

Two questions, each answered 0..1 (0.5 = neutral / unknown):

* skin_harmony   — do the garment's colours suit the wearer's skin tone?
* outfit_harmony — do the garment's own colours go together?

Everything here is a transparent rule over named colours (no model), so every
number can be explained back to the user in a sentence.
"""

from __future__ import annotations

import colorsys
import re
from dataclasses import dataclass, field

# Named colour -> its usual swatch (sRGB hex). Hue and saturation come from
# HSV (spec §12); lightness is CIE L* because HSV "value" says a pure yellow
# and a white are equally light, which is wrong for contrast with skin.
_HEX: dict[str, str] = {
    "black": "#111111", "charcoal": "#36454F", "grey": "#8C8C8C", "gray": "#8C8C8C",
    "silver": "#C0C0C0", "white": "#FFFFFF", "off white": "#F4F1EA", "ivory": "#FFFFF0",
    "cream": "#FFFDD0", "beige": "#E8D9B5", "khaki": "#C3B091", "tan": "#D2B48C",
    "camel": "#C19A6B", "brown": "#7B4A2D", "rust": "#B7410E", "copper": "#B87333",
    "bronze": "#CD7F32", "red": "#D7263D", "maroon": "#800000", "burgundy": "#800020",
    "wine": "#722F37", "ruby": "#9B111E", "pink": "#F4A7C0", "rose pink": "#F19CBB",
    "magenta": "#D0208F", "coral": "#FF7F50", "peach": "#FFCBA4", "orange": "#FF8C00",
    "mustard": "#E1AD01", "yellow": "#FFD500", "gold": "#D4AF37", "olive": "#708238",
    "green": "#2E8B57", "emerald": "#009B77", "sage": "#9CAF88", "mint": "#AAF0D1",
    "teal": "#008080", "turquoise": "#30D5C8", "sky blue": "#87CEEB", "blue": "#1F5FBF",
    "royal blue": "#2A52BE", "navy": "#1B2A4A", "denim": "#4F6D8F", "lavender": "#C8A2C8",
    "purple": "#6A1B9A", "plum": "#8E4585",
}


def _rgb(hex_: str) -> tuple[float, float, float]:
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def _lightness(rgb: tuple[float, float, float]) -> float:
    """CIE L* (0 black .. 100 white) of an sRGB colour."""
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    return 116 * (y ** (1 / 3) if y > 0.008856 else 7.787 * y + 16 / 116) - 16


def _hsvl(hex_: str) -> tuple[float, float, float, float]:
    rgb = _rgb(hex_)
    h, s, v = colorsys.rgb_to_hsv(*rgb)
    return h * 360, s, v, _lightness(rgb)


# name -> (hue degrees, saturation 0-1, value 0-1, L* 0-100)
COLOR_HSV: dict[str, tuple[float, float, float, float]] = {n: _hsvl(h) for n, h in _HEX.items()}

# Colours that go with anything (low saturation, or navy/denim by convention).
NEUTRALS = {"black", "charcoal", "grey", "gray", "silver", "white", "off white", "ivory",
            "cream", "beige", "khaki", "tan", "camel", "navy", "denim"}

# Longest names first so "off white" wins over "white", "sky blue" over "blue".
_NAMES = sorted(COLOR_HSV, key=len, reverse=True)
_NAME_RE = re.compile(r"\b(" + "|".join(re.escape(n) for n in _NAMES) + r")\b")

# Skin-tone buckets: the six ITA buckets cv_analysis uses (fair..deep) plus the
# labels the app shows on the profile swatches (Light, Olive, Dark, ...).
_SKIN_ALIASES = {
    "fair": "fair", "very light": "fair", "type i": "fair",
    "light": "light", "type ii": "light",
    "medium": "medium", "wheatish": "medium", "wheat": "medium", "type iii": "medium",
    "tan": "tan", "olive": "tan", "type iv": "tan",
    "brown": "brown", "type v": "brown",
    "deep": "deep", "dark": "deep", "type vi": "deep",
}
# A typical swatch per bucket (the ITA buckets span real skin colours; these
# sit mid-bucket). Only hue and lightness are used.
_SKIN_HEX = {"fair": "#F1D3C2", "light": "#E3B597", "medium": "#C99A74", "tan": "#AF7B55",
             "brown": "#875A3B", "deep": "#553826"}
SKIN_HUE = {k: _hsvl(v)[0] for k, v in _SKIN_HEX.items()}
SKIN_L = {k: _hsvl(v)[3] for k, v in _SKIN_HEX.items()}

# Widely used stylist guidance, as named-colour lists per bucket. These only
# nudge the score; contrast and wash-out (below) do most of the work.
FLATTERING = {
    "fair": {"navy", "royal blue", "emerald", "ruby", "burgundy", "lavender", "pink", "rose pink",
             "teal", "plum", "sky blue", "mint", "black"},
    "light": {"navy", "royal blue", "emerald", "teal", "lavender", "pink", "rose pink", "burgundy",
              "plum", "sky blue", "purple", "coral"},
    "medium": {"olive", "teal", "maroon", "mustard", "rust", "white", "emerald", "burgundy",
               "coral", "denim", "off white", "navy"},
    "tan": {"olive", "teal", "maroon", "mustard", "rust", "white", "emerald", "gold", "coral",
            "turquoise", "cream", "burgundy"},
    "brown": {"gold", "emerald", "coral", "white", "royal blue", "burgundy", "cream", "magenta",
              "orange", "yellow", "turquoise", "red"},
    "deep": {"gold", "emerald", "coral", "white", "royal blue", "magenta", "yellow", "orange",
             "red", "turquoise", "cream", "lavender"},
}


# Colours stylists commonly say wash each skin tone out (too close to it in
# hue and depth, or too muddy against it).
WASH_OUT = {
    "fair": {"beige", "cream", "ivory", "tan", "khaki", "peach", "yellow"},
    "light": {"beige", "tan", "khaki", "peach", "cream"},
    "medium": {"beige", "khaki", "tan", "camel", "peach"},
    "tan": {"beige", "khaki", "tan", "camel", "peach"},
    "brown": {"brown", "tan", "camel", "khaki", "rust"},
    "deep": {"brown", "charcoal", "tan", "camel"},
}


# Undertone (21 Nov 2026, the skin tone analyzer): stylists' common guidance. Warm
# (golden/peachy) skin: earthy and golden colours; cool (pink/blue) skin: blue-based
# jewel tones and icy shades; neutral: both. Each side's typical "avoid" colours are
# the other side's signature shades near the face.
UNDERTONE_BEST = {
    "warm": {"mustard", "rust", "olive", "coral", "peach", "gold", "orange", "cream", "ivory", "camel",
             "turquoise", "teal", "red", "maroon", "copper", "bronze"},
    "cool": {"navy", "royal blue", "emerald", "ruby", "plum", "magenta", "lavender", "silver", "white",
             "burgundy", "purple", "pink", "rose pink", "teal", "charcoal"},
    "neutral": set(),
}
UNDERTONE_AVOID = {
    "warm": {"silver", "lavender", "mint", "sky blue", "grey", "gray", "plum", "purple", "magenta"},
    "cool": {"orange", "mustard", "rust", "camel", "gold", "peach", "khaki", "copper", "cream", "ivory",
             "coral", "olive"},
    "neutral": set(),
}
UNDERTONE_NUDGE = (0.15, 0.2)  # + for a best colour, - for an avoid colour


def undertone_key(undertone: str | None) -> str | None:
    u = (undertone or "").strip().lower()
    return u if u in UNDERTONE_BEST else None


def skin_bucket(skin_tone: str | None) -> str | None:
    """'Medium', 'Olive', 'Type IV', 'deep' ... -> one of the six buckets."""
    if not skin_tone:
        return None
    tone = skin_tone.lower().strip()
    if tone in _SKIN_ALIASES:
        return _SKIN_ALIASES[tone]
    for alias in sorted(_SKIN_ALIASES, key=len, reverse=True):
        if re.search(rf"\b{re.escape(alias)}\b", tone):
            return _SKIN_ALIASES[alias]
    return None


def extract_colors(product: dict) -> list[str]:
    """Named colours of a product: its colour list first, then any colour
    words in the title/tags (shops often only name it there). Unique, in order."""
    found: list[str] = []
    sources = [c for c in (product.get("colors") or []) if isinstance(c, str)]
    tags = product.get("tags") or []
    sources.append(product.get("title") or "")
    sources.append(" ".join(t for t in tags if isinstance(t, str)) if isinstance(tags, list) else str(tags))
    for text in sources:
        for name in _NAME_RE.findall(text.lower()):
            if name not in found:
                found.append(name)
    return found[:4]


def _hue_distance(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


@dataclass
class Harmony:
    score: float  # 0..1, 0.5 = neutral / not enough information
    known: bool  # False: no colour (or skin tone) to judge, score is the neutral 0.5
    reason: str = ""
    per_color: dict[str, float] = field(default_factory=dict)


def _skin_color_score(name: str, bucket: str, undertone: str | None = None) -> float:
    h, s, _, lightness = COLOR_HSV[name]
    contrast = abs(lightness - SKIN_L[bucket])  # 0..~90 L* units
    score = 0.45 + 0.25 * min(1.0, contrast / 45)
    # wash-out: a muted colour of the skin's own hue and depth blends into it
    if s < 0.6 and _hue_distance(h, SKIN_HUE[bucket]) <= 25 and contrast < 20:
        score -= 0.15
    tone = undertone_key(undertone)
    other = {"warm": "cool", "cool": "warm"}.get(tone or "")
    own_signature = bool(tone) and name in UNDERTONE_BEST[tone]
    other_signature = bool(other) and name in UNDERTONE_BEST[other] and not own_signature
    # a known undertone wins over the depth lists for the undertones' own colours: the fair /
    # light lists are cool-leaning (they called cream "wash-out" and royal blue "flattering"),
    # which told a warm, light-skinned user the opposite of her own advice (21 Nov 2026)
    if name in FLATTERING[bucket] and not other_signature:
        score += 0.25
    if name in WASH_OUT[bucket] and not own_signature:
        score -= 0.25
    if own_signature:
        score += UNDERTONE_NUDGE[0]
    if tone and name in UNDERTONE_AVOID[tone]:
        score -= UNDERTONE_NUDGE[1]
    return max(0.0, min(1.0, score))


def skin_harmony(colors: list[str], skin_tone: str | None, undertone: str | None = None) -> Harmony:
    """How well the colours suit the skin (depth bucket; the undertone, when known, nudges it)."""
    bucket = skin_bucket(skin_tone)
    named = [c for c in colors if c in COLOR_HSV]
    if not bucket or not named:
        return Harmony(0.5, False)
    per = {c: _skin_color_score(c, bucket, undertone) for c in named}
    # the main (first-listed) colour counts double: it is most of the garment
    weights = [2.0] + [1.0] * (len(named) - 1)
    score = sum(w * per[c] for w, c in zip(weights, named)) / sum(weights)
    best = max(per, key=per.get)
    worst = min(per, key=per.get)
    label = (skin_tone or bucket).strip()
    if score >= 0.70:
        reason = f"{best} flatters your {label} skin tone"
    elif score <= 0.40:
        reason = f"{worst} is close to your {label} skin tone and may wash you out"
    else:
        reason = f"{named[0]} is a safe choice for your {label} skin tone"
    return Harmony(round(score, 3), True, reason, {k: round(v, 3) for k, v in per.items()})


def _pair_score(a: str, b: str) -> float:
    if a in NEUTRALS or b in NEUTRALS:
        return 0.85
    (ha, sa, _, _), (hb, sb, _, _) = COLOR_HSV[a], COLOR_HSV[b]
    d = _hue_distance(ha, hb)
    if d <= 30:
        return 0.90  # analogous / tonal
    if 150 <= d <= 210:
        return 0.85  # complementary
    if 105 <= d <= 135:
        return 0.70  # triadic
    if 40 <= d <= 100 and sa > 0.6 and sb > 0.6:
        return 0.35  # two loud colours that fight
    return 0.55


def outfit_harmony(colors: list[str]) -> Harmony:
    named = [c for c in colors if c in COLOR_HSV]
    if not named:
        return Harmony(0.5, False)
    if len(named) == 1:
        return Harmony(0.75, True, f"a single-colour {named[0]} look is easy to wear")
    pairs = [(a, b) for i, a in enumerate(named) for b in named[i + 1:]]
    scores = {(a, b): _pair_score(a, b) for a, b in pairs}
    score = sum(scores.values()) / len(scores)
    worst = min(scores, key=scores.get)
    if score >= 0.80:
        reason = f"{' and '.join(named[:2])} work well together"
    elif score <= 0.45:
        reason = f"{worst[0]} and {worst[1]} compete with each other"
    else:
        reason = f"{' and '.join(named[:2])} are a reasonable pairing"
    return Harmony(round(score, 3), True, reason)


def pairing_suggestions(colors: list[str], skin_tone: str | None, limit: int = 2) -> list[str]:
    """Colours to wear *with* this garment (a dupatta, shoes, a waistcoat):
    ones that pair well with its main colour and flatter the skin tone."""
    named = [c for c in colors if c in COLOR_HSV]
    bucket = skin_bucket(skin_tone)
    if not named:
        return []
    main = named[0]
    hm, _, _, lm = COLOR_HSV[main]

    def near_duplicate(c: str) -> bool:  # maroon + burgundy is not a pairing
        h, _, _, lightness = COLOR_HSV[c]
        return _hue_distance(h, hm) < 20 and abs(lightness - lm) < 15

    candidates = [c for c in COLOR_HSV
                  if c not in named and c != "gray" and not near_duplicate(c)
                  and not (bucket and c in WASH_OUT[bucket])]
    ranked = sorted(
        candidates,
        key=lambda c: (_pair_score(main, c) + (_skin_color_score(c, bucket) if bucket else 0.5), c),
        reverse=True,
    )
    return ranked[:limit]
