"""Pydantic schemas for the Computer Vision body analysis pipeline.

Covers:
  - Request: image input (URL or base64) + optional profile hints
  - Response: body shape, estimated size, pose landmarks, skin tone,
    proportions, and confidence metrics
"""

from pydantic import BaseModel, Field


class CvAnalysisRequest(BaseModel):
    """Input to the /cv/analyze endpoint."""

    image_url: str | None = None
    image_base64: str | None = None
    gender: str | None = None
    # Optional known measurements — used to calibrate CV-derived estimates
    height_cm: float | None = None
    weight_kg: float | None = None
    chest_cm: float | None = None
    waist_cm: float | None = None
    hip_cm: float | None = None


class PoseLandmark(BaseModel):
    """A single 3D body landmark from MediaPipe Pose."""

    name: str
    x: float
    y: float
    z: float
    visibility: float


class BodyProportions(BaseModel):
    """Derived body proportions from pose landmark geometry."""

    shoulder_width_ratio: float | None = None  # shoulder / hip width
    torso_length_ratio: float | None = None  # torso / total height
    leg_length_ratio: float | None = None  # leg / total height
    waist_hip_ratio: float | None = None
    shoulder_hip_diff: float | None = None  # px difference (>0 = broader shoulders)


class SkinToneResult(BaseModel):
    """Skin tone analysis from face/neck region."""

    dominant_hex: str = ""  # e.g. "#C49A6C"
    fitzpatrick_type: str = ""  # e.g. "Type III"
    tone_label: str = ""  # e.g. "Medium", "Fair", "Deep"
    hsv_hue: float | None = None
    hsv_saturation: float | None = None
    hsv_value: float | None = None


class CvAnalysisResponse(BaseModel):
    """Full output from the body detection and pose estimation pipeline."""

    success: bool = True
    error: str | None = None

    # ── Body shape classification ──
    body_shape: str | None = None  # Apple / Pear / Rectangle / Hourglass / Inverted Triangle
    body_shape_confidence: float = 0.0  # 0.0–1.0

    # ── Size estimation ──
    estimated_size: str | None = None  # XS / S / M / L / XL / XXL
    estimated_size_source: str = ""  # "pose_landmarks" | "profile_measurements" | "bmi_fallback"
    
    # ── Gender estimation ──
    estimated_gender: str | None = None  # "male", "female", or "uncertain"
    gender_confidence: float | None = None  # 0.0 to 1.0

    # ── Measurements derived from pose (pixel-space ratios, calibrated if height_cm provided) ──
    estimated_chest_cm: float | None = None
    estimated_waist_cm: float | None = None
    estimated_hip_cm: float | None = None
    estimated_shoulder_width_cm: float | None = None

    # ── Proportions ──
    proportions: BodyProportions | None = None

    # ── Pose landmarks (33 from MediaPipe) ──
    pose_landmarks: list[PoseLandmark] = Field(default_factory=list)
    pose_confidence: float = 0.0  # average visibility across all landmarks

    # ── Skin tone ──
    skin_tone: SkinToneResult | None = None

    # ── Image metadata ──
    image_width: int = 0
    image_height: int = 0
