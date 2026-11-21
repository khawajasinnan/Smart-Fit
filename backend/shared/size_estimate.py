"""The user's standard clothing size (XS..4XL) from measurements (SFR-020), and
how Pakistani stores write sizes.

Shared by the CV service (body scan), the try-on service (SFR-025: is the
product available in the user's size?) and, since 21 Nov 2026, the
recommendations ("Your size" on every product card). Moved here from
services/cv_analysis/body_classifier.py on 20 Nov 2026 so all use one table.

21 Nov 2026 (the user's report: a man with XL/XXL measurements was shown
small-size products): the tables go up to 4XL (they stopped at XXL, so every
bigger body was called XXL), and the size follows the LARGEST of the body's
chest, waist and hip sizes ("go by your larger measurement"), not chest alone.
"""

from __future__ import annotations

import re

# Body measurements (cm, circumference) per size: international standard charts
# (the same ranges Pakistani stores' body charts use); 3XL/4XL continue the steps.
SIZE_CHART_MALE = {
    "XS": {"chest": (84, 88), "waist": (70, 74)},
    "S": {"chest": (88, 93), "waist": (74, 79)},
    "M": {"chest": (93, 98), "waist": (79, 84)},
    "L": {"chest": (98, 104), "waist": (84, 90)},
    "XL": {"chest": (104, 110), "waist": (90, 96)},
    "XXL": {"chest": (110, 118), "waist": (96, 104)},
    "3XL": {"chest": (118, 126), "waist": (104, 112)},
    "4XL": {"chest": (126, 134), "waist": (112, 120)},
}

SIZE_CHART_FEMALE = {
    "XS": {"chest": (76, 82), "waist": (60, 64), "hip": (84, 88)},
    "S": {"chest": (82, 87), "waist": (64, 69), "hip": (88, 93)},
    "M": {"chest": (87, 92), "waist": (69, 74), "hip": (93, 98)},
    "L": {"chest": (92, 98), "waist": (74, 80), "hip": (98, 104)},
    "XL": {"chest": (98, 106), "waist": (80, 88), "hip": (104, 112)},
    "XXL": {"chest": (106, 114), "waist": (88, 96), "hip": (112, 120)},
    "3XL": {"chest": (114, 122), "waist": (96, 104), "hip": (120, 128)},
    "4XL": {"chest": (122, 130), "waist": (104, 112), "hip": (128, 136)},
}

LETTER_ORDER = ("XXS", "XS", "S", "M", "L", "XL", "XXL", "3XL", "4XL")


def _chart(gender: str | None) -> dict:
    return SIZE_CHART_FEMALE if (gender or "").lower() == "female" else SIZE_CHART_MALE


def _size_for(chart: dict, part: str, value: float) -> str:
    """The chart size whose range holds this measurement (the smallest / largest
    size when it is below / above every range)."""
    for label, ranges in chart.items():
        low, high = ranges[part]
        if low <= value <= high:
            return label
    first, last = next(iter(chart)), list(chart)[-1]
    return first if value < chart[first][part][0] else last


def estimate_size(
    measurements: dict[str, float | None],
    gender: str | None,
    profile_chest: float | None = None,
    height_cm: float | None = None,
    weight_kg: float | None = None,
    profile_waist: float | None = None,
    profile_hip: float | None = None,
) -> tuple[str, str]:
    """Clothing size -> (label, source). Priority: profile measurements (the
    largest size of chest, waist and, for women, hip), pose chest, BMI."""
    chart = _chart(gender)
    chest = profile_chest or measurements.get("chest_cm")
    parts = [("chest", chest), ("waist", profile_waist)]
    if "hip" in next(iter(chart.values())):
        parts.append(("hip", profile_hip))
    sizes = [_size_for(chart, part, float(v)) for part, v in parts if v]
    if sizes:
        source = "profile_measurements" if (profile_chest or profile_waist or profile_hip) else "pose_landmarks"
        return max(sizes, key=LETTER_ORDER.index), source

    if height_cm and weight_kg and height_cm > 0:
        bmi = weight_kg / ((height_cm / 100) ** 2)
        for limit, label in ((18.5, "XS"), (22, "S"), (25, "M"), (28, "L"), (32, "XL"), (36, "XXL")):
            if bmi < limit:
                return label, "bmi_fallback"
        return "3XL", "bmi_fallback"

    return "M", "default_fallback"


# The same size written two ways on Pakistani stores.
_SAME = {"2XL": "XXL", "XXXL": "3XL", "XXXXL": "4XL"}


def same_size(size: str) -> str:
    s = size.strip().upper()
    return _SAME.get(s, s)


# ── Reading a store's size label (213 different spellings in the catalog) ──────
_WORDS = (  # longest first
    (re.compile(r"\b(?:EXTRA[ -]?SMALL|X[ -]?SMALL)\b"), " XS "),
    (re.compile(r"\b(?:XX[ -]?LARGE|EXTRA[ -]?EXTRA[ -]?LARGE)\b"), " XXL "),
    (re.compile(r"\b(?:EXTRA[ -]?LARGE|X[ -]?LARGE)\b"), " XL "),
    (re.compile(r"\bSMALL\b"), " S "),
    (re.compile(r"\bMEDIUM\b"), " M "),
    (re.compile(r"\bLARGE\b"), " L "),
)
_TOKENS = {
    "XXS": ("XXS",), "XS": ("XS",), "S": ("S",), "M": ("M",), "L": ("L",), "XL": ("XL",),
    "XXL": ("XXL",), "2XL": ("XXL",), "3XL": ("3XL",), "XXXL": ("3XL",), "4XL": ("4XL",), "XXXXL": ("4XL",),
    "SM": ("S", "M"), "ML": ("M", "L"),  # "S-M" written without the dash
}
ONE_SIZE_RE = re.compile(r"\b(?:FREE ?SIZE|ONE ?SIZE|F\.S|OS)\b")
CUSTOM_RE = re.compile(r"\b(?:CUSTOM\w*|MAKE TO ORDER|MADE TO (?:ORDER|MEASURE))\b")
FABRIC_RE = re.compile(r"\b(?:UNSTITCH\w*|METERS?|METRES?)\b")


def letter_sizes(label: str) -> set[str]:
    """The letter sizes a store's label covers, in LETTER_ORDER names:
    "L (14)" -> {L}, "10 (S)" -> {S}, "XL RGF" -> {XL}, "S-M" / "SM" / "Small Medium" -> {S, M},
    "X-Large" -> {XL}, "2XL" / "3 XL" -> {XXL} / {3XL}. Empty for other size systems
    (collar "15.5", inches '40"', waist "W 34 / L 31", "Unstitched"): those are never converted."""
    text = (label or "").upper()
    if re.search(r"\bW\s*\d", text) or ONE_SIZE_RE.search(text):  # jeans "W 34 / L 31": L is the leg length
        return set()
    text = re.sub(r"(\d)\s+XL\b", r"\1XL", text)  # "3 XL"
    for rx, repl in _WORDS:
        text = rx.sub(repl, text)
    out: set[str] = set()
    for token in re.split(r"[^A-Z0-9]+", text):
        out.update(_TOKENS.get(token, ()))
    return out


def size_kind(label: str) -> str:
    """"one" (free / one size), "custom" (made to measure), "fabric" (unstitched), "letter" or "other"."""
    text = (label or "").upper()
    if ONE_SIZE_RE.search(text):
        return "one"
    if CUSTOM_RE.search(text):
        return "custom"
    if FABRIC_RE.search(text):
        return "fabric"
    return "letter" if letter_sizes(label) else "other"
