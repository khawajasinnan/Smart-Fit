"""Hairstyle suggestions + 2D preview (SFR-029..031) -> hairstyle service.

Signed-in users only: the photos are of the user's face. Nothing is stored;
previews come back in the response. The camera's face check is called about
twice a second while the user lines up, so it has its own, higher limit.
"""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, require_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward
from shared.config import settings
from shared.schemas.errors import ErrorEnvelope

router = APIRouter(tags=["hairstyle"])
_DOCS = {"responses": {401: {"model": ErrorEnvelope}, 422: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope},
                       503: {"model": ErrorEnvelope}}}


@router.post("/hairstyles/face-check", dependencies=[Depends(rate_limit("face_check"))], **_DOCS)
async def face_check(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    return await forward(request, settings.hairstyle_url, "/hairstyles/face-check", service="hairstyle", user=user,
                         timeout=15.0)


@router.post("/hairstyles", dependencies=[Depends(rate_limit("hairstyle"))], **_DOCS)
async def suggest(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    return await forward(request, settings.hairstyle_url, "/hairstyles", service="hairstyle", user=user,
                         timeout=settings.hairstyle_gpu_timeout_seconds + 30)  # AI previews on the GPU (§23.27)
