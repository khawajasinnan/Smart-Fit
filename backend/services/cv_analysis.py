"""Computer Vision body analysis service.

Uses MediaPipe Pose Landmarker (Tasks API, v1.0+) for 33-landmark body
detection, OpenCV for skin tone analysis, and rule-based classifiers for
body shape and size estimation.

Pipeline:
  1. Load image (from URL or base64)
  2. Run MediaPipe PoseLandmarker → 33 body landmarks
  3. Compute body proportions from landmarks
  4. Classify body shape (Apple / Pear / Hourglass / Rectangle / Inverted Triangle)
  5. Estimate clothing size (XS–XXL) — from landmarks, profile measurements, or BMI
  6. Analyze skin tone from face/neck region via OpenCV HSV analysis
  7. Return structured CvAnalysisResponse

References:
  - SRDS: SFR-019 (body shape), SFR-020 (size estimation), SFR-021 (processing indicator)
  - architecture.md: AI/ML — CV layer (MediaPipe + OpenCV)
"""

from __future__ import annotations

import base64
import logging
import math
import os
from dataclasses import dataclass
from pathlib import Path

import cv2
import httpx
import mediapipe as mp
import numpy as np

from models.cv_schemas import (
    BodyProportions,
    CvAnalysisRequest,
    CvAnalysisResponse,
    PoseLandmark,
    SkinToneResult,
)

logger = logging.getLogger("smartfit.cv")

# ──────────────────────────────────────────────────────────────────────────────
# MediaPipe Pose Landmarker setup (new Tasks API — mediapipe ≥ 1.0)
# ──────────────────────────────────────────────────────────────────────────────

_BaseOptions = mp.tasks.BaseOptions
_PoseLandmarker = mp.tasks.vision.PoseLandmarker
_PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
_VisionRunningMode = mp.tasks.vision.RunningMode

# Path to the downloaded .task model file
_MODEL_DIR = Path(__file__).resolve().parent.parent / "models" / "ml_models"
_POSE_MODEL_PATH = _MODEL_DIR / "pose_landmarker_heavy.task"

# Landmark name lookup (MediaPipe Pose has 33 landmarks)
_LANDMARK_NAMES: list[str] = [
    "nose",
    "left_eye_inner",
    "left_eye",
    "left_eye_outer",
    "right_eye_inner",
    "right_eye",
    "right_eye_outer",
    "left_ear",
    "right_ear",
    "mouth_left",
    "mouth_right",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_pinky",
    "right_pinky",
    "left_index",
    "right_index",
    "left_thumb",
    "right_thumb",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
    "left_heel",
    "right_heel",
    "left_foot_index",
    "right_foot_index",
]


@dataclass
class _LandmarkPoint:
    """Internal helper: a 2D + depth point from MediaPipe."""

    x: float  # normalised [0,1] → multiply by image width for pixel
    y: float  # normalised [0,1] → multiply by image height for pixel
    z: float  # depth (relative)
    visibility: float


# ──────────────────────────────────────────────────────────────────────────────
# IMAGE LOADING
# ──────────────────────────────────────────────────────────────────────────────


async def _load_image_from_url(url: str) -> np.ndarray:
    """Download an image and decode it into a BGR numpy array for OpenCV."""
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
    img_array = np.frombuffer(resp.content, dtype=np.uint8)
    img_bgr = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise ValueError("Failed to decode image from URL")
    return img_bgr


def _load_image_from_base64(b64_string: str) -> np.ndarray:
    """Decode a base64-encoded image into a BGR numpy array."""
    # Strip optional data-URI prefix  e.g. "data:image/jpeg;base64,..."
    if "," in b64_string:
        b64_string = b64_string.split(",", 1)[1]
    raw = base64.b64decode(b64_string)
    img_array = np.frombuffer(raw, dtype=np.uint8)
    img_bgr = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise ValueError("Failed to decode base64 image")
    return img_bgr


# ──────────────────────────────────────────────────────────────────────────────
# POSE ESTIMATION  (MediaPipe Tasks API)
# ──────────────────────────────────────────────────────────────────────────────


def _run_pose_estimation(
    img_bgr: np.ndarray,
) -> tuple[list[_LandmarkPoint], float]:
    """Run MediaPipe PoseLandmarker on a BGR image.

    Returns (landmarks_list, average_visibility).
    Uses the new Tasks API (mediapipe >= 1.0).
    """
    if not _POSE_MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Pose model not found at {_POSE_MODEL_PATH}. "
            "Download it from: https://storage.googleapis.com/mediapipe-models/"
            "pose_landmarker/pose_landmarker_heavy/float16/latest/"
            "pose_landmarker_heavy.task"
        )

    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    # Create a MediaPipe Image from the numpy array
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=img_rgb)

    options = _PoseLandmarkerOptions(
        base_options=_BaseOptions(model_asset_path=str(_POSE_MODEL_PATH)),
        running_mode=_VisionRunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
        output_segmentation_masks=False,
    )

    with _PoseLandmarker.create_from_options(options) as landmarker:
        result = landmarker.detect(mp_image)

    if not result.pose_landmarks or len(result.pose_landmarks) == 0:
        return [], 0.0

    # Take the first detected pose
    pose = result.pose_landmarks[0]

    points: list[_LandmarkPoint] = []
    total_vis = 0.0
    for lm in pose:
        # In the new API, visibility and presence are separate.
        # Use visibility if available, otherwise presence.
        vis = getattr(lm, "visibility", None)
        if vis is None:
            vis = getattr(lm, "presence", 0.5)
        points.append(_LandmarkPoint(x=lm.x, y=lm.y, z=lm.z, visibility=float(vis)))
        total_vis += float(vis)

    avg_confidence = total_vis / len(points) if points else 0.0
    return points, avg_confidence


def _dist_px(
    p1: _LandmarkPoint,
    p2: _LandmarkPoint,
    img_w: int,
    img_h: int,
) -> float:
    """Euclidean distance between two landmarks in pixel space."""
    dx = (p1.x - p2.x) * img_w
    dy = (p1.y - p2.y) * img_h
    return math.sqrt(dx * dx + dy * dy)


def _midpoint(p1: _LandmarkPoint, p2: _LandmarkPoint) -> _LandmarkPoint:
    """Midpoint between two landmarks."""
    return _LandmarkPoint(
        x=(p1.x + p2.x) / 2,
        y=(p1.y + p2.y) / 2,
        z=(p1.z + p2.z) / 2,
        visibility=min(p1.visibility, p2.visibility),
    )


# ──────────────────────────────────────────────────────────────────────────────
# BODY PROPORTIONS & GENDER ESTIMATION
# ──────────────────────────────────────────────────────────────────────────────

def _estimate_gender_from_pose(
    proportions: BodyProportions,
) -> tuple[str, float]:
    """Estimate gender from body proportions using shoulder-to-hip ratio.
    
    Males typically have shoulder/hip ratio > 1.1
    Females typically have shoulder/hip ratio < 1.0
    
    Returns (estimated_gender, confidence) where:
      - estimated_gender: "male", "female", or "uncertain"
      - confidence: 0.0 to 1.0
    """
    shr = proportions.shoulder_width_ratio
    whr = proportions.waist_hip_ratio
    
    if shr is None:
        return "uncertain", 0.0
    
    # Strong male indicators: broad shoulders relative to hips
    if shr > 1.20:
        confidence = min(0.95, 0.70 + (shr - 1.20) * 1.5)
        return "male", confidence
    
    # Strong female indicators: hips wider than or equal to shoulders
    if shr < 0.90:
        confidence = min(0.95, 0.70 + (0.90 - shr) * 1.5)
        return "female", confidence
    
    # Ambiguous zone (0.90 - 1.20): use WHR as tiebreaker
    if whr is not None:
        if whr < 0.78:  # lower WHR more common in females
            return "female", 0.60
        if whr > 0.90:  # higher WHR more common in males
            return "male", 0.60
    
    # In the overlap zone, lean towards the direction but low confidence
    if shr > 1.05:
        return "male", 0.50
    if shr < 0.95:
        return "female", 0.50
    
    return "uncertain", 0.30

def _compute_proportions(
    lms: list[_LandmarkPoint],
    img_w: int,
    img_h: int,
) -> BodyProportions:
    """Derive body proportion ratios from the 33 MediaPipe landmarks.

    Key landmark indices:
      11 = left_shoulder,  12 = right_shoulder
      23 = left_hip,       24 = right_hip
      25 = left_knee,      26 = right_knee
      27 = left_ankle,     28 = right_ankle
       0 = nose (top reference)
    """
    l_shoulder, r_shoulder = lms[11], lms[12]
    l_hip, r_hip = lms[23], lms[24]
    l_ankle, r_ankle = lms[27], lms[28]
    nose = lms[0]

    shoulder_width = _dist_px(l_shoulder, r_shoulder, img_w, img_h)
    hip_width = _dist_px(l_hip, r_hip, img_w, img_h)

    mid_shoulder = _midpoint(l_shoulder, r_shoulder)
    mid_hip = _midpoint(l_hip, r_hip)
    mid_ankle = _midpoint(l_ankle, r_ankle)

    torso_length = _dist_px(mid_shoulder, mid_hip, img_w, img_h)
    leg_length = _dist_px(mid_hip, mid_ankle, img_w, img_h)
    total_height = _dist_px(nose, mid_ankle, img_w, img_h)

    shoulder_width_ratio = shoulder_width / hip_width if hip_width > 0 else 1.0
    torso_ratio = torso_length / total_height if total_height > 0 else 0.0
    leg_ratio = leg_length / total_height if total_height > 0 else 0.0
    shoulder_hip_diff = shoulder_width - hip_width

    # Approximate waist-hip ratio from landmark geometry
    waist_hip_ratio = None
    if hip_width > 0:
        waist_width_est = shoulder_width * 0.4 + hip_width * 0.6
        waist_hip_ratio = round(waist_width_est / hip_width, 3)

    return BodyProportions(
        shoulder_width_ratio=round(shoulder_width_ratio, 3),
        torso_length_ratio=round(torso_ratio, 3),
        leg_length_ratio=round(leg_ratio, 3),
        waist_hip_ratio=waist_hip_ratio,
        shoulder_hip_diff=round(shoulder_hip_diff, 1),
    )


# ──────────────────────────────────────────────────────────────────────────────
# BODY SHAPE CLASSIFICATION
# ──────────────────────────────────────────────────────────────────────────────


def _classify_body_shape(
    proportions: BodyProportions,
    gender: str | None = None,
) -> tuple[str, float]:
    """Classify body shape from proportions. Returns (shape_name, confidence).

    Rules (tuned for Pakistani body types):
      - Shoulder/hip ratio > 1.15 → Inverted Triangle
      - Shoulder/hip ratio < 0.85 → Pear
      - WHR < 0.78 (female) or < 0.88 (male) → Hourglass
      - WHR > 0.90 → Apple
      - Otherwise → Rectangle
    """
    shr = proportions.shoulder_width_ratio or 1.0
    whr = proportions.waist_hip_ratio or 0.82
    g = (gender or "").lower()

    if shr > 1.15:
        return "Inverted Triangle", min(0.95, 0.6 + (shr - 1.15) * 2)
    if shr < 0.85:
        return "Pear", min(0.95, 0.6 + (0.85 - shr) * 2)

    hourglass_threshold = 0.78 if g == "female" else 0.88
    if whr < hourglass_threshold and 0.90 <= shr <= 1.10:
        return "Hourglass", min(0.90, 0.6 + (hourglass_threshold - whr) * 3)

    if whr > 0.90:
        return "Apple", min(0.85, 0.5 + (whr - 0.90) * 3)

    return "Rectangle", 0.65


# ──────────────────────────────────────────────────────────────────────────────
# SIZE ESTIMATION
# ──────────────────────────────────────────────────────────────────────────────

# Pakistani ready-to-wear size charts (consolidated from major brands)
_SIZE_CHART_MALE = {
    "XS": {"chest": (84, 88), "waist": (70, 74)},
    "S": {"chest": (88, 93), "waist": (74, 79)},
    "M": {"chest": (93, 98), "waist": (79, 84)},
    "L": {"chest": (98, 104), "waist": (84, 90)},
    "XL": {"chest": (104, 110), "waist": (90, 96)},
    "XXL": {"chest": (110, 118), "waist": (96, 104)},
}

_SIZE_CHART_FEMALE = {
    "XS": {"chest": (76, 82), "waist": (60, 64), "hip": (84, 88)},
    "S": {"chest": (82, 87), "waist": (64, 69), "hip": (88, 93)},
    "M": {"chest": (87, 92), "waist": (69, 74), "hip": (93, 98)},
    "L": {"chest": (92, 98), "waist": (74, 80), "hip": (98, 104)},
    "XL": {"chest": (98, 106), "waist": (80, 88), "hip": (104, 112)},
    "XXL": {"chest": (106, 114), "waist": (88, 96), "hip": (112, 120)},
}


def _estimate_measurements_from_pose(
    lms: list[_LandmarkPoint],
    img_w: int,
    img_h: int,
    known_height_cm: float | None,
) -> dict[str, float | None]:
    """Estimate real-world measurements from pose landmarks.

    If known_height_cm is provided, we calibrate pixel-to-cm.
    Otherwise, we use statistical averages based on the Pakistani population.
    """
    l_shoulder, r_shoulder = lms[11], lms[12]
    l_hip, r_hip = lms[23], lms[24]
    nose = lms[0]
    mid_ankle = _midpoint(lms[27], lms[28])

    shoulder_px = _dist_px(l_shoulder, r_shoulder, img_w, img_h)
    hip_px = _dist_px(l_hip, r_hip, img_w, img_h)
    full_height_px = _dist_px(nose, mid_ankle, img_w, img_h)

    # Add ~8% for top of head above nose
    full_height_px *= 1.08

    if full_height_px < 50:
        return {"chest_cm": None, "waist_cm": None, "hip_cm": None, "shoulder_cm": None}

    if known_height_cm and known_height_cm > 100:
        px_per_cm = full_height_px / known_height_cm
    else:
        # Fallback: average Pakistani height
        avg_height = 163.0
        px_per_cm = full_height_px / avg_height

    shoulder_cm = shoulder_px / px_per_cm
    hip_cm = hip_px / px_per_cm

    # Chest circumference ≈ shoulder width × π × 0.55 (frontal-view factor)
    chest_cm = shoulder_cm * math.pi * 0.55
    # Hip circumference ≈ hip width × π × 0.55
    hip_circ_cm = hip_cm * math.pi * 0.55
    # Waist ≈ weighted average between chest and hip
    waist_circ_cm = chest_cm * 0.4 + hip_circ_cm * 0.6

    return {
        "shoulder_cm": round(shoulder_cm, 1),
        "chest_cm": round(chest_cm, 1),
        "waist_cm": round(waist_circ_cm, 1),
        "hip_cm": round(hip_circ_cm, 1),
    }


def _estimate_size(
    measurements: dict[str, float | None],
    gender: str | None,
    profile_chest: float | None = None,
    profile_waist: float | None = None,
    profile_hip: float | None = None,
    height_cm: float | None = None,
    weight_kg: float | None = None,
) -> tuple[str, str]:
    """Estimate clothing size. Returns (size_label, source).

    Priority: 1. Profile measurements  2. Pose-derived  3. BMI fallback
    """
    chest = profile_chest or measurements.get("chest_cm")
    waist = profile_waist or measurements.get("waist_cm")
    hip = profile_hip or measurements.get("hip_cm")
    source = "profile_measurements" if profile_chest else "pose_landmarks"

    g = (gender or "").lower()
    chart = _SIZE_CHART_FEMALE if g == "female" else _SIZE_CHART_MALE

    if chest:
        for size_label, ranges in chart.items():
            low, high = ranges["chest"]
            if low <= chest <= high:
                return size_label, source
        first_size = list(chart.keys())[0]
        last_size = list(chart.keys())[-1]
        if chest < chart[first_size]["chest"][0]:
            return first_size, source
        return last_size, source

    # BMI fallback
    if height_cm and weight_kg and height_cm > 0:
        bmi = weight_kg / ((height_cm / 100) ** 2)
        if bmi < 18.5:
            return "XS", "bmi_fallback"
        if bmi < 22:
            return "S", "bmi_fallback"
        if bmi < 25:
            return "M", "bmi_fallback"
        if bmi < 28:
            return "L", "bmi_fallback"
        if bmi < 32:
            return "XL", "bmi_fallback"
        return "XXL", "bmi_fallback"

    return "M", "default_fallback"


# ──────────────────────────────────────────────────────────────────────────────
# SKIN TONE ANALYSIS
# ──────────────────────────────────────────────────────────────────────────────

_FITZPATRICK_MAP = [
    # (min_value, max_value, min_sat, max_sat, type, label)
    (180, 255, 20, 80, "Type I", "Very Fair"),
    (160, 200, 30, 100, "Type II", "Fair"),
    (130, 180, 40, 130, "Type III", "Medium"),
    (100, 150, 50, 150, "Type IV", "Olive"),
    (60, 120, 50, 170, "Type V", "Brown"),
    (0, 80, 40, 200, "Type VI", "Deep"),
]


def _analyze_skin_tone(
    img_bgr: np.ndarray,
    lms: list[_LandmarkPoint],
    img_w: int,
    img_h: int,
) -> SkinToneResult:
    """Extract skin tone from the face/neck region using OpenCV HSV analysis.

    Strategy:
      1. Use MediaPipe nose (0), left_ear (7), right_ear (8) landmarks
         to define a face bounding region
      2. Sample the cheek/face region
      3. Convert to HSV, compute median H/S/V in the skin region
      4. Map to Fitzpatrick type
    """
    nose = lms[0]
    l_ear = lms[7]
    r_ear = lms[8]

    face_pts_x = [nose.x, l_ear.x, r_ear.x]
    face_pts_y = [nose.y, l_ear.y, r_ear.y]

    x_min = int(min(face_pts_x) * img_w) - 10
    x_max = int(max(face_pts_x) * img_w) + 10
    y_min = int(min(face_pts_y) * img_h) - 20
    y_max = int(max(face_pts_y) * img_h) + 30

    x_min = max(0, x_min)
    x_max = min(img_w, x_max)
    y_min = max(0, y_min)
    y_max = min(img_h, y_max)

    if x_max - x_min < 10 or y_max - y_min < 10:
        return SkinToneResult()

    face_roi = img_bgr[y_min:y_max, x_min:x_max]
    hsv = cv2.cvtColor(face_roi, cv2.COLOR_BGR2HSV)

    # Skin color mask (HSV range for typical skin tones)
    lower_skin = np.array([0, 20, 50], dtype=np.uint8)
    upper_skin = np.array([35, 255, 255], dtype=np.uint8)
    mask = cv2.inRange(hsv, lower_skin, upper_skin)

    # Also include reddish wrap-around hue range
    lower_skin2 = np.array([170, 20, 50], dtype=np.uint8)
    upper_skin2 = np.array([180, 255, 255], dtype=np.uint8)
    mask2 = cv2.inRange(hsv, lower_skin2, upper_skin2)
    mask = cv2.bitwise_or(mask, mask2)

    skin_pixels = hsv[mask > 0]
    if len(skin_pixels) < 30:
        skin_pixels = hsv.reshape(-1, 3)

    if len(skin_pixels) == 0:
        return SkinToneResult()

    median_h = float(np.median(skin_pixels[:, 0]))
    median_s = float(np.median(skin_pixels[:, 1]))
    median_v = float(np.median(skin_pixels[:, 2]))

    # Get dominant BGR color for hex
    bgr_skin = face_roi[mask > 0] if mask.sum() > 0 else face_roi.reshape(-1, 3)
    median_bgr = np.median(bgr_skin, axis=0).astype(int)
    b, g, r = int(median_bgr[0]), int(median_bgr[1]), int(median_bgr[2])
    hex_color = f"#{r:02X}{g:02X}{b:02X}"

    # Map to Fitzpatrick
    fitz_type = "Type III"
    tone_label = "Medium"
    for min_v, max_v, min_s, max_s, f_type, label in _FITZPATRICK_MAP:
        if min_v <= median_v <= max_v and min_s <= median_s <= max_s:
            fitz_type = f_type
            tone_label = label
            break

    return SkinToneResult(
        dominant_hex=hex_color,
        fitzpatrick_type=fitz_type,
        tone_label=tone_label,
        hsv_hue=round(median_h, 1),
        hsv_saturation=round(median_s, 1),
        hsv_value=round(median_v, 1),
    )


# ──────────────────────────────────────────────────────────────────────────────
# MAIN ANALYSIS ENTRY POINT
# ──────────────────────────────────────────────────────────────────────────────


async def analyze_body(request: CvAnalysisRequest) -> CvAnalysisResponse:
    """Full body detection and analysis pipeline.

    Returns a CvAnalysisResponse with body shape, size, proportions,
    33 pose landmarks, and skin tone analysis.
    """
    # ── Step 1: Load image ──
    try:
        if request.image_url:
            img_bgr = await _load_image_from_url(request.image_url)
        elif request.image_base64:
            img_bgr = _load_image_from_base64(request.image_base64)
        else:
            return CvAnalysisResponse(
                success=False,
                error="No image provided. Send either image_url or image_base64.",
            )
    except Exception as exc:
        logger.error("Failed to load image: %s", exc)
        return CvAnalysisResponse(
            success=False,
            error=f"Could not load image: {exc}",
        )

    img_h, img_w = img_bgr.shape[:2]
    logger.info("Image loaded: %dx%d", img_w, img_h)

    # ── Step 2: Pose estimation ──
    try:
        landmarks, pose_confidence = _run_pose_estimation(img_bgr)
    except FileNotFoundError as exc:
        logger.error("Model file missing: %s", exc)
        return CvAnalysisResponse(
            success=False,
            error=str(exc),
        )
    except Exception as exc:
        logger.error("Pose estimation error: %s", exc)
        landmarks, pose_confidence = [], 0.0

    if not landmarks or len(landmarks) < 33:
        logger.warning("Pose detection failed or incomplete (%d landmarks)", len(landmarks))
        size_label, size_source = _estimate_size(
            {},
            request.gender,
            request.chest_cm,
            request.waist_cm,
            request.hip_cm,
            request.height_cm,
            request.weight_kg,
        )
        return CvAnalysisResponse(
            success=True,
            error="Pose detection could not find a clear body in the image. "
                  "Try a full-body photo with good lighting, facing the camera.",
            estimated_size=size_label,
            estimated_size_source=size_source,
            image_width=img_w,
            image_height=img_h,
            pose_confidence=pose_confidence,
        )

    logger.info(
        "Pose detected with %.1f%% avg confidence across %d landmarks",
        pose_confidence * 100,
        len(landmarks),
    )

    # ── Step 3: Compute proportions ──
    proportions = _compute_proportions(landmarks, img_w, img_h)
    
    # ── Estimate gender from pose ──
    estimated_gender, gender_confidence = _estimate_gender_from_pose(proportions)

    # ── Step 4: Classify body shape ──
    body_shape, shape_confidence = _classify_body_shape(proportions, request.gender)

    # ── Step 5: Estimate measurements & size ──
    pose_measurements = _estimate_measurements_from_pose(
        landmarks, img_w, img_h, request.height_cm
    )
    size_label, size_source = _estimate_size(
        pose_measurements,
        request.gender,
        request.chest_cm,
        request.waist_cm,
        request.hip_cm,
        request.height_cm,
        request.weight_kg,
    )

    # ── Step 6: Skin tone analysis ──
    skin_tone = _analyze_skin_tone(img_bgr, landmarks, img_w, img_h)

    # ── Step 7: Build landmark list for response ──
    pose_lm_list = [
        PoseLandmark(
            name=_LANDMARK_NAMES[i] if i < len(_LANDMARK_NAMES) else f"landmark_{i}",
            x=round(lm.x, 5),
            y=round(lm.y, 5),
            z=round(lm.z, 5),
            visibility=round(lm.visibility, 4),
        )
        for i, lm in enumerate(landmarks)
    ]

    logger.info(
        "Analysis complete: shape=%s (%.0f%%), size=%s (%s), skin=%s",
        body_shape,
        shape_confidence * 100,
        size_label,
        size_source,
        skin_tone.tone_label,
    )

    return CvAnalysisResponse(
        success=True,
        body_shape=body_shape,
        body_shape_confidence=round(shape_confidence, 3),
        estimated_size=size_label,
        estimated_size_source=size_source,
        estimated_gender=estimated_gender,
        gender_confidence=gender_confidence,
        estimated_chest_cm=pose_measurements.get("chest_cm"),
        estimated_waist_cm=pose_measurements.get("waist_cm"),
        estimated_hip_cm=pose_measurements.get("hip_cm"),
        estimated_shoulder_width_cm=pose_measurements.get("shoulder_cm"),
        proportions=proportions,
        pose_landmarks=pose_lm_list,
        pose_confidence=round(pose_confidence, 4),
        skin_tone=skin_tone,
        image_width=img_w,
        image_height=img_h,
    )
