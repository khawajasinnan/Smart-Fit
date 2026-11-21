"""Profile + body analysis (SFR-007, SFR-019..021).

Profile CRUD itself stays in Supabase (the app writes it directly under RLS);
the gateway adds the CV body-analysis route and a read-only /profile/me.
"""

from typing import Any

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, get_optional_user, require_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward, get_client
from shared.config import settings
from shared.schemas.cv import CvAnalysisRequest, CvAnalysisResponse
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.supabase_client import select_as_user

router = APIRouter(tags=["profile"])

_CV_DOCS = {
    "response_model": CvAnalysisResponse,
    "responses": {429: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}},
    "openapi_extra": {
        "requestBody": {
            "content": {"application/json": {"schema": CvAnalysisRequest.model_json_schema()}},
            "required": True,
        }
    },
}


async def _analyze(request: Request, user: AuthUser | None) -> Response:
    return await forward(request, settings.cv_analysis_url, "/analyze/app", service="body analysis", user=user, timeout=45)


@router.post("/cv/analyze", dependencies=[Depends(rate_limit("cv"))], **_CV_DOCS)
async def cv_analyze(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    """Legacy path used by the current app build."""
    return await _analyze(request, user)


@router.post("/profile/analyze-body", dependencies=[Depends(rate_limit("cv"))], **_CV_DOCS)
async def analyze_body(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    return await _analyze(request, user)


@router.post("/skin-tone/analyze", dependencies=[Depends(rate_limit("cv"))],
             responses={422: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def skin_tone_analyze(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    """Skin tone analyzer (21 Nov 2026): depth, undertone and clothing advice from a face photo."""
    return await forward(request, settings.cv_analysis_url, "/skin-tone/analyze", service="skin tone analyzer",
                         user=user, timeout=45)


@router.get("/skin-tone/palette", responses={422: {"model": ErrorEnvelope}})
async def skin_tone_palette(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    """The clothing advice for a skin tone and undertone (?skin_tone=&undertone=)."""
    return await forward(request, settings.cv_analysis_url, "/skin-tone/palette", service="skin tone analyzer", user=user)


@router.get("/profile/me", responses={401: {"model": ErrorEnvelope}, 404: {"model": ErrorEnvelope}})
async def my_profile(request: Request, user: AuthUser = Depends(require_user)) -> dict[str, Any]:
    token = request.headers["authorization"].split(" ", 1)[1].strip()
    rows = await select_as_user(get_client(), "profiles", token, {"select": "*", "id": f"eq.{user.id}"})
    if not rows:
        raise AppError(404, "NOT_FOUND", "Profile not found. Please complete your profile setup.")
    return rows[0]
