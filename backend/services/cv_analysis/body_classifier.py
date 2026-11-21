"""Body proportions, gender hint, body shape and clothing size (SFR-019, SFR-020).

Pure Python on top of the pose landmarks — no OpenCV / MediaPipe imports, so it
is fully unit-testable.

Body shape needs a real waist measurement. A front photo's pose landmarks have
no waist point, so:
  * with the user's chest / waist / hip measurements (profile) -> full
    5-shape classification from real ratios ("measurements")
  * photo only -> shoulder-to-hip ratio only: Inverted Triangle / Pear /
    Rectangle ("pose"). Apple and Hourglass can't be told apart from a
    photo without a waist, so they are never guessed.
(The previous version invented a waist as 0.4*shoulder + 0.6*hip, which made
Hourglass and Rectangle impossible and biased the gender guess to "male".)
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from shared.schemas.cv import BodyProportions
from shared.size_estimate import SIZE_CHART_FEMALE, SIZE_CHART_MALE, estimate_size  # noqa: F401 (re-exported)


@dataclass
class LandmarkPoint:
    """A 2D + depth point from MediaPipe (x, y normalised to [0, 1])."""

    x: float
    y: float
    z: float
    visibility: float


def dist_px(p1: LandmarkPoint, p2: LandmarkPoint, img_w: int, img_h: int) -> float:
    """Euclidean distance between two landmarks in pixel space."""
    dx = (p1.x - p2.x) * img_w
    dy = (p1.y - p2.y) * img_h
    return math.sqrt(dx * dx + dy * dy)


def midpoint(p1: LandmarkPoint, p2: LandmarkPoint) -> LandmarkPoint:
    return LandmarkPoint(
        x=(p1.x + p2.x) / 2,
        y=(p1.y + p2.y) / 2,
        z=(p1.z + p2.z) / 2,
        visibility=min(p1.visibility, p2.visibility),
    )


# ──────────────────────────────────────────────────────────────────────────────
# PROPORTIONS & GENDER HINT
# ──────────────────────────────────────────────────────────────────────────────


def compute_proportions(
    lms: list[LandmarkPoint],
    img_w: int,
    img_h: int,
    waist_cm: float | None = None,
    hip_cm: float | None = None,
) -> BodyProportions:
    """Derive ratios from the 33 MediaPipe landmarks.

    Key indices: 0 nose, 11/12 shoulders, 23/24 hips, 27/28 ankles.
    waist_hip_ratio is only filled from *real* measurements when provided.
    """
    l_shoulder, r_shoulder = lms[11], lms[12]
    l_hip, r_hip = lms[23], lms[24]
    nose = lms[0]
    mid_shoulder = midpoint(l_shoulder, r_shoulder)
    mid_hip = midpoint(l_hip, r_hip)
    mid_ankle = midpoint(lms[27], lms[28])

    shoulder_width = dist_px(l_shoulder, r_shoulder, img_w, img_h)
    hip_width = dist_px(l_hip, r_hip, img_w, img_h)
    torso_length = dist_px(mid_shoulder, mid_hip, img_w, img_h)
    leg_length = dist_px(mid_hip, mid_ankle, img_w, img_h)
    total_height = dist_px(nose, mid_ankle, img_w, img_h)

    waist_hip_ratio = None
    if waist_cm and hip_cm and hip_cm > 0:
        waist_hip_ratio = round(waist_cm / hip_cm, 3)

    return BodyProportions(
        shoulder_width_ratio=round(shoulder_width / hip_width if hip_width > 0 else 1.0, 3),
        torso_length_ratio=round(torso_length / total_height if total_height > 0 else 0.0, 3),
        leg_length_ratio=round(leg_length / total_height if total_height > 0 else 0.0, 3),
        waist_hip_ratio=waist_hip_ratio,
        shoulder_hip_diff=round(shoulder_width - hip_width, 1),
    )


def estimate_gender_from_pose(proportions: BodyProportions) -> tuple[str, float]:
    """Gender hint from the photo. Disabled (always "uncertain") until calibrated.

    The previous cut-offs (male if shoulder/hip > 1.20) were applied to the raw
    landmark ratio, which is about 1.67 for women (VITON-HD, n=400), so every
    woman was reported "male" with 0.95 confidence. A reliable cut-off needs a
    male baseline measured the same way; until MALE_SHOULDER_HIP_BASELINE is
    calibrated on real photos this returns "uncertain", so the app never shows
    a false "photo and gender don't match" warning.
    """
    if MALE_SHOULDER_HIP_BASELINE is None or proportions.shoulder_width_ratio is None:
        return "uncertain", 0.0
    shr = proportions.shoulder_width_ratio
    split = (FEMALE_SHOULDER_HIP_BASELINE + MALE_SHOULDER_HIP_BASELINE) / 2
    gap = abs(shr - split) / split
    if gap < 0.03:
        return "uncertain", 0.3
    return ("male" if shr > split else "female"), round(min(0.9, 0.5 + gap * 4), 2)


# ──────────────────────────────────────────────────────────────────────────────
# BODY SHAPE
# ──────────────────────────────────────────────────────────────────────────────


# Spec §6.2 body types (API values).
BODY_TYPES = ("hourglass", "inverted_triangle", "triangle", "rectangle", "oval")

# The labels the mobile app already stores and shows.
APP_BODY_SHAPE_LABELS = {
    "hourglass": "Hourglass",
    "inverted_triangle": "Inverted Triangle",
    "triangle": "Pear",
    "rectangle": "Rectangle",
    "oval": "Apple",
}

# ── Tunable thresholds (spec §6.2: named constants, not magic numbers) ──────
# The spec's "≈": two values within this fraction of each other.
BALANCE_TOLERANCE = 0.05
# Spec: an hourglass needs a defined waist, waist-to-hip ratio below this.
HOURGLASS_MAX_WAIST_HIP_RATIO = 0.75

# Photo only: MediaPipe's hip landmarks are the hip *joints*, much narrower
# than the visible hip line, so the raw shoulder/hip landmark ratio is far
# above 1 for everyone. It is compared with a population baseline instead of
# 1.0. Measured on VITON-HD test images (n=400, all women, front-facing):
# median 1.674, sd 0.107, 5th-95th percentile 1.498-1.841.
FEMALE_SHOULDER_HIP_BASELINE = 1.674
# Not measured yet: VITON-HD has no men. Needs about 20 front-facing male
# photos. Until then men are compared with the female baseline and the
# result is marked low-confidence.
MALE_SHOULDER_HIP_BASELINE: float | None = None


def _within(a: float, b: float, tolerance: float = BALANCE_TOLERANCE) -> bool:
    return abs(a - b) / max(a, b) <= tolerance


def classify_from_measurements(chest: float, waist: float, hip: float) -> tuple[str, float]:
    """Five body types from chest/bust, waist and hip circumferences (cm).

    The spec §6.2 rules, in order, with two documented deviations:
      * oval is checked first and means the waist is the widest measurement.
        The spec's "otherwise -> oval" would call an ordinary balanced figure
        with a modest waist (e.g. 100/90/98) oval;
      * anything matching none of the rules falls back to rectangle.
    """
    balanced = _within(chest, hip) and _within(waist, hip) and _within(waist, chest)
    if waist >= chest and waist >= hip and not balanced:
        return "oval", 0.75
    if _within(chest, hip) and waist / hip < HOURGLASS_MAX_WAIST_HIP_RATIO:
        return "hourglass", 0.8
    if chest > hip * (1 + BALANCE_TOLERANCE):
        return "inverted_triangle", 0.75
    if hip > chest * (1 + BALANCE_TOLERANCE):
        return "triangle", 0.75
    if balanced:
        return "rectangle", 0.75
    return "rectangle", 0.55


def classify_from_pose(shoulder_hip_ratio: float, gender: str | None) -> tuple[str, float]:
    """Photo-only fallback. Without a waist only three types can be told
    apart; hourglass and oval need the profile's real measurements."""
    male = (gender or "").lower() == "male"
    calibrated = not male or MALE_SHOULDER_HIP_BASELINE is not None
    baseline = MALE_SHOULDER_HIP_BASELINE if (male and MALE_SHOULDER_HIP_BASELINE) else FEMALE_SHOULDER_HIP_BASELINE
    relative = shoulder_hip_ratio / baseline
    if relative > 1 + BALANCE_TOLERANCE:
        shape, conf = "inverted_triangle", min(0.85, 0.55 + (relative - 1 - BALANCE_TOLERANCE) * 3)
    elif relative < 1 - BALANCE_TOLERANCE:
        shape, conf = "triangle", min(0.85, 0.55 + (1 - BALANCE_TOLERANCE - relative) * 3)
    else:
        shape, conf = "rectangle", 0.45
    if not calibrated:
        conf = min(conf, 0.35)
    return shape, round(conf, 2)


def classify_body_shape(
    proportions: BodyProportions,
    gender: str | None,
    bust_cm: float | None = None,
    waist_cm: float | None = None,
    hip_cm: float | None = None,
) -> tuple[str, float, str]:
    """(spec body type, confidence, source); source is "measurements" or "pose"."""
    if bust_cm and waist_cm and hip_cm and hip_cm > 0:
        shape, confidence = classify_from_measurements(bust_cm, waist_cm, hip_cm)
        return shape, confidence, "measurements"
    ratio = proportions.shoulder_width_ratio or FEMALE_SHOULDER_HIP_BASELINE
    shape, confidence = classify_from_pose(ratio, gender)
    return shape, confidence, "pose"


# ──────────────────────────────────────────────────────────────────────────────
# MEASUREMENTS & SIZE
# ──────────────────────────────────────────────────────────────────────────────

# Nose-to-ankle is about 93% of standing height; this adds the top of the head.
HEAD_TOP_FACTOR = 1.08

# Pakistani ready-to-wear size charts (consolidated from major brands)
def estimate_measurements_from_pose(
    lms: list[LandmarkPoint],
    img_w: int,
    img_h: int,
    known_height_cm: float | None,
) -> dict[str, float | None]:
    """Rough real-world measurements from the landmarks.

    Calibrated with the user's height when known, else the average Pakistani
    height. The waist here is an *estimate* for size lookup only — it is never
    used for body-shape classification.
    """
    shoulder_px = dist_px(lms[11], lms[12], img_w, img_h)
    hip_px = dist_px(lms[23], lms[24], img_w, img_h)
    full_height_px = dist_px(lms[0], midpoint(lms[27], lms[28]), img_w, img_h) * HEAD_TOP_FACTOR

    if full_height_px < 50:
        return {"chest_cm": None, "waist_cm": None, "hip_cm": None, "shoulder_cm": None}

    height_ref = known_height_cm if known_height_cm and known_height_cm > 100 else 163.0
    px_per_cm = full_height_px / height_ref

    shoulder_cm = shoulder_px / px_per_cm
    hip_cm = hip_px / px_per_cm
    chest_circ = shoulder_cm * math.pi * 0.55  # frontal-view factor
    hip_circ = hip_cm * math.pi * 0.55
    waist_circ = chest_circ * 0.4 + hip_circ * 0.6

    return {
        "shoulder_cm": round(shoulder_cm, 1),
        "chest_cm": round(chest_circ, 1),
        "waist_cm": round(waist_circ, 1),
        "hip_cm": round(hip_circ, 1),
    }


SPEC_SIZES = ("S", "M", "L", "XL")


def to_spec_size(label: str) -> str:
    """Clamp the detailed chart size (XS..XXL) to the spec's S/M/L/XL."""
    return {"XS": "S", "XXL": "XL"}.get(label, label if label in SPEC_SIZES else "M")


def body_measurements_cm(
    lms: list[LandmarkPoint], img_w: int, img_h: int, height_cm: float
) -> dict[str, float] | None:
    """Spec §6.2 measurements, scaled by the user's height.

    Distances between landmarks, not circumferences: shoulder_cm is the
    shoulder-joint span, hip_cm the hip-joint span (narrower than the visible
    hips), torso_cm shoulder midpoint to hip midpoint. Needs the whole body in
    frame (nose to ankles); returns None otherwise.
    """
    full_height_px = dist_px(lms[0], midpoint(lms[27], lms[28]), img_w, img_h) * HEAD_TOP_FACTOR
    if full_height_px < 50 or height_cm <= 0:
        return None
    px_per_cm = full_height_px / height_cm
    mid_shoulder = midpoint(lms[11], lms[12])
    mid_hip = midpoint(lms[23], lms[24])
    return {
        "shoulder_cm": round(dist_px(lms[11], lms[12], img_w, img_h) / px_per_cm, 1),
        "hip_cm": round(dist_px(lms[23], lms[24], img_w, img_h) / px_per_cm, 1),
        "torso_cm": round(dist_px(mid_shoulder, mid_hip, img_w, img_h) / px_per_cm, 1),
    }
