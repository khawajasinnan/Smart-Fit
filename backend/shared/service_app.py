"""Factory for SmartFit FastAPI apps — identical logging, error envelope and
/health endpoint for every microservice, so each service's main.py only
declares its own routes."""

from __future__ import annotations

import logging
from collections.abc import Callable
from contextlib import AbstractAsyncContextManager
from typing import Any

from fastapi import FastAPI

from shared.config import settings
from shared.schemas.errors import install_error_handlers

Lifespan = Callable[[FastAPI], AbstractAsyncContextManager[None]]


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.DEBUG if settings.debug else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )


def create_service_app(
    service: str,
    title: str,
    description: str,
    *,
    version: str = "1.0.0",
    lifespan: Lifespan | None = None,
    health_extra: Callable[[], dict[str, Any]] | None = None,
) -> FastAPI:
    """Build a service app with the shared error handlers and a /health route.

    ``health_extra`` lets a service add readiness facts to /health (e.g. whether
    its model is loaded or its API key is configured).
    """
    configure_logging()
    app = FastAPI(title=title, description=description, version=version, lifespan=lifespan)
    install_error_handlers(app)

    @app.get("/health", tags=["health"])
    async def health() -> dict[str, Any]:
        body: dict[str, Any] = {"status": "ok", "service": service}
        if health_extra is not None:
            body.update(health_extra())
        return body

    return app
