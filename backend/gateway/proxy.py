"""Forward requests from the public gateway to internal services.

The gateway passes the body, query string and status code through unchanged,
so each service's contract (and error envelope) reaches the app as-is. Network
failures become clear 503/504 envelopes instead of raw exceptions.
"""

from __future__ import annotations

import logging
import uuid

import httpx
from fastapi import Request
from fastapi.responses import Response

from gateway.middleware.auth import AuthUser
from shared.config import settings
from shared.schemas.errors import AppError

logger = logging.getLogger("smartfit.gateway.proxy")

_client: httpx.AsyncClient | None = None

_PASS_THROUGH_RESPONSE_HEADERS = ("retry-after", "x-request-id")


def set_client(client: httpx.AsyncClient | None) -> None:
    global _client
    _client = client


def get_client() -> httpx.AsyncClient:
    if _client is None:
        raise RuntimeError("Gateway HTTP client not initialised (lifespan not started)")
    return _client


async def forward(
    request: Request,
    base_url: str,
    path: str,
    *,
    service: str,
    user: AuthUser | None = None,
    timeout: float | None = None,
) -> Response:
    """Proxy ``request`` to ``base_url + path`` and return the upstream response."""
    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
    headers = {
        "content-type": request.headers.get("content-type", "application/json"),
        "x-request-id": request_id,
    }
    if user is not None:
        headers["x-user-id"] = user.id

    try:
        upstream = await get_client().request(
            request.method,
            f"{base_url.rstrip('/')}{path}",
            content=await request.body(),
            params=request.query_params,
            headers=headers,
            timeout=timeout or settings.proxy_timeout_seconds,
        )
    except httpx.ConnectError as exc:
        logger.warning("%s unreachable at %s (%s)", service, base_url, request_id)
        raise AppError(
            503,
            "SERVICE_UNAVAILABLE",
            f"The {service} service isn't available right now. Please try again shortly.",
            {"service": service},
        ) from exc
    except httpx.TimeoutException as exc:
        logger.warning("%s timed out (%s)", service, request_id)
        raise AppError(
            504,
            "UPSTREAM_TIMEOUT",
            f"The {service} service took too long to respond. Please try again.",
            {"service": service},
        ) from exc
    except httpx.HTTPError as exc:
        logger.warning("%s request failed: %s (%s)", service, type(exc).__name__, request_id)
        raise AppError(502, "UPSTREAM_ERROR", f"The {service} service had a problem.", {"service": service}) from exc

    out_headers = {h: upstream.headers[h] for h in _PASS_THROUGH_RESPONSE_HEADERS if h in upstream.headers}
    out_headers.setdefault("x-request-id", request_id)
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
        headers=out_headers,
    )
