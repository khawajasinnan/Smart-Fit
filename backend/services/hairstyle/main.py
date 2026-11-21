"""Hairstyle recommendation service — SRDS SFR-029 (suggest), SFR-030 (2D
overlay preview), SFR-031 (default + alternatives), SF-UC-07. Spec §11.

POST /hairstyles/face-check   one camera frame -> is the face in the guide
                              circle, straight, sharp and well lit? (face_gate.py:
                              MediaPipe + dlib). The app auto-captures on "ready".
POST /hairstyles              the face photo -> face shape (MediaPipe face mesh)
                              + the best-suited catalog hairstyles, each rendered
                              on the user's face (overlay.py).

Photos are processed in memory and never stored: previews go back in the
response. Graceful degradation (SRDS §4.3.1): if this service is down, outfit
recommendations and try-on keep working; the app shows "hairstyles unavailable".
"""

from __future__ import annotations

import base64
import binascii
import io
import logging
import math
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import cv2
import numpy as np
from fastapi import FastAPI
from PIL import Image, ImageOps, UnidentifiedImageError
from starlette.concurrency import run_in_threadpool

from shared.config import settings
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.schemas.hairstyle import (
    FaceCheckRequest,
    FaceCheckResponse,
    HairstylePreview,
    HairstyleRequest,
    HairstyleResponse,
)
from shared.service_app import create_service_app
from services.hairstyle.catalog import CatalogEntry, load_catalog
from services.hairstyle.face_gate import Circle, FaceGate
from services.hairstyle.face_mesh import anchors, skin_luma
from services.hairstyle import gpu_client
from services.hairstyle.hair_profile import profile as hair_profile
from services.hairstyle.overlay import coverage, covers_eyes, head_crop, render, warp
from services.hairstyle.personal_fit import personal_fit
from services.hairstyle.shape_classifier import reason_text, suitability

logger = logging.getLogger("smartfit.hairstyle")

REQUIREMENTS = "SFR-029, SFR-030, SFR-031"
MAX_SIDE = 1280  # photos are scaled down to this before processing
MIN_SIDE = 320
PREVIEW_HEIGHT = 720
FRAME_MAX_SIDE = MAX_SIDE  # live frames: full size, or the eyes are too small to judge sharpness

_faces = None  # services.cv_analysis.face.FaceDetector
_mesh = None  # services.cv_analysis.face_landmarks.FaceLandmarker
_gate: FaceGate | None = None
_hair = None  # services.hairstyle.hair_segment.HairSegmenter
_catalog: list[CatalogEntry] = []


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    global _faces, _mesh, _gate, _hair, _catalog
    try:
        from services.cv_analysis.face import FaceDetector
        from services.cv_analysis.face_landmarks import FaceLandmarker
        from services.hairstyle.hair_segment import HairSegmenter

        _faces = FaceDetector()
        _mesh = FaceLandmarker()
        _gate = FaceGate(_faces)
        _hair = HairSegmenter()
    except Exception:
        logger.exception("Hairstyle models failed to load — the service answers 503 until fixed")
    _catalog = load_catalog()
    try:
        yield
    finally:
        for model in (_faces, _mesh, _hair):
            if model is not None:
                model.close()
        _faces = _mesh = _gate = _hair = None


app = create_service_app(
    "hairstyle",
    "SmartFit Hairstyle Service",
    "Face-shape based hairstyle suggestions with a 2D overlay preview (SFR-029..031).",
    lifespan=lifespan,
    health_extra=lambda: {
        "implemented": True,
        "models_loaded": _gate is not None and _mesh is not None and _hair is not None,
        "catalog_styles": len(_catalog),
        "renderer": "ai" if gpu_client.enabled() else "overlay",
        "gpu_error": gpu_client.error(),
    },
)


# ── helpers ──────────────────────────────────────────────────────────────────


def decode(image_base64: str, max_side: int = MAX_SIDE) -> np.ndarray:
    """Base64 photo -> upright BGR (the phone's EXIF rotation applied), scaled down."""
    raw = image_base64.split(",", 1)[1] if image_base64.startswith("data:") else image_base64
    if len(raw) * 3 // 4 > settings.cv_max_image_bytes:
        raise AppError(422, "IMAGE_TOO_LARGE", "That photo is too large. Please use one under 8 MB.")
    try:
        img = Image.open(io.BytesIO(base64.b64decode(raw, validate=False)))
        img.load()
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (binascii.Error, ValueError, UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise AppError(422, "INVALID_IMAGE", "That photo couldn't be read. Please take it again.") from exc
    if min(img.size) < MIN_SIDE:
        raise AppError(422, "IMAGE_TOO_SMALL", "That photo is too small. Please use your phone camera.")
    scale = min(1.0, max_side / max(img.size))
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
    return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)


def jpeg_bytes(img_bgr: np.ndarray) -> bytes:
    """The photo as JPEG for the GPU app (it finds and crops the face itself)."""
    ok, buf = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 95])
    if not ok:
        raise AppError(500, "INTERNAL_ERROR", "Couldn't prepare the photo.")
    return buf.tobytes()


def jpeg_b64(img_bgr: np.ndarray, height: int = PREVIEW_HEIGHT) -> str:
    h, w = img_bgr.shape[:2]
    if h > height:
        img_bgr = cv2.resize(img_bgr, (round(w * height / h), height), interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 92])
    if not ok:
        raise AppError(500, "INTERNAL_ERROR", "Couldn't make the preview.")
    return base64.b64encode(buf.tobytes()).decode()


def _require_models() -> None:
    if _gate is None or _mesh is None or _hair is None:
        raise AppError(503, "MODEL_UNAVAILABLE", "Hairstyle previews are temporarily unavailable. Please try again later.")


def _style_key(entry: CatalogEntry) -> tuple:
    f = entry.features
    return f.length, f.bangs, f.wavy


def rank(
    entries: list[CatalogEntry], face_shape: str, gender: str | None, count: int, *,
    hair_length: str | None = None, hair_wavy: bool | None = None, occasion: str | None = None,
    outfit: str | None = None, uncovered: dict[str, float] | None = None,
) -> list[tuple[CatalogEntry, float, str]]:
    """Best-suited styles first, varied (one per look before repeats).

    Score = face-shape suitability + personal fit (length the user can wear
    today, texture, occasion, the chosen outfit). `uncovered` is only given for the 2D overlay:
    styles missing from it would sit over an eye and are left out, and styles
    that leave more of the user's own hair showing rank lower (it gets painted
    over). Nobody is refused for having long or full hair (spec §23.27)."""
    pool = [e for e in entries if gender is None or e.features.gender == gender]
    if uncovered is not None:
        pool = [e for e in pool if e.id in uncovered]
    scored = []
    for e in pool:
        s = suitability(face_shape, e.features)
        delta, personal = personal_fit(e.features, hair_length, hair_wavy, occasion, outfit)
        score = max(0.0, min(1.0, s.score + delta))
        order = score - (0.2 * uncovered[e.id] if uncovered is not None else 0.0)
        reason = reason_text(face_shape, s)
        if personal:
            reason = f"{reason[:-1]}; {', '.join(personal[:2])}."
        scored.append((e, order, reason, score))
    scored.sort(key=lambda t: t[1], reverse=True)
    picked, seen = [], set()
    for e, _, reason, score in scored:  # first pass: one per look
        if _style_key(e) not in seen:
            picked.append((e, score, reason))
            seen.add(_style_key(e))
        if len(picked) == count:
            break
    for e, _, reason, score in scored:  # then fill up
        if len(picked) == count:
            break
        if all(e is not p[0] for p in picked):
            picked.append((e, score, reason))
    return picked


def thumb_b64(jpeg: bytes, width: int = 160) -> str | None:
    """A small copy of a preview for the wardrobe card (SFR-035/036): ~5-10 KB."""
    try:
        from PIL import Image

        img = Image.open(io.BytesIO(jpeg)).convert("RGB")
        img.thumbnail((width, width * 2))
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=72, optimize=True)
        return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:  # noqa: BLE001 - a missing thumbnail must never fail the suggestions
        return None


def recommend(img: np.ndarray, gender: str | None, count: int, occasion: str | None = None,
              user_texture: str | None = None, outfit: str | None = None) -> HairstyleResponse:
    """Synchronous; always called in a worker thread."""
    from services.cv_analysis.structure import face_structure

    assert _gate is not None and _mesh is not None and _hair is not None
    verdict = _gate.check(img, None)
    if not verdict.ready:
        raise AppError(422, verdict.code or "NO_FACE", verdict.message, {"reason": verdict.code})
    h, w = img.shape[:2]
    points = _mesh.detect(img)
    face = face_structure(points, w, h)
    user_anchors = anchors(points, w, h)
    if face is None or user_anchors is None:
        raise AppError(422, "NO_FACE", "We couldn't see your face clearly. Please take the photo again.",
                       {"reason": "NO_FACE"})
    if face.face_shape is None:
        raise AppError(422, "FACE_TURNED", "Look straight at the camera so we can measure your face shape.",
                       {"reason": "FACE_TURNED"})
    if not any(gender is None or e.features.gender == gender for e in _catalog):
        raise AppError(503, "CATALOG_MISSING", f"No {gender} hairstyles are set up yet.")
    user_hair = _hair.hair_mask(img)
    hair = hair_profile(img, user_hair, user_anchors)
    if user_texture in ("straight", "wavy"):
        wavy, texture_source = user_texture == "wavy", "user"
    elif hair.wavy is not None:
        wavy, texture_source = hair.wavy, "estimated"
    else:
        wavy, texture_source = None, "unknown"
    common = {
        "face_shape": face.face_shape, "face_shape_note": face.note,
        "length_to_cheek": face.length_to_cheek, "forehead_to_cheek": face.forehead_to_cheek,
        "jaw_to_cheek": face.jaw_to_cheek, "hair_length": hair.length,
        "hair_texture": None if wavy is None else ("wavy" if wavy else "straight"),
        "hair_texture_source": texture_source,
    }
    personal = {"hair_length": hair.length, "hair_wavy": wavy, "occasion": occasion, "outfit": outfit}

    # 1. Realistic previews: HairFastGAN on the GPU replaces the user's own hair.
    note = ""
    if gpu_client.enabled():
        picked = rank(_catalog, face.face_shape, gender, count, **personal)
        out = gpu_client.render(jpeg_bytes(img), [e.id for e, _, _ in picked]) if picked else None
        if out:
            previews = [HairstylePreview(
                hairstyle_id=e.id, name=e.name, colour=e.colour, reason=reason, score=round(score, 3),
                preview_base64=base64.b64encode(out["previews"][e.id]).decode("ascii"), renderer="ai",
                thumb_base64=thumb_b64(out["previews"][e.id]),
            ) for e, score, reason in picked if e.id in out.get("previews", {})]
            if previews:
                return HairstyleResponse(**common, default=previews[0], alternatives=previews[1:],
                                         original_base64=base64.b64encode(out["original"]).decode("ascii"),
                                         renderer="ai")
        note = "Showing a quick 2D preview: the realistic AI preview isn't available right now."

    # 2. The CPU 2D overlay: the user's hair the style doesn't cover is painted over.
    user_skin = skin_luma(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), points)
    uncovered, alphas = {}, {}
    for e in _catalog:
        if gender is None or e.features.gender == gender:
            alpha = warp(e.asset, user_anchors, (w, h))[..., 3] / 255.0
            if covers_eyes(user_anchors, alpha):
                continue  # misaligned on this face: it would hang over an eye
            uncovered[e.id] = coverage(user_hair, alpha)
            alphas[e.id] = alpha
    picked = rank(_catalog, face.face_shape, gender, count, uncovered=uncovered, **personal)
    if not picked:
        raise AppError(422, "STYLES_DONT_FIT_PHOTO",
                       "We couldn't line the hairstyles up with this photo. Please take a straight-on photo "
                       "with your whole head in the circle.", {"reason": "STYLES_DONT_FIT_PHOTO"})
    # One crop for every preview and the original, so before/after line up.
    boxes = [head_crop(img.shape, user_anchors, alphas[e.id]) for e, _, _ in picked]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    previews = []
    for e, score, reason in picked:
        out_img = render(img, user_anchors, e.asset, user_hair, user_skin)
        preview = jpeg_b64(out_img[y0:y1, x0:x1])
        previews.append(HairstylePreview(
            hairstyle_id=e.id, name=e.name, colour=e.colour, reason=reason, score=round(score, 3),
            preview_base64=preview, renderer="overlay", thumb_base64=thumb_b64(base64.b64decode(preview)),
        ))
    return HairstyleResponse(**common, default=previews[0], alternatives=previews[1:],
                             original_base64=jpeg_b64(img[y0:y1, x0:x1]), renderer="overlay", note=note)


# ── endpoints ────────────────────────────────────────────────────────────────


@app.post("/hairstyles/face-check", response_model=FaceCheckResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def face_check(body: FaceCheckRequest) -> FaceCheckResponse:
    _require_models()
    assert _gate is not None
    img = await run_in_threadpool(decode, body.image_base64, FRAME_MAX_SIDE)
    circle = Circle(body.circle.cx, body.circle.cy, body.circle.r) if body.circle else None
    result = await run_in_threadpool(_gate.check, img, circle)
    gpu_client.warm()  # the camera is open: get the GPU ready for the photo (spec §23.27)
    return FaceCheckResponse(
        ready=result.ready, code=result.code, message=result.message,
        face_box=[round(v, 4) for v in result.face_box] if result.face_box else None,
        sharpness=result.sharpness if result.sharpness is None or math.isfinite(result.sharpness) else None,
        brightness=result.brightness,
    )


@app.post("/hairstyles", response_model=HairstyleResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def suggest_hairstyles(body: HairstyleRequest) -> HairstyleResponse:
    _require_models()
    if not _catalog:
        raise AppError(503, "CATALOG_MISSING",
                       "Hairstyle previews aren't set up yet (the hairstyle catalog hasn't been built).")
    img = await run_in_threadpool(decode, body.image_base64)
    return await run_in_threadpool(recommend, img, body.gender, body.count, body.occasion, body.hair_texture,
                                   body.outfit)
