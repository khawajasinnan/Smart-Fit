"""Outfit recommendations (SFR-022..025) -> recommendation service."""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, get_optional_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward
from shared.config import settings
from shared.schemas.errors import ErrorEnvelope
from shared.schemas.recommendation import ScrapeRecommendRequest, ScrapeRecommendResponse

router = APIRouter(tags=["recommendation"])

_DOCS = {
    "response_model": ScrapeRecommendResponse,
    "responses": {429: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}, 504: {"model": ErrorEnvelope}},
    "openapi_extra": {
        "requestBody": {
            "content": {"application/json": {"schema": ScrapeRecommendRequest.model_json_schema()}},
            "required": True,
        }
    },
}


async def _recommend(request: Request, user: AuthUser | None) -> Response:
    return await forward(request, settings.recommendation_url, "/recommend/app", service="recommendation", user=user)


@router.post("/scrape/recommend", dependencies=[Depends(rate_limit("recommend"))], **_DOCS)
async def scrape_recommend(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    """Legacy path used by the current app build."""
    return await _recommend(request, user)


@router.post("/recommendation/recommend", dependencies=[Depends(rate_limit("recommend"))], **_DOCS)
async def recommend(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    return await _recommend(request, user)


@router.get("/culture/guide", dependencies=[Depends(rate_limit("recommend"))])
async def culture_guide(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    """Traditional outfits of the profile's culture, for men or women (?culture=&gender=)."""
    return await forward(request, settings.recommendation_url, "/culture/guide", service="recommendation", user=user)
