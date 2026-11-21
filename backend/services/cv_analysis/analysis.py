"""The CV pipeline shared by both endpoints (spec §6.2).

photo -> quality checks -> pose (33 landmarks) -> body type -> height-scaled
measurements -> face -> skin tone -> size. Pure CPU, run in a worker thread.

Every way a photo can be unusable raises AnalysisError with a stable code the
client can turn into "please retake your photo" (spec §6.3):
IMAGE_TOO_SMALL, POOR_LIGHTING, NO_PERSON_DETECTED, MULTIPLE_PEOPLE,
PARTIAL_BODY, NO_FACE_DETECTED.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from shared.schemas.cv import BodyProportions, SkinToneResult
from services.cv_analysis.body_classifier import (
    LandmarkPoint,
    body_measurements_cm,
    classify_body_shape,
    compute_proportions,
    estimate_measurements_from_pose,
    estimate_size,
)
from services.cv_analysis.face import FaceBox, FaceDetector
from services.cv_analysis.pose import PoseEstimator
from services.cv_analysis.skin_tone import analyze_skin_tone

# ── Tunable photo-quality limits ────────────────────────────────────────────
MIN_IMAGE_SIDE = 256  # px, shorter side
MIN_MEAN_BRIGHTNESS = 45  # 0-255 HSV value, whole image
MIN_LANDMARK_VISIBILITY = 0.5

SHOULDERS_HIPS = (11, 12, 23, 24)
ANKLES = (27, 28)


class AnalysisError(Exception):
    """A photo the pipeline can't use; code and message are client-facing."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class AnalysisResult:
    landmarks: list[LandmarkPoint]
    pose_confidence: float
    proportions: BodyProportions
    body_type: str
    body_type_confidence: float
    body_type_source: str
    measurements: dict[str, float] | None  # spec: shoulder/hip/torso cm (None: no full body)
    pose_measurements: dict[str, float | None]  # chest/waist/hip estimates for size lookup
    face: FaceBox | None
    skin_bucket: str | None
    skin_tone: SkinToneResult | None
    size_label: str  # detailed chart size XS..XXL
    size_source: str
    image_width: int
    image_height: int


def check_quality(img_bgr: np.ndarray) -> None:
    h, w = img_bgr.shape[:2]
    if min(h, w) < MIN_IMAGE_SIDE:
        raise AnalysisError(
            "IMAGE_TOO_SMALL",
            f"This photo is too small ({w}×{h}). Please use one at least {MIN_IMAGE_SIDE} pixels on each side.",
        )
    brightness = float(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)[..., 2].mean())
    if brightness < MIN_MEAN_BRIGHTNESS:
        raise AnalysisError("POOR_LIGHTING", "This photo is too dark. Please retake it in better light.")


def _visible(lms: list[LandmarkPoint], indices: tuple[int, ...]) -> bool:
    return all(lms[i].visibility >= MIN_LANDMARK_VISIBILITY for i in indices)


def run_analysis(
    img_bgr: np.ndarray,
    pose: PoseEstimator,
    faces: FaceDetector,
    *,
    height_cm: float | None,
    gender: str | None = None,
    chest_cm: float | None = None,
    waist_cm: float | None = None,
    hip_cm: float | None = None,
    weight_kg: float | None = None,
    require_full_body: bool,
    require_face: bool,
) -> AnalysisResult:
    """Full pipeline. require_* make the spec endpoint strict; the app's
    endpoint is lenient (it shows what it can and explains the rest)."""
    check_quality(img_bgr)
    img_h, img_w = img_bgr.shape[:2]

    people = pose.detect_people(img_bgr)
    if not people:
        raise AnalysisError(
            "NO_PERSON_DETECTED",
            "We couldn't find a person in this photo. Use a clear, full-body photo facing the camera.",
        )
    if len(people) > 1:
        raise AnalysisError("MULTIPLE_PEOPLE", "More than one person is in this photo. Please use a photo of just you.")
    lms = people[0]
    if not _visible(lms, SHOULDERS_HIPS):
        raise AnalysisError(
            "PARTIAL_BODY", "Your shoulders and hips need to be visible. Step back so more of you is in the photo."
        )
    full_body = _visible(lms, ANKLES)
    if require_full_body and not full_body:
        raise AnalysisError(
            "PARTIAL_BODY", "Please use a full-body photo (head to feet) so we can estimate your measurements."
        )

    proportions = compute_proportions(lms, img_w, img_h, waist_cm, hip_cm)
    body_type, confidence, source = classify_body_shape(proportions, gender, chest_cm, waist_cm, hip_cm)
    measurements = body_measurements_cm(lms, img_w, img_h, height_cm) if (full_body and height_cm) else None
    pose_measurements = estimate_measurements_from_pose(lms, img_w, img_h, height_cm)
    size_label, size_source = estimate_size(pose_measurements, gender, chest_cm, height_cm, weight_kg)

    detected = faces.detect(img_bgr)
    face = detected[0] if detected else None
    skin = analyze_skin_tone(img_bgr, face) if face else None
    if require_face and skin is None:
        raise AnalysisError(
            "NO_FACE_DETECTED", "We couldn't see your face clearly. Face the camera in even light and try again."
        )

    return AnalysisResult(
        landmarks=lms,
        pose_confidence=sum(p.visibility for p in lms) / len(lms),
        proportions=proportions,
        body_type=body_type,
        body_type_confidence=confidence,
        body_type_source=source,
        measurements=measurements,
        pose_measurements=pose_measurements,
        face=face,
        skin_bucket=skin[0] if skin else None,
        skin_tone=skin[1] if skin else None,
        size_label=size_label,
        size_source=size_source,
        image_width=img_w,
        image_height=img_h,
    )
