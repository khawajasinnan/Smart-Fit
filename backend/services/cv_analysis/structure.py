"""Body and face structure from the landmark models: shoulders (MediaPipe +
HRNet), face shape (MediaPipe face mesh) and how closely the two pose
models agree. Pure functions on normalised points, so they are unit-tested
without the models.

Face-shape cut-offs are placed on the spread measured on 299 frontal VITON-HD
photos (length/cheek median 1.21, p90 1.33; jaw/cheek median 0.79; forehead/
cheek median 0.86). There are no labelled face shapes to calibrate against,
so the label is an estimate and the ratios are returned with it.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

from shared.schemas.cv import FaceStructure, ModelAgreement, ShoulderAnalysis
from services.cv_analysis.body_classifier import LandmarkPoint
from services.cv_analysis.hrnet import Keypoint

# ── Face mesh indices (MediaPipe 478-point topology) ────────────────────────
FACE_TOP, CHIN = 10, 152
CHEEK_L, CHEEK_R = 454, 234
FOREHEAD_L, FOREHEAD_R = 284, 54
JAW_L, JAW_R = 397, 172
NOSE_TIP = 1

FACE_CONTOURS: dict[str, list[int]] = {
    "face_oval": [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
                  152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10],
    "right_brow": [70, 63, 105, 66, 107, 55, 65, 52, 53, 46],
    "left_brow": [300, 293, 334, 296, 336, 285, 295, 282, 283, 276],
    "right_eye": [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246, 33],
    "left_eye": [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466, 263],
    "nose": [168, 6, 197, 195, 5, 4, 1],
    "nostrils": [98, 97, 2, 326, 327],
    "lips": [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185, 61],
    # the measurement lines the app highlights
    "face_length": [FACE_TOP, CHIN],
    "forehead_width": [FOREHEAD_R, FOREHEAD_L],
    "cheekbone_width": [CHEEK_R, CHEEK_L],
    "jaw_width": [JAW_R, JAW_L],
}

MAX_FACE_TURN = 0.25  # nose-to-cheek asymmetry above this: head turned, ratios unreliable

# ── Pose ────────────────────────────────────────────────────────────────────
MP_LEFT_SHOULDER, MP_RIGHT_SHOULDER = 11, 12
HR_LEFT_SHOULDER, HR_RIGHT_SHOULDER = 5, 6
MP_MIN_VISIBILITY = 0.5
LEVEL_SHOULDERS_DEG = 3.0

# MediaPipe index -> HRNet COCO-17 index for the same body part.
MP_TO_HRNET: dict[int, int] = {
    0: 0,  # nose
    2: 1, 5: 2, 7: 3, 8: 4,  # left eye, right eye, left ear, right ear
    11: 5, 12: 6, 13: 7, 14: 8, 15: 9, 16: 10,  # shoulders, elbows, wrists (left, right)
    23: 11, 24: 12, 25: 13, 26: 14, 27: 15, 28: 16,  # hips, knees, ankles (left, right)
}

SHOULDER_BUILD = {  # from the body type the pose classifier already gives
    "inverted_triangle": "Broader than hips",
    "triangle": "Narrower than hips",
    "rectangle": "Balanced with hips",
}


def _dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def classify_face_shape(length_ratio: float, forehead_ratio: float, jaw_ratio: float) -> str:
    """Ratios are to cheekbone width."""
    if length_ratio >= 1.33:
        return "Oblong"
    if jaw_ratio >= 0.83 and length_ratio < 1.25:
        return "Square"
    if length_ratio <= 1.15:
        return "Square" if jaw_ratio >= 0.81 else "Round"
    if forehead_ratio - jaw_ratio >= 0.10 and jaw_ratio <= 0.77:
        return "Heart"
    if forehead_ratio <= 0.83 and jaw_ratio <= 0.77:
        return "Diamond"
    return "Oval"


def face_structure(points: Sequence[tuple[float, float]], img_w: int, img_h: int) -> FaceStructure | None:
    """Face-shape estimate + overlay geometry from the 478 normalised mesh points."""
    if len(points) < 468:
        return None
    px = [(x * img_w, y * img_h) for x, y in points]
    cheek = _dist(px[CHEEK_R], px[CHEEK_L])
    if cheek <= 0:
        return None
    length = _dist(px[FACE_TOP], px[CHIN]) / cheek
    forehead = _dist(px[FOREHEAD_R], px[FOREHEAD_L]) / cheek
    jaw = _dist(px[JAW_R], px[JAW_L]) / cheek
    turn = abs(_dist(px[NOSE_TIP], px[CHEEK_R]) - _dist(px[NOSE_TIP], px[CHEEK_L])) / cheek

    def rounded(p: tuple[float, float]) -> list[float]:
        return [round(p[0], 4), round(p[1], 4)]

    turned = turn > MAX_FACE_TURN
    return FaceStructure(
        face_shape=None if turned else classify_face_shape(length, forehead, jaw),
        note="Turn to face the camera straight on for a face-shape estimate." if turned
        else "Estimated from face-mesh proportions.",
        length_to_cheek=round(length, 3),
        forehead_to_cheek=round(forehead, 3),
        jaw_to_cheek=round(jaw, 3),
        points=[rounded(p) for p in points[:468]],  # the mesh; 468-477 are the irises
        contours={name: [rounded(points[i]) for i in idx] for name, idx in FACE_CONTOURS.items()},
    )


def _mp_shoulders(lms: Sequence[LandmarkPoint], img_w: int, img_h: int):
    if len(lms) <= MP_RIGHT_SHOULDER:
        return None
    left, right = lms[MP_LEFT_SHOULDER], lms[MP_RIGHT_SHOULDER]
    if min(left.visibility, right.visibility) < MP_MIN_VISIBILITY:
        return None
    return (left.x * img_w, left.y * img_h), (right.x * img_w, right.y * img_h)


def _hr_shoulders(kps: Sequence[Keypoint | None], img_w: int, img_h: int):
    if len(kps) <= HR_LEFT_SHOULDER or kps[HR_LEFT_SHOULDER] is None or kps[HR_RIGHT_SHOULDER] is None:
        return None
    left, right = kps[HR_LEFT_SHOULDER], kps[HR_RIGHT_SHOULDER]
    return (left.x * img_w, left.y * img_h), (right.x * img_w, right.y * img_h)


def _tilt_deg(left: tuple[float, float], right: tuple[float, float]) -> float:
    """Signed shoulder-line angle from horizontal; > 0 means the left shoulder sits higher."""
    dx = abs(left[0] - right[0])
    return math.degrees(math.atan2(right[1] - left[1], dx)) if dx > 0 else 0.0


def shoulder_analysis(
    mp_landmarks: Sequence[LandmarkPoint],
    hr_keypoints: Sequence[Keypoint | None],
    img_w: int,
    img_h: int,
    body_type: str | None = None,
    shoulder_width_cm: float | None = None,
) -> ShoulderAnalysis | None:
    lines = {
        "MediaPipe": _mp_shoulders(mp_landmarks, img_w, img_h),
        "HRNet": _hr_shoulders(hr_keypoints, img_w, img_h),
    }
    sources = [name for name, line in lines.items() if line]
    if not sources:
        return None
    tilts = [_tilt_deg(*lines[name]) for name in sources]
    tilt = sum(tilts) / len(tilts)
    if abs(tilt) < LEVEL_SHOULDERS_DEG:
        level = "Level"
    else:
        level = "Left shoulder higher" if tilt > 0 else "Right shoulder higher"
    return ShoulderAnalysis(
        tilt_deg=round(tilt, 1),
        level=level,
        build=SHOULDER_BUILD.get(body_type or ""),
        width_cm=shoulder_width_cm,
        sources=sources,
    )


def model_agreement(
    mp_landmarks: Sequence[LandmarkPoint], hr_keypoints: Sequence[Keypoint | None], img_w: int, img_h: int
) -> ModelAgreement | None:
    """Mean distance between the two models' matching joints, as % of shoulder width."""
    shoulders = _mp_shoulders(mp_landmarks, img_w, img_h)
    if not shoulders or not hr_keypoints:
        return None
    width = _dist(*shoulders)
    if width <= 0:
        return None
    offsets = []
    for mp_i, hr_i in MP_TO_HRNET.items():
        if mp_i >= len(mp_landmarks) or hr_i >= len(hr_keypoints):
            continue
        mp_pt, hr_pt = mp_landmarks[mp_i], hr_keypoints[hr_i]
        if hr_pt is None or mp_pt.visibility < MP_MIN_VISIBILITY:
            continue
        offsets.append(_dist((mp_pt.x * img_w, mp_pt.y * img_h), (hr_pt.x * img_w, hr_pt.y * img_h)) / width)
    if len(offsets) < 3:
        return None
    mean_pct = 100 * sum(offsets) / len(offsets)
    label = "Strong" if mean_pct < 15 else "Moderate" if mean_pct < 30 else "Weak"
    return ModelAgreement(compared_points=len(offsets), mean_offset_pct=round(mean_pct, 1), agreement=label)
