"""Hairstyle service contract (SFR-029..031). The app reaches it through the
gateway at /api/v1/hairstyles and /api/v1/hairstyles/face-check."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class GuideCircle(BaseModel):
    """The circle drawn on the camera preview: centre as fractions of the frame
    width/height, radius as a fraction of the frame width."""

    cx: float = Field(..., ge=0, le=1)
    cy: float = Field(..., ge=0, le=1)
    r: float = Field(..., gt=0.05, le=0.6)


class FaceCheckRequest(BaseModel):
    image_base64: str = Field(..., min_length=1)
    circle: GuideCircle | None = None  # None: an uploaded photo (no circle to be in)


class FaceCheckResponse(BaseModel):
    ready: bool
    code: str | None = None  # NO_FACE | MULTIPLE_FACES | OFF_CENTER | TOO_FAR | TOO_CLOSE | HEAD_TILTED | ...
    message: str
    face_box: list[float] | None = None  # x, y, w, h as fractions of the frame
    sharpness: float | None = None
    brightness: float | None = None


class HairstyleRequest(BaseModel):
    image_base64: str = Field(..., min_length=1, description="The face photo (JPEG/PNG, base64)")
    gender: Literal["male", "female"] | None = Field(None, description="From the profile; None = both")
    count: int = Field(6, ge=1, le=8, description="How many previews (the default + alternatives)")
    occasion: str | None = Field(None, max_length=40, description="e.g. mehndi, office: favours fitting styles")
    outfit: str | None = Field(None, max_length=160, description="SFR-029: the chosen outfit (product name and type, "
                               "e.g. 'Embroidered Sherwani, sherwani'); its style category steers the suggestions")
    hair_texture: Literal["straight", "wavy"] | None = Field(
        None, description="The user's own hair as they describe it; None = estimate it from the photo")


class HairstylePreview(BaseModel):
    hairstyle_id: str
    name: str
    colour: str
    reason: str  # why it suits this face shape
    score: float  # 0..1 suitability for the face shape
    preview_base64: str  # JPEG of the user's face wearing it (never stored on the server)
    thumb_base64: str | None = None  # small JPEG of the same preview, for the wardrobe card (SFR-035/036)
    renderer: Literal["ai", "overlay"] = "overlay"  # ai = HairFastGAN hair transfer (§23.27), overlay = 2D cut-out


class HairstyleResponse(BaseModel):
    face_shape: str  # Oval | Round | Square | Heart | Oblong | Diamond
    face_shape_note: str
    length_to_cheek: float
    forehead_to_cheek: float
    jaw_to_cheek: float
    default: HairstylePreview  # SFR-031: the best match ...
    alternatives: list[HairstylePreview]  # ... and the other options
    original_base64: str  # the same head crop without a new hairstyle, for before/after
    skipped_shorter: int = 0  # kept for older apps; always 0 since §23.27 (nobody is refused for long hair)
    hair_length: Literal["short", "medium", "long"] | None = None  # the user's own hair, measured
    hair_texture: Literal["straight", "wavy"] | None = None  # as the user said, or estimated when confident
    hair_texture_source: Literal["user", "estimated", "unknown"] = "unknown"
    renderer: Literal["ai", "overlay"] = "overlay"
    note: str = ""  # e.g. why the simpler preview was used
