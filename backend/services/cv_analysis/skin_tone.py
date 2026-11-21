"""Skin tone from the face region (spec §6.2 step 6, SFR-012 suggestion).

1. Face box from MediaPipe face detection (face.py).
2. Sample the central 40% of the box (cheeks/nose bridge, away from hair,
   ears and background), keep skin-coloured pixels only (YCrCb skin range)
   and drop the darkest/brightest 10% (eye/brow shadows, highlights).
3. Median colour -> CIELAB -> Individual Typology Angle (ITA).
4. ITA -> one of 6 buckets using the published dermatology thresholds
   (Chardon et al. 1991; Del Bino et al. 2013).

Deviation from the spec's "HSV range lookup": the spec gives no thresholds,
and ITA is the standard, citable way to bucket skin colour into exactly six
groups. HSV values are still reported.

Limits: lighting changes the measured colour, so this is a suggestion — the
user picks their skin tone in the profile (SFR-012) and can override it.
"""

from __future__ import annotations

import math

import cv2
import numpy as np

from shared.schemas.cv import SkinToneResult
from services.cv_analysis.face import FaceBox

SKIN_TONES = ("fair", "light", "medium", "tan", "brown", "deep")

# ITA lower bounds (degrees) per bucket, lightest first. Chardon et al. 1991:
# very light > 55, light 41-55, intermediate 28-41, tan 10-28, brown -30-10,
# dark < -30.
ITA_THRESHOLDS = (
    (55.0, "fair"),
    (41.0, "light"),
    (28.0, "medium"),
    (10.0, "tan"),
    (-30.0, "brown"),
)

# How the app labels the same buckets (profile skin-tone swatches) and the
# matching Fitzpatrick types it shows.
APP_SKIN_LABELS = {
    "fair": "Fair",
    "light": "Light",
    "medium": "Medium",
    "tan": "Olive",
    "brown": "Brown",
    "deep": "Dark",
}
FITZPATRICK = {
    "fair": "Type I",
    "light": "Type II",
    "medium": "Type III",
    "tan": "Type IV",
    "brown": "Type V",
    "deep": "Type VI",
}

# Central part of the face box that is sampled (spec: central 40%).
CENTRAL_FRACTION = 0.40
# Pixels kept after trimming the darkest/brightest tails (shadows, highlights).
TRIM_FRACTION = 0.10
MIN_SKIN_PIXELS = 30
# YCrCb skin range (Chai & Ngan 1999), wide enough for all skin colours.
_CR_RANGE = (133, 173)
_CB_RANGE = (77, 127)


def ita_degrees(lab_l: float, lab_b: float) -> float:
    """ITA = atan((L* - 50) / b*) in degrees."""
    return math.degrees(math.atan2(lab_l - 50.0, lab_b))


def bucket_from_ita(ita: float) -> str:
    for lower_bound, label in ITA_THRESHOLDS:
        if ita > lower_bound:
            return label
    return "deep"


def face_skin_pixels(img_bgr: np.ndarray, face: FaceBox) -> np.ndarray:
    """BGR skin pixels (N, 3) from the central part of the face box."""
    margin_x = int(face.w * (1 - CENTRAL_FRACTION) / 2)
    margin_y = int(face.h * (1 - CENTRAL_FRACTION) / 2)
    roi = img_bgr[face.y + margin_y : face.y + face.h - margin_y, face.x + margin_x : face.x + face.w - margin_x]
    if roi.size == 0:
        return np.empty((0, 3), dtype=np.uint8)

    ycrcb = cv2.cvtColor(roi, cv2.COLOR_BGR2YCrCb)
    mask = (
        (ycrcb[..., 1] >= _CR_RANGE[0])
        & (ycrcb[..., 1] <= _CR_RANGE[1])
        & (ycrcb[..., 2] >= _CB_RANGE[0])
        & (ycrcb[..., 2] <= _CB_RANGE[1])
    )
    pixels = roi[mask]
    if len(pixels) < MIN_SKIN_PIXELS:
        return np.empty((0, 3), dtype=np.uint8)

    # Trim by brightness to drop shadows and specular highlights.
    luma = ycrcb[..., 0][mask]
    lo, hi = np.quantile(luma, [TRIM_FRACTION, 1 - TRIM_FRACTION])
    return pixels[(luma >= lo) & (luma <= hi)]


def analyze_skin_tone(img_bgr: np.ndarray, face: FaceBox) -> tuple[str, SkinToneResult] | None:
    """(spec bucket, app-facing result) or None when there aren't enough skin pixels."""
    pixels = face_skin_pixels(img_bgr, face)
    if len(pixels) < MIN_SKIN_PIXELS:
        return None

    median_bgr = np.median(pixels, axis=0).astype(np.float32).reshape(1, 1, 3)
    lab = cv2.cvtColor(median_bgr / 255.0, cv2.COLOR_BGR2Lab)[0, 0]  # L 0..100, b real units
    hsv = cv2.cvtColor(median_bgr.astype(np.uint8), cv2.COLOR_BGR2HSV)[0, 0]
    ita = ita_degrees(float(lab[0]), float(lab[2]))
    bucket = bucket_from_ita(ita)

    b, g, r = (int(c) for c in median_bgr[0, 0])
    return bucket, SkinToneResult(
        dominant_hex=f"#{r:02X}{g:02X}{b:02X}",
        fitzpatrick_type=FITZPATRICK[bucket],
        tone_label=APP_SKIN_LABELS[bucket],
        hsv_hue=round(float(hsv[0]), 1),
        hsv_saturation=round(float(hsv[1]), 1),
        hsv_value=round(float(hsv[2]), 1),
    )


# ── Skin tone analyzer (21 Nov 2026): depth on the Monk scale + undertone ─────────
# The user asked for a closer analysis with clothing advice. Depth: the 10-shade
# Monk Skin Tone scale (Ellis Monk with Google, open; reference swatches below) next
# to the app's six swatches. Undertone: the CIELAB hue angle h = atan2(b*, a*) of the
# skin, i.e. how yellow (warm) or red-pink (cool) it is, after a white balance from
# the photo's neutral pixels. Lighting changes it, and no study gives validated cut-offs, so: the
# thresholds come from a calibration on real faces (UNDERTONE_CUTS, see
# scripts/calibrate_undertone.py), the result says how sure it is, and the app
# confirms it with the two standard questions (vein colour, gold or silver).
MONK_HEX = ("#F6EDE4", "#F3E7DB", "#F7EAD0", "#EADABA", "#D7BD96",
            "#A07E56", "#825C43", "#604134", "#3A312A", "#292420")
# Hue-angle cut-offs (degrees) per depth: below the first -> cool, above the second -> warm,
# between -> neutral. The lower and upper thirds of 1,497 CelebAMask-HQ faces at that depth
# (deep: only 27), measured exactly as here (scripts/calibrate_undertone.py, 21 Nov 2026): the angle depends on
# depth (fair skin reads pinker), so one cut-off for all would mislabel whole groups.
UNDERTONE_CUTS = {
    "fair": (41.5, 54.3), "light": (48.7, 56.7), "medium": (50.3, 57.1),
    "tan": (50.4, 56.1), "brown": (46.4, 53.2), "deep": (35.2, 44.5),
}
# Few deep-skinned faces in the calibration set and a less stable angle at low chroma:
# there the answer is always marked "low" confidence (the app's questions decide).
LOW_CONFIDENCE_BUCKETS = {"deep"}
# This close to a cut-off, the answer is marked "low" confidence.
UNDERTONE_MARGIN = 2.0
LIT_BAND = (60, 80)  # brightness percentiles of the face skin that are measured
WB_GAIN_LIMITS = (0.8, 1.25)  # safety clip on the white-balance gains


def _lab_of_bgr(bgr: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(bgr.reshape(1, -1, 3).astype(np.float32) / 255.0, cv2.COLOR_BGR2Lab)[0]


_MONK_LAB = _lab_of_bgr(np.array([[int(h[5:7], 16), int(h[3:5], 16), int(h[1:3], 16)] for h in MONK_HEX], np.float32))


# White balance from the photo's NEUTRAL pixels only (white / grey walls, backgrounds):
# low saturation, neither black nor blown out, outside the face. Grey-world over the
# whole photo was tried first (21 Nov 2026) and failed on a fair woman in a red top: the
# red pulled the skin grey-green and she read as "Brown, Monk 7". Too few neutral pixels:
# no correction at all rather than a wrong one.
NEUTRAL_MAX_SATURATION = 40  # OpenCV HSV, 0..255 (beige is ~56; a grey wall under a warm lamp ~38)
NEUTRAL_VALUE_RANGE = (120, 248)  # bright surfaces (walls), not mid-grey clothes; not blown out
MIN_NEUTRAL_SHARE = 0.03


def neutral_gains(img_bgr: np.ndarray, face: FaceBox | None = None) -> np.ndarray | None:
    """Per-channel gains that make the photo's neutral pixels grey, or None without enough of them."""
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    mask = (hsv[..., 1] < NEUTRAL_MAX_SATURATION) & (hsv[..., 2] > NEUTRAL_VALUE_RANGE[0]) & (
        hsv[..., 2] < NEUTRAL_VALUE_RANGE[1])
    if face is not None:
        mask[face.y:face.y + face.h, face.x:face.x + face.w] = False
    if mask.mean() < MIN_NEUTRAL_SHARE:
        return None
    means = img_bgr[mask].astype(np.float64).mean(axis=0)
    return means.mean() / np.maximum(means, 1e-6)


def monk_level(lab: np.ndarray) -> int:
    """1..10: the nearest Monk swatch (CIE76) to a skin colour in Lab."""
    d = np.linalg.norm(_MONK_LAB - lab.reshape(1, 3), axis=1)
    return int(np.argmin(d)) + 1


def undertone_from_hue(hue: float, bucket: str = "medium") -> tuple[str, str]:
    """(warm | cool | neutral, high | low confidence) from the skin's hue angle and depth bucket."""
    cool_cut, warm_cut = UNDERTONE_CUTS.get(bucket, UNDERTONE_CUTS["medium"])
    if hue < cool_cut:
        tone, gap = "cool", cool_cut - hue
    elif hue > warm_cut:
        tone, gap = "warm", hue - warm_cut
    else:
        tone, gap = "neutral", min(hue - cool_cut, warm_cut - hue)
    return tone, "high" if gap >= UNDERTONE_MARGIN and bucket not in LOW_CONFIDENCE_BUCKETS else "low"


def analyze_skin_detail(img_bgr: np.ndarray, face: FaceBox) -> dict | None:
    """The analyzer's measurement, or None without enough skin pixels:
    {bucket, app_label, monk_level, measured_hex, hue_angle, ita, undertone,
     undertone_confidence, white_balanced}."""
    gains = neutral_gains(img_bgr, face)
    white_balanced = gains is not None  # a white / grey surface to correct the light by
    balanced = img_bgr if gains is None else np.clip(
        img_bgr.astype(np.float64) * np.clip(gains, *WB_GAIN_LIMITS), 0, 255).astype(np.uint8)
    pixels = face_skin_pixels(balanced, face)
    if len(pixels) < MIN_SKIN_PIXELS:
        return None
    # the LIT skin (60th-80th brightness percentile): the median includes the shading under
    # cheekbones and nose and read every face too deep (a fair woman as "Light, Monk 6",
    # wheatish Pakistani men as "Brown"); the brightest band over-lightens instead
    luma = cv2.cvtColor(pixels.reshape(1, -1, 3), cv2.COLOR_BGR2YCrCb)[0, :, 0]
    lo, hi = np.percentile(luma, LIT_BAND)
    lit = pixels[(luma >= lo) & (luma <= hi)]
    median_bgr = np.median(lit if len(lit) >= MIN_SKIN_PIXELS // 2 else pixels, axis=0).astype(np.float32)
    lab = _lab_of_bgr(median_bgr.reshape(1, 3))[0]
    ita = ita_degrees(float(lab[0]), float(lab[2]))
    bucket = bucket_from_ita(ita)
    hue = math.degrees(math.atan2(float(lab[2]), float(lab[1])))
    undertone, confidence = undertone_from_hue(hue, bucket)
    b, g, r = (int(c) for c in median_bgr)
    return {
        "bucket": bucket, "app_label": APP_SKIN_LABELS[bucket], "monk_level": monk_level(lab),
        "measured_hex": f"#{r:02X}{g:02X}{b:02X}", "hue_angle": round(hue, 1), "ita": round(ita, 1),
        "undertone": undertone, "undertone_confidence": confidence, "white_balanced": white_balanced,
    }
