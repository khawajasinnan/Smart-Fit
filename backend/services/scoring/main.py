"""Look scoring & feedback service — SRDS SFR-032 (overall look score),
SFR-033 (styling comments and hints), SFR-034 (feedback), SF-UC-08/09.
Spec §12, with the learned validator of §23.25.

POST /score     the outfit (+ the hairstyle the user chose) -> 0..100 look score:
                formula.py      weighted components (style, colour harmony, fit,
                                occasion, hairstyle), each with its reason
                look_model.py   Random Forest second opinion + exact per-component
                                contributions (interpretable scoring)
                hints.py        comments and practical styling hints (SFR-033)
POST /feedback  the user's 1-5 rating of a scored look, stored in
                public.user_feedback with the component scores they saw, for
                feedback_retrain.py (SFR-034).
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Literal

import httpx
from fastapi import FastAPI, Request
from pydantic import BaseModel, Field

from shared.config import settings
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.service_app import create_service_app
from shared.supabase_client import service_upsert
from services.scoring.formula import LABELS, components_for, compute_score, load_weights
from services.scoring.hints import comments, hints, overall_comment
from services.scoring.look_model import FEATURES, LookValidator, to_row
from services.scoring.look_model import MODEL_DIR as LOOK_MODEL_DIR
from shared.model_registry import file_stamp, read_history
from shared.retrain_scheduler import retrain_loop

logger = logging.getLogger("smartfit.scoring")

_validator_cache: list[LookValidator | None] = []
_validator_stamp: list[float | None] = []


def _validator() -> LookValidator | None:
    """The live look model; reloaded when its card changes, so a model the
    self-learning job promotes (spec §23.26) is used without a restart."""
    stamp = file_stamp(LOOK_MODEL_DIR / "look_card.json")
    if not _validator_cache or (_validator_stamp and stamp != _validator_stamp[0]):
        _validator_cache[:] = [LookValidator.load(LOOK_MODEL_DIR)]
        _validator_stamp[:] = [stamp]
    return _validator_cache[0]


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # spec §23.26: learn from users' look ratings on a schedule (0 = off)
    task = asyncio.create_task(retrain_loop("services.scoring.feedback_retrain", settings.auto_retrain_hours))         if settings.auto_retrain_hours > 0 else None
    try:
        yield
    finally:
        if task is not None:
            task.cancel()


app = create_service_app(
    "scoring",
    "SmartFit Scoring Service",
    "Overall look score, styling hints and feedback learning (SFR-032..034).",
    lifespan=lifespan,
    health_extra=lambda: {"implemented": True, "validator_loaded": _validator() is not None},
)


@app.get("/ml/status")
async def ml_status() -> dict:
    """The live look model, the formula weights and the last self-learning attempts."""
    model = _validator()
    card = model.card if model else None
    return {
        "live_model": None if card is None else {
            k: card.get(k) for k in ("version", "trained_at", "label_source", "rows", "real_rows", "metrics",
                                     "real_holdout")},
        "weights": load_weights(),
        "auto_retrain_every_hours": settings.auto_retrain_hours,
        "min_new_ratings": settings.auto_retrain_min_look_ratings,
        "history": read_history(LOOK_MODEL_DIR),
    }


class LookProduct(BaseModel):
    id: str = Field(..., min_length=1, max_length=300)
    title: str = Field("", max_length=500)
    brand: str | None = Field(None, max_length=120)
    category: str | None = Field(None, max_length=120)
    colors: list[str] = Field(default_factory=list, max_length=20)
    tags: list[str] = Field(default_factory=list, max_length=60)
    price_pkr: float | None = Field(None, ge=0)


class LookProfile(BaseModel):
    gender: str | None = None
    skin_tone: str | None = None
    skin_undertone: Literal["warm", "cool", "neutral"] | None = None  # skin tone analyzer (21 Nov 2026)
    body_type: str | None = None
    style_preferences: list[str] = Field(default_factory=list, max_length=20)
    preferred_colors: list[str] = Field(default_factory=list, max_length=20)


class LookHairstyle(BaseModel):
    hairstyle_id: str | None = None
    name: str | None = Field(None, max_length=120)
    score: float = Field(..., ge=0, le=1, description="Suitability for the face shape (hairstyle service)")
    face_shape: str | None = None


class ScoreRequest(BaseModel):
    product: LookProduct
    profile: LookProfile = Field(default_factory=LookProfile)
    occasion: str | None = Field(None, max_length=60, description="Occasion gathered by the chatbot (SFR-015)")
    fit_status: Literal["fits", "small", "big", "unknown"] = "unknown"
    fit_size: str | None = Field(None, max_length=20)
    hairstyle: LookHairstyle | None = None
    session_id: str | None = None


class ScoreComponent(BaseModel):
    key: str
    label: str
    score: int  # 0..100
    weight: float  # share of the final score
    known: bool  # False: not enough information, a neutral score was used
    note: str
    effect: float | None = Field(None, description="Points this part added (+) or removed (-) in the "
                                                   "Random Forest's view, relative to an average look")


class ScoreValidation(BaseModel):
    model: str = "random_forest"
    predicted_score: int
    agrees: bool
    baseline: int  # the average look's score
    note: str


class ScoreResponse(BaseModel):
    score: int
    verdict: str
    components: list[ScoreComponent]
    comments: list[str]
    hints: list[str]
    validation: ScoreValidation | None = None
    model_features: list[float] = Field(description="Send back with POST /feedback")


class FeedbackRequest(BaseModel):
    product_id: str = Field(..., min_length=1, max_length=300)
    rating: int = Field(..., ge=1, le=5)
    score: int | None = Field(None, ge=0, le=100, description="The look score the user saw")
    model_features: list[float] = Field(..., min_length=len(FEATURES), max_length=len(FEATURES))
    occasion: str | None = Field(None, max_length=60)
    comment: str | None = Field(None, max_length=2000)
    suggestion: str | None = Field(None, max_length=2000)
    # SFR-034 corrections: the parts of the score the user says are wrong
    corrections: list[Literal["style", "colour", "fit", "occasion", "hairstyle"]] = Field(default_factory=list,
                                                                                       max_length=5)
    session_id: str | None = None


class FeedbackResponse(BaseModel):
    stored: bool


def _validation_note(score: float, predicted: float, agrees: bool, effects: dict[str, float]) -> str:
    if agrees:
        return "A second AI model (Random Forest) independently agrees with this score."
    lowest = min(effects, key=effects.get) if effects else None
    highest = max(effects, key=effects.get) if effects else None
    if predicted < score and lowest:
        return (f"A second AI model rates it lower ({round(predicted)}), "
                f"mainly because of {LABELS[lowest].lower()}.")
    if highest:
        return (f"A second AI model rates it higher ({round(predicted)}), "
                f"mainly thanks to {LABELS[highest].lower()}.")
    return f"A second AI model rates it {round(predicted)}."


@app.post("/score", response_model=ScoreResponse, responses={422: {"model": ErrorEnvelope}})
async def score_look(body: ScoreRequest) -> ScoreResponse:
    product = body.product.model_dump()
    profile = body.profile.model_dump()
    hairstyle = body.hairstyle.model_dump() if body.hairstyle else None
    parts = components_for(product, profile, body.occasion, body.fit_status, body.fit_size, hairstyle)
    score, weights = compute_score(parts, load_weights())

    validation, effects = None, {}
    model = _validator()
    if model is not None:
        v = model.validate(parts, score)
        effects = v.contributions
        validation = ScoreValidation(predicted_score=round(v.predicted), agrees=v.agrees,
                                     baseline=round(v.baseline),
                                     note=_validation_note(score, v.predicted, v.agrees, effects))
    return ScoreResponse(
        score=round(score),
        verdict=overall_comment(score),
        components=[ScoreComponent(key=c.key, label=LABELS[c.key], score=round(c.score), weight=weights[c.key],
                                   known=c.known, note=c.note, effect=effects.get(c.key)) for c in parts],
        comments=comments(parts),
        hints=hints(parts, product, profile, body.occasion, body.fit_status, profile.get("gender")),
        validation=validation,
        model_features=to_row(parts),
    )


@app.post("/feedback", response_model=FeedbackResponse,
          responses={401: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def submit_feedback(body: FeedbackRequest, request: Request) -> FeedbackResponse:
    user_id = request.headers.get("x-user-id")
    if not user_id:
        raise AppError(401, "UNAUTHORIZED", "Sign in to rate a look.")
    if not (settings.supabase_url and settings.supabase_service_key):
        raise AppError(503, "SERVICE_UNAVAILABLE", "Feedback storage isn't configured.")
    if any(not (0 <= v <= 100) for v in body.model_features):
        raise AppError(422, "VALIDATION_ERROR", "model_features must be the values returned by /score.")
    row = {
        "user_id": user_id,
        "product_id": f"look:{body.product_id}",
        "feedback_type": "rating",
        "feedback_data": {
            "kind": "look", "rating": body.rating, "score": body.score, "features": body.model_features,
            "occasion": body.occasion, "comment": (body.comment or "").strip() or None,
            "suggestion": body.suggestion, "corrections": sorted(set(body.corrections)),
            "session_id": body.session_id, "source": "app",
        },
    }
    async with httpx.AsyncClient() as client:
        await service_upsert(client, "user_feedback", [row], "user_id,product_id,feedback_type")
    return FeedbackResponse(stored=True)
