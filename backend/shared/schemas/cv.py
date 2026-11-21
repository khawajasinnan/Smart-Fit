"""Pydantic schemas for the Computer Vision body analysis pipeline.

Covers:
  - Request: image input (URL or base64) + optional profile hints
  - Response: body shape, estimated size, pose landmarks, skin tone,
    proportions, and confidence metrics
"""

from typing import Literal

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
    # Also run the face mesh and HRNet (face shape, shoulders, both
    # skeletons for the app's scan view). Adds ~2-3 s on CPU.
    detailed: bool = False


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
    waist_hip_ratio: float | None = None  # only from real measurements (profile)
    shoulder_hip_diff: float | None = None  # px difference (>0 = broader shoulders)


class SkinToneResult(BaseModel):
    """Skin tone analysis from face/neck region."""

    dominant_hex: str = ""  # e.g. "#C49A6C"
    fitzpatrick_type: str = ""  # e.g. "Type III"
    tone_label: str = ""  # e.g. "Medium", "Fair", "Deep"
    hsv_hue: float | None = None
    hsv_saturation: float | None = None
    hsv_value: float | None = None


class PoseKeypoint(BaseModel):
    """One of HRNet's 17 COCO body keypoints (x, y normalised to the image)."""

    name: str
    x: float
    y: float
    confidence: float


class PersonCheckRequest(BaseModel):
    """POST /pose/check: is this photo usable for a try-on of this kind of garment?"""

    image_base64: str = Field(..., min_length=1)
    category: Literal["upper", "lower", "dress"] = "upper"
    angle: Literal["front", "right", "back", "left"] = "front"


class PersonCheckResponse(BaseModel):
    ok: bool
    code: str | None = None  # NO_PERSON | MULTIPLE_PEOPLE | POSE_NOT_UPRIGHT | PERSON_TOO_SMALL | BODY_CUT_OFF
    message: str = ""
    people: int = 0
    keypoints: list[PoseKeypoint] = Field(default_factory=list)


class FaceStructure(BaseModel):
    """Face mesh (MediaPipe Face Landmarker) and the face-shape estimate."""

    face_shape: str | None = None  # Oval / Round / Square / Heart / Diamond / Oblong; None if the head is turned
    note: str = ""
    length_to_cheek: float
    forehead_to_cheek: float
    jaw_to_cheek: float
    points: list[list[float]] = Field(default_factory=list)  # 468 [x, y], normalised
    contours: dict[str, list[list[float]]] = Field(default_factory=dict)  # named polylines for the overlay


class ShoulderAnalysis(BaseModel):
    tilt_deg: float  # > 0: the person's left shoulder is higher
    level: str  # "Level" / "Left shoulder higher" / "Right shoulder higher"
    build: str | None = None  # relative to hips, from the body-type step
    width_cm: float | None = None  # only when the profile height calibrates the photo
    sources: list[str] = Field(default_factory=list)  # which pose models measured it


class ModelAgreement(BaseModel):
    """How closely MediaPipe and HRNet place the same joints."""

    compared_points: int
    mean_offset_pct: float  # mean joint distance as % of shoulder width
    agreement: str  # Strong / Moderate / Weak


class CvAnalysisResponse(BaseModel):
    """Full output from the body detection and pose estimation pipeline."""

    success: bool = True
    error: str | None = None

    # ── Body shape classification ──
    body_shape: str | None = None  # Apple / Pear / Rectangle / Hourglass / Inverted Triangle
    body_shape_confidence: float = 0.0  # 0.0–1.0
    # "measurements" (profile chest/waist/hip -> all 5 shapes) or "pose" (photo
    # only -> Inverted Triangle / Pear / Rectangle; no waist is visible)
    body_shape_source: str | None = None

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

    # ── Detailed scan (request.detailed) ──
    hrnet_keypoints: list[PoseKeypoint] = Field(default_factory=list)
    face: FaceStructure | None = None
    shoulders: ShoulderAnalysis | None = None
    model_agreement: ModelAgreement | None = None
    models_used: list[str] = Field(default_factory=list)
    processing_time_ms: int | None = None


# ── Spec §6.3 contract: POST /analyze (multipart) ────────────────────────────


class BodyMeasurementsCm(BaseModel):
    """Landmark distances scaled by the user's height (not circumferences)."""

    shoulder_cm: float
    hip_cm: float
    torso_cm: float


class AnalyzeResponse(BaseModel):
    body_type: Literal["hourglass", "inverted_triangle", "triangle", "rectangle", "oval"]
    # "measurements": from the chest/waist/hip sent with the photo (all five
    # types); "pose": photo only (inverted_triangle / triangle / rectangle).
    body_type_source: Literal["measurements", "pose"]
    measurements: BodyMeasurementsCm
    skin_tone: Literal["fair", "light", "medium", "tan", "brown", "deep"]
    estimated_size: Literal["S", "M", "L", "XL"]
    processing_time_ms: int


# ── Skin tone analyzer (21 Nov 2026) ─────────────────────────────────────────


class SkinAnalyzeRequest(BaseModel):
    """A photo with the user's face: sent (image_base64) or the profile photo's address (image_url)."""

    image_base64: str | None = Field(None, min_length=100, max_length=20_000_000)
    image_url: str | None = Field(None, max_length=2048)


class SkinColour(BaseModel):
    name: str
    hex: str


class SkinPalette(BaseModel):
    """Clothing advice for a skin tone + undertone (shared/skin_palette.py)."""

    skin_tone: str
    bucket: str
    undertone: Literal["warm", "cool", "neutral"] | None = None
    summary: str
    best: list[SkinColour]
    avoid: list[SkinColour]
    white: str
    metal: str
    outfits: list[str]
    avoid_tip: str


class SkinAnalyzeResponse(BaseModel):
    """The analyzer's measurement and the advice for it."""

    skin_tone: str  # the app's swatch: Fair / Light / Medium / Olive / Brown / Dark
    monk_level: int = Field(ge=1, le=10)  # Monk Skin Tone scale, 1 lightest .. 10 deepest
    monk_hex: str
    measured_hex: str
    undertone: Literal["warm", "cool", "neutral"]
    undertone_confidence: Literal["high", "low"]
    hue_angle: float
    white_balanced: bool  # a white / grey surface in the photo corrected the light
    note: str = ""
    palette: SkinPalette
