"""Virtual try-on (SFR-026..028) -> tryon service.

Every route needs a signed-in user: results are private to their owner, and
the service files them under the user's id. Starting a job has its own tight
rate limit, because each job uses paid GPU time (spec §19: the only GPU
resource must not be an easy denial-of-service target). Polling uses the
normal limit (the app polls every few seconds).
"""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, require_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward
from shared.config import settings
from shared.schemas.errors import ErrorEnvelope

router = APIRouter(tags=["try-on"])
_DOCS = {"responses": {401: {"model": ErrorEnvelope}, 422: {"model": ErrorEnvelope}, 429: {"model": ErrorEnvelope},
                       503: {"model": ErrorEnvelope}}}
# Starting a job checks the photos, picks the product photo and hands the views to the GPU:
# ~10-15 s warm; the margin covers a slow store CDN or a service that just restarted.
_TIMEOUT = 90.0


@router.post("/tryon", dependencies=[Depends(rate_limit("tryon"))], **_DOCS)
async def start(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    return await forward(request, settings.tryon_url, "/tryon", service="virtual try-on", user=user, timeout=_TIMEOUT)


@router.post("/tryon/sign", dependencies=[Depends(rate_limit("default"))], **_DOCS)
async def sign(request: Request, user: AuthUser = Depends(require_user)) -> Response:
    return await forward(request, settings.tryon_url, "/tryon/sign", service="virtual try-on", user=user)


@router.get("/tryon/{job_id}", dependencies=[Depends(rate_limit("default"))], **_DOCS)
async def status(job_id: str, request: Request, user: AuthUser = Depends(require_user)) -> Response:
    return await forward(request, settings.tryon_url, f"/tryon/{job_id}", service="virtual try-on", user=user,
                         timeout=_TIMEOUT)
