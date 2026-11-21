"""AI stylist chat (SFR-014..018) -> chat-orchestrator service."""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser, get_optional_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import forward
from shared.config import settings
from shared.schemas.chat import ChatRequest, ChatResponse
from shared.schemas.errors import ErrorEnvelope

router = APIRouter(tags=["chat"])


@router.post(
    "/chat",
    dependencies=[Depends(rate_limit("chat"))],
    response_model=ChatResponse,
    responses={429: {"model": ErrorEnvelope}, 502: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}},
    openapi_extra={
        "requestBody": {
            "content": {"application/json": {"schema": ChatRequest.model_json_schema()}},
            "required": True,
        }
    },
)
async def chat(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> Response:
    return await forward(request, settings.chat_orchestrator_url, "/chat", service="AI stylist", user=user, timeout=60)
