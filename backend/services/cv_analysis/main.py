"""Computer-vision body analysis service — SRDS SFR-019 (body features),
SFR-020 (size estimation), SFR-021 (processing feedback). Spec §6.

POST /analyze      spec §6.3 contract: multipart image + height_cm ->
                   body type, measurements, skin tone, size. Unusable photos
                   get a structured error (code + message), never a raw 500.
POST /analyze/app  the JSON contract the mobile app uses (via the gateway at
                   /api/v1/cv/analyze). Same pipeline, lenient: it returns
                   what it can and puts the reason in `error`. With
                   "detailed": true it also runs the MediaPipe face mesh and
                   HRNet (face shape, shoulders, both skeletons) for the
                   app's scan view.

Models (pose + face) load once at start-up; CPU work runs in a worker thread
(SRDS §4.1: <= 10 s; MediaPipe takes well under a second).
"""

from __future__ import annotations

import logging
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import cv2
import httpx
import numpy as np
from fastapi import FastAPI, File, Form, UploadFile
from starlette.concurrency import run_in_threadpool

from shared.config import settings
from shared.schemas.cv import (
    AnalyzeResponse,
    BodyMeasurementsCm,
    CvAnalysisRequest,
    CvAnalysisResponse,
    PersonCheckRequest,
    PersonCheckResponse,
    PoseKeypoint,
    PoseLandmark,
    SkinAnalyzeRequest,
    SkinAnalyzeResponse,
    SkinPalette,
)
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.service_app import create_service_app
from services.cv_analysis.analysis import AnalysisError, AnalysisResult, run_analysis
from services.cv_analysis.body_classifier import (
    APP_BODY_SHAPE_LABELS,
    estimate_gender_from_pose,
    estimate_size,
    to_spec_size,
)
from services.cv_analysis.face import FaceBox, FaceDetector
from services.cv_analysis.face_landmarks import FaceLandmarker
from services.cv_analysis.hrnet import KEYPOINT_NAMES as HRNET_NAMES
from services.cv_analysis.hrnet import HRNetEstimator
from services.cv_analysis.person_check import check_person
from services.cv_analysis.pose import (
    LANDMARK_NAMES,
    ImageLoadError,
    PoseEstimator,
    decode_image,
    load_image_from_base64,
    load_image_from_url,
)
from services.cv_analysis.structure import face_structure, model_agreement, shoulder_analysis
from services.cv_analysis.skin_tone import MONK_HEX, analyze_skin_detail
from shared.skin_palette import palette

logger = logging.getLogger("smartfit.cv")

_pose: PoseEstimator | None = None
_faces: FaceDetector | None = None
# Optional extras for the detailed scan; the service runs without them.
_face_mesh: FaceLandmarker | None = None
_hrnet: HRNetEstimator | None = None
_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    global _pose, _faces, _face_mesh, _hrnet, _client
    _client = httpx.AsyncClient()
    try:
        _pose = PoseEstimator()
        _faces = FaceDetector()
    except Exception:
        logger.exception("CV models failed to load — analysis will return a friendly error")
        _pose = _faces = None
    try:
        _face_mesh = FaceLandmarker()
    except Exception:
        logger.exception("Face landmarker failed to load — detailed scans skip the face mesh")
    try:
        _hrnet = HRNetEstimator()
    except Exception:
        logger.exception("HRNet failed to load — detailed scans use MediaPipe only")
    try:
        yield
    finally:
        for model in (_pose, _faces, _face_mesh, _hrnet):
            if model is not None:
                model.close()
        _pose = _faces = _face_mesh = _hrnet = None
        await _client.aclose()
        _client = None


app = create_service_app(
    "cv-analysis",
    "SmartFit CV Analysis Service",
    "MediaPipe pose + face: body type, measurements, skin tone and size (SFR-019..021).",
    lifespan=lifespan,
    health_extra=lambda: {
        "model_loaded": _pose is not None and _faces is not None,
        "face_mesh_loaded": _face_mesh is not None,
        "hrnet_loaded": _hrnet is not None,
    },
)


def _models() -> tuple[PoseEstimator, FaceDetector]:
    if _pose is None or _faces is None:
        raise AppError(503, "MODEL_UNAVAILABLE", "Body analysis is temporarily unavailable. Please try again later.")
    return _pose, _faces


# ── Spec §6.3: POST /analyze (multipart) ────────────────────────────────────


@app.post(
    "/analyze",
    response_model=AnalyzeResponse,
    responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}},
)
async def analyze(
    image: UploadFile = File(..., description="JPG or PNG photo of one person, ideally full body"),
    height_cm: float = Form(..., gt=50, lt=260, description="Height from the profile (SFR-011)"),
    gender: str | None = Form(None, description="male | female; picks the size chart"),
    chest_cm: float | None = Form(None, gt=0),
    waist_cm: float | None = Form(None, gt=0),
    hip_cm: float | None = Form(None, gt=0),
) -> AnalyzeResponse:
    pose, faces = _models()
    raw = await image.read(settings.cv_max_image_bytes + 1)
    if len(raw) > settings.cv_max_image_bytes:
        raise AppError(413, "IMAGE_TOO_LARGE", "That photo is too large. Please use one under 8 MB.")
    started = time.perf_counter()
    try:
        img = await run_in_threadpool(decode_image, raw)
        result = await run_in_threadpool(
            lambda: run_analysis(
                img, pose, faces,
                height_cm=height_cm, gender=gender, chest_cm=chest_cm, waist_cm=waist_cm, hip_cm=hip_cm,
                require_full_body=True, require_face=True,
            )
        )
    except ImageLoadError as exc:
        raise AppError(422, "INVALID_IMAGE", str(exc)) from exc
    except AnalysisError as exc:
        raise AppError(422, exc.code, exc.message) from exc

    assert result.measurements is not None and result.skin_bucket is not None  # guaranteed by require_*
    logger.info(
        "Analyze: %s (%s) skin=%s size=%s", result.body_type, result.body_type_source,
        result.skin_bucket, result.size_label,
    )
    return AnalyzeResponse(
        body_type=result.body_type,
        body_type_source=result.body_type_source,
        measurements=BodyMeasurementsCm(**result.measurements),
        skin_tone=result.skin_bucket,
        estimated_size=to_spec_size(result.size_label),
        processing_time_ms=round((time.perf_counter() - started) * 1000),
    )


# ── The mobile app's JSON contract: POST /analyze/app ───────────────────────


def _app_response(result: AnalysisResult) -> CvAnalysisResponse:
    estimated_gender, gender_confidence = estimate_gender_from_pose(result.proportions)
    pm = result.pose_measurements
    return CvAnalysisResponse(
        success=True,
        body_shape=APP_BODY_SHAPE_LABELS[result.body_type],
        body_shape_confidence=round(result.body_type_confidence, 3),
        body_shape_source=result.body_type_source,
        estimated_size=result.size_label,
        estimated_size_source=result.size_source,
        estimated_gender=estimated_gender,
        gender_confidence=gender_confidence,
        estimated_chest_cm=pm.get("chest_cm"),
        estimated_waist_cm=pm.get("waist_cm"),
        estimated_hip_cm=pm.get("hip_cm"),
        estimated_shoulder_width_cm=pm.get("shoulder_cm"),
        proportions=result.proportions,
        pose_landmarks=[
            PoseLandmark(
                name=LANDMARK_NAMES[i] if i < len(LANDMARK_NAMES) else f"landmark_{i}",
                x=round(lm.x, 5),
                y=round(lm.y, 5),
                z=round(lm.z, 5),
                visibility=round(lm.visibility, 4),
            )
            for i, lm in enumerate(result.landmarks)
        ],
        pose_confidence=round(result.pose_confidence, 4),
        skin_tone=result.skin_tone,
        image_width=result.image_width,
        image_height=result.image_height,
    )


# Photos the detailed extras can't help with either.
_NO_EXTRAS = {"IMAGE_TOO_SMALL", "MULTIPLE_PEOPLE"}


def add_structure(
    response: CvAnalysisResponse,
    img_bgr: np.ndarray,
    landmarks: list,
    body_type: str | None,
    shoulder_cm: float | None,
    face_mesh: FaceLandmarker | None,
    hrnet: HRNetEstimator | None,
) -> None:
    """Detailed scan: face mesh + HRNet + shoulders + model agreement (in place)."""
    h, w = img_bgr.shape[:2]
    if face_mesh is not None:
        response.models_used.append("MediaPipe Face Mesh")
        response.face = face_structure(face_mesh.detect(img_bgr), w, h)
    keypoints = []
    if hrnet is not None:
        response.models_used.append("HRNet-W32 (COCO-17)")
        keypoints = hrnet.detect(img_bgr, landmarks)
        response.hrnet_keypoints = [
            PoseKeypoint(name=HRNET_NAMES[i], x=round(k.x, 5), y=round(k.y, 5), confidence=round(k.confidence, 4))
            for i, k in enumerate(keypoints) if k is not None
        ]
    response.shoulders = shoulder_analysis(landmarks, keypoints, w, h, body_type, shoulder_cm)
    response.model_agreement = model_agreement(landmarks, keypoints, w, h)


def analyze_for_app(
    img_bgr: np.ndarray,
    req: CvAnalysisRequest,
    pose: PoseEstimator,
    faces: FaceDetector,
    face_mesh: FaceLandmarker | None = None,
    hrnet: HRNetEstimator | None = None,
) -> CvAnalysisResponse:
    """Synchronous; always called in a worker thread."""
    started = time.perf_counter()
    try:
        result = run_analysis(
            img_bgr, pose, faces,
            height_cm=req.height_cm, gender=req.gender, chest_cm=req.chest_cm, waist_cm=req.waist_cm,
            hip_cm=req.hip_cm, weight_kg=req.weight_kg, require_full_body=False, require_face=False,
        )
        response = _app_response(result)
        landmarks, body_type = result.landmarks, result.body_type
        shoulder_cm = result.measurements.get("shoulder_cm") if result.measurements else None
        error_code = None
    except AnalysisError as exc:
        # Lenient: still give the profile-based size so the app has something.
        size_label, size_source = estimate_size({}, req.gender, req.chest_cm, req.height_cm, req.weight_kg)
        h, w = img_bgr.shape[:2]
        response = CvAnalysisResponse(
            success=True,
            error=exc.message,
            estimated_size=size_label,
            estimated_size_source=size_source,
            image_width=w,
            image_height=h,
        )
        landmarks, body_type, shoulder_cm, error_code = [], None, None, exc.code

    if req.detailed:
        response.models_used = ["MediaPipe Pose", "MediaPipe Face Detector"]
        if error_code not in _NO_EXTRAS:
            if not landmarks and error_code != "NO_PERSON_DETECTED":
                # e.g. hips out of frame: no body type, but the shoulders can still be measured
                landmarks, _ = pose.detect(img_bgr)
            add_structure(response, img_bgr, landmarks, body_type, shoulder_cm, face_mesh, hrnet)
    response.processing_time_ms = round((time.perf_counter() - started) * 1000)
    return response


@app.post("/analyze/app", response_model=CvAnalysisResponse)
async def analyze_app(body: CvAnalysisRequest) -> CvAnalysisResponse:
    if not body.image_url and not body.image_base64:
        raise AppError(422, "VALIDATION_ERROR", "Provide either 'image_url' or 'image_base64'.")
    if _pose is None or _faces is None:
        return CvAnalysisResponse(success=False, error="Body analysis is temporarily unavailable. Please try again later.")

    try:
        if body.image_url:
            assert _client is not None, "lifespan not started"
            img = await load_image_from_url(_client, body.image_url)
        else:
            img = await run_in_threadpool(load_image_from_base64, body.image_base64 or "")
    except ImageLoadError as exc:
        return CvAnalysisResponse(success=False, error=str(exc))

    return await run_in_threadpool(analyze_for_app, img, body, _pose, _faces, _face_mesh, _hrnet)


# ── Skin tone analyzer (21 Nov 2026) ─────────────────────────────────────────


HEAD_CROP_PX = 640  # the face detector is short-range: a full-body photo's small face is looked for here


def face_in_full_body(img_bgr: np.ndarray, faces: FaceDetector, pose: PoseEstimator | None) -> FaceBox | None:
    """The face of a full-body photo (profile photos often are): the head found by the pose
    model (nose, ears, shoulders), cropped and enlarged, then the face detector on that."""
    if pose is None:
        return None
    points, _ = pose.detect(img_bgr)
    if len(points) < 13:
        return None
    h, w = img_bgr.shape[:2]
    nose, ear_l, ear_r, sh_l, sh_r = points[0], points[7], points[8], points[11], points[12]
    span = max(abs(ear_l.x - ear_r.x) * w * 2.6, abs(sh_l.x - sh_r.x) * w * 0.9, 24.0)
    cx, cy = nose.x * w, nose.y * h
    x0, y0 = int(max(0, cx - span)), int(max(0, cy - span))
    x1, y1 = int(min(w, cx + span)), int(min(h, cy + span))
    if x1 - x0 < 16 or y1 - y0 < 16:
        return None
    crop = img_bgr[y0:y1, x0:x1]
    scale = HEAD_CROP_PX / max(crop.shape[:2])
    big = cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
    found = faces.detect(big)
    if not found:
        return None
    f = found[0]
    return FaceBox(x0 + int(f.x / scale), y0 + int(f.y / scale), max(1, int(f.w / scale)), max(1, int(f.h / scale)),
                   f.score)


def skin_analysis(img_bgr: np.ndarray, faces: FaceDetector, pose: PoseEstimator | None = None) -> SkinAnalyzeResponse:
    """Synchronous; always called in a worker thread."""
    found = faces.detect(img_bgr)
    face = found[0] if found else face_in_full_body(img_bgr, faces, pose)
    if face is None:
        raise AppError(422, "NO_FACE", "We couldn't see a face. Use a clear, front-facing photo in daylight.")
    detail = analyze_skin_detail(img_bgr, face)
    if detail is None:
        raise AppError(422, "NO_SKIN", "We couldn't read your skin colour. Try a brighter photo without filters.")
    notes = []
    if detail["undertone_confidence"] == "low":
        notes.append("Your undertone is close to the line, so answer the two quick questions to confirm it.")
    if not detail["white_balanced"]:
        notes.append("Tip: a photo in daylight with a white or grey wall behind you gives the truest colour.")
    advice = palette(detail["app_label"], detail["undertone"])
    return SkinAnalyzeResponse(
        skin_tone=detail["app_label"], monk_level=detail["monk_level"], monk_hex=MONK_HEX[detail["monk_level"] - 1],
        measured_hex=detail["measured_hex"], undertone=detail["undertone"],
        undertone_confidence=detail["undertone_confidence"], hue_angle=detail["hue_angle"],
        white_balanced=detail["white_balanced"], note=" ".join(notes), palette=SkinPalette(**advice),
    )


@app.post("/skin-tone/analyze", response_model=SkinAnalyzeResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def skin_tone_analyze(body: SkinAnalyzeRequest) -> SkinAnalyzeResponse:
    """Skin depth (Monk scale + the app's swatch) and undertone from a face photo, with clothing advice."""
    if _faces is None:
        raise AppError(503, "MODEL_UNAVAILABLE", "The skin tone analyzer is temporarily unavailable.")
    if not body.image_url and not body.image_base64:
        raise AppError(422, "VALIDATION_ERROR", "Send a photo (image_base64) or your profile photo (image_url).")
    try:
        if body.image_url:  # the profile photo, from an allowed host only (as the body scan)
            assert _client is not None, "lifespan not started"
            img = await load_image_from_url(_client, body.image_url)
        else:
            img = await run_in_threadpool(load_image_from_base64, body.image_base64 or "")
    except ImageLoadError as exc:
        raise AppError(422, "BAD_IMAGE", str(exc)) from exc
    return await run_in_threadpool(skin_analysis, img, _faces, _pose)


@app.get("/skin-tone/palette", response_model=SkinPalette, responses={422: {"model": ErrorEnvelope}})
async def skin_tone_palette(skin_tone: str, undertone: str | None = None) -> SkinPalette:
    """The advice for a chosen swatch and undertone (after the app's two questions)."""
    advice = palette(skin_tone, undertone)
    if advice is None:
        raise AppError(422, "UNKNOWN_SKIN_TONE", "Pick a skin tone first.")
    return SkinPalette(**advice)


# ── Try-on photo check (HRNet, before any GPU work) ─────────────────────────


def person_check(img_bgr: np.ndarray, req: PersonCheckRequest, pose: PoseEstimator, hrnet: HRNetEstimator) -> PersonCheckResponse:
    """Synchronous; always called in a worker thread. MediaPipe counts the
    people and boxes the person; HRNet places the joints the rules use."""
    people = pose.detect_people(img_bgr)
    h, w = img_bgr.shape[:2]
    keypoints = hrnet.detect(img_bgr, people[0] if len(people) == 1 else None)
    verdict = check_person(keypoints, len(people), req.category, req.angle, w, h)
    return PersonCheckResponse(
        ok=verdict.ok, code=verdict.code, message=verdict.message, people=len(people),
        keypoints=[
            PoseKeypoint(name=HRNET_NAMES[i], x=round(k.x, 5), y=round(k.y, 5), confidence=round(k.confidence, 4))
            for i, k in enumerate(keypoints) if k is not None
        ],
    )


@app.post("/pose/check", response_model=PersonCheckResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def pose_check(body: PersonCheckRequest) -> PersonCheckResponse:
    if _pose is None or _hrnet is None:
        raise AppError(503, "MODEL_UNAVAILABLE", "The photo check is temporarily unavailable.")
    try:
        img = await run_in_threadpool(load_image_from_base64, body.image_base64)
    except ImageLoadError as exc:
        raise AppError(422, "INVALID_IMAGE", str(exc)) from exc
    return await run_in_threadpool(person_check, img, body, _pose, _hrnet)
