"""Unified try-on training sample (spec §5.6).

Every LoRA training/evaluation sample, whatever its source, is normalised to
this record before it reaches the trainer, so the training loop never needs
source-specific branches. Manifests are JSON Lines of these records with
paths relative to the dataset root, so the same manifest works locally and
on Kaggle.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, model_validator

from shared.schemas.catalog import TryOnCategory

SourceDataset = Literal["viton-hd", "dresscode", "roboflow-pk", "scraped-pk"]


class TryOnSample(BaseModel):
    # spec §5.6 fields
    person_image_path: str
    cloth_image_path: str
    agnostic_mask_path: str = Field(description="Binary mask, white = garment region to repaint")
    agnostic_person_path: str = Field(description="Person image with the garment region masked out")
    densepose_path: str = Field(description="DensePose IUV map of the person")
    category: TryOnCategory
    source_dataset: SourceDataset
    # additions: a stable id, and the garment text IDM-VTON's prompts need
    sample_id: str = Field(description='"<source>:<split>:<person stem>"')
    garment_caption: str = Field(description='Garment text for "model is wearing …" / "a photo of …"')


# ── Try-on service API (SFR-026..028) ────────────────────────────────────────
#
# A try-on is an async job (spec §8.6): POST returns a job id at once, the app
# polls GET /tryon/{id}. One job dresses up to four photos of the user taken
# from different sides; the app shows them as a drag-to-spin 360° view. Every
# view is an ordinary 2D try-on image (SRDS SFR-026: 2D, never a 3D model).

ViewAngle = Literal["front", "right", "back", "left"]
VIEW_ORDER: tuple[ViewAngle, ...] = ("front", "right", "back", "left")

ViewStatus = Literal["queued", "running", "done", "failed"]
JobStatus = Literal["running", "done", "partial", "failed"]


class TryOnViewInput(BaseModel):
    angle: ViewAngle
    image_base64: str = Field(min_length=100, description="JPEG/PNG/WebP photo of the user, base64 (no data: prefix needed)")


class CustomGarment(BaseModel):
    """The user's own clothes photo instead of a catalog product."""

    image_base64: str = Field(min_length=100, description="JPEG/PNG/WebP photo of the garment, base64")
    category: TryOnCategory = Field(description='"upper" (top), "lower" (bottom) or "dress" (full outfit)')
    name: str | None = Field(None, max_length=80, description='Optional words for the AI, e.g. "denim jacket"')
    # Tape measurements of the garment laid flat, straight across (x2 = around).
    # Tops need the chest, bottoms the waist, full outfits both (shared/size_fit.py).
    chest_width_cm: float | None = Field(None, ge=15, le=120, description="Armpit to armpit, laid flat")
    waist_width_cm: float | None = Field(None, ge=15, le=120, description="Waistband edge to edge, laid flat")


class TryOnJobRequest(BaseModel):
    """Exactly one of `product_id` (a catalog product) or `garment` (the user's own clothes photo)."""

    product_id: str | None = Field(None, min_length=1, max_length=300)
    garment: CustomGarment | None = None
    views: list[TryOnViewInput] = Field(min_length=1, max_length=4)
    # SFR-025 result from the recommendation (true / false / null = fit unknown, spec §23.7).
    size_compatible: bool | None = None
    size: str | None = Field(None, max_length=20)

    @model_validator(mode="after")
    def _one_garment_source(self) -> TryOnJobRequest:
        if (self.product_id is None) == (self.garment is None):
            raise ValueError("send either product_id or garment, not both or neither")
        return self


class TryOnViewResult(BaseModel):
    angle: ViewAngle
    status: ViewStatus
    image_url: str | None = Field(None, description="Signed, time-limited URL (private bucket)")
    storage_path: str | None = Field(None, description="Path in the tryon-results bucket; re-sign it later")
    error_code: str | None = None
    message: str | None = None
    cached: bool = False
    # cloth warping (21 Nov 2026): the garment fitted to the body outline, made on the CPU while
    # the GPU works; null until it's ready, or when it can't be made (no body points / garment outline)
    fitting_url: str | None = Field(None, description="Signed URL of the fitting preview")
    fitting_path: str | None = None


class TryOnFit(BaseModel):
    """The size check done before the try-on (SFR-025). The try-on always runs:
    the size is reported, never a reason to refuse, so the user can see the
    garment on themselves and decide (user's call, 15 Nov 2026)."""

    status: Literal["fits", "small", "big", "unknown"]
    basis: str = Field(description='"size_chart" | "label" | "measurements" | "unknown"')
    size: str | None = Field(None, description="The fitting size, when a size chart was used")
    note: str = ""


class TryOnJob(BaseModel):
    job_id: str
    status: JobStatus
    product_id: str
    category: TryOnCategory
    fit: TryOnFit | None = None
    views: list[TryOnViewResult]
    mode: Literal["modal", "mock"] = Field(description='"mock" = test mode: placeholder images, not a real try-on')
    model_version: str
    elapsed_seconds: float
    estimated_seconds: int


class SignRequest(BaseModel):
    paths: list[str] = Field(min_length=1, max_length=20)


class SignResponse(BaseModel):
    urls: dict[str, str]
