"""SmartFit API Gateway — the only backend service the app talks to
(SRDS Fig 5.1 / 5.2: "API Gateway + Rate Limiter + REST Router").

Responsibilities: JWT verification, rate limiting, admin RBAC, request size
limits, and routing /api/v1/* to the internal services. Business logic lives
in the services, never here.

Run locally (from backend/):  uvicorn gateway.main:app --reload --port 8000
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.types import ASGIApp, Receive, Scope, Send

from gateway.middleware.auth import init_verifier
from gateway.proxy import set_client
from gateway.routers import (
    account_router,
    admin_router,
    auth_router,
    chat_router,
    hairstyle_router,
    profile_router,
    recommendation_router,
    scoring_router,
    tryon_router,
    wardrobe_router,
)
from shared.config import settings
from shared.schemas.errors import error_response
from shared.service_app import create_service_app

logger = logging.getLogger("smartfit.gateway")


class BodySizeLimitMiddleware:
    """Reject oversized requests (413) before reading them (SRDS §4.2 secure upload)."""

    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http":
            for name, value in scope.get("headers", []):
                if name == b"content-length":
                    try:
                        too_large = int(value) > self.max_bytes
                    except ValueError:
                        too_large = False
                    if too_large:
                        response = error_response(
                            413,
                            "PAYLOAD_TOO_LARGE",
                            "That upload is too large. Please use a smaller photo.",
                        )
                        await response(scope, receive, send)
                        return
                    break
        await self.app(scope, receive, send)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    client = httpx.AsyncClient()
    set_client(client)
    init_verifier(client)
    logger.info("Gateway ready (auth_required=%s)", settings.auth_required)
    try:
        yield
    finally:
        set_client(None)
        init_verifier(None)
        await client.aclose()


app = create_service_app(
    "gateway",
    "SmartFit API",
    "Public API gateway for the SmartFit mobile app and admin panel.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,  # bearer tokens, not cookies
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(BodySizeLimitMiddleware, max_bytes=settings.max_body_bytes)

for module in (
    auth_router,
    account_router,
    profile_router,
    chat_router,
    recommendation_router,
    tryon_router,
    hairstyle_router,
    scoring_router,
    wardrobe_router,
    admin_router,
):
    app.include_router(module.router, prefix="/api/v1")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("gateway.main:app", host=settings.api_host, port=settings.api_port, reload=True)
