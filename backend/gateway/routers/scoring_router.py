"""Look score + feedback (SFR-032..034) -> scoring service (spec §12, §23.25)."""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, get_optional_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward
from shared.config import settings
from shared.schemas.errors import ErrorEnvelope

router = APIRouter(tags=["scoring"], dependencies=[Depends(rate_limit("default"))])
_DOCS = {"responses": {401: {"model": ErrorEnvelope}, 422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}}}


@router.post("/score", **_DOCS)
async def score(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    return await forward(request, settings.scoring_url, "/score", service="look scoring", user=user)


@router.post("/feedback", **_DOCS)
async def feedback(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    return await forward(request, settings.scoring_url, "/feedback", service="look scoring", user=user)
