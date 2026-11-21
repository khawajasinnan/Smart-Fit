"""Uniform error envelope for every SmartFit service (rules.md §3.2).

Every non-2xx response has the shape::

    {"error": {"code": "NOT_IMPLEMENTED", "message": "...", "details": {...}}}

Clients (the Flutter app, the admin panel) parse only this shape. Raw stack
traces and database errors are never returned.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("smartfit.errors")

STATUS_TO_CODE: dict[int, str] = {
    400: "BAD_REQUEST",
    401: "UNAUTHORIZED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    413: "PAYLOAD_TOO_LARGE",
    422: "VALIDATION_ERROR",
    429: "RATE_LIMITED",
    500: "INTERNAL_ERROR",
    501: "NOT_IMPLEMENTED",
    502: "UPSTREAM_ERROR",
    503: "SERVICE_UNAVAILABLE",
    504: "UPSTREAM_TIMEOUT",
}


class ErrorBody(BaseModel):
    code: str
    message: str
    details: dict[str, Any] | None = None


class ErrorEnvelope(BaseModel):
    error: ErrorBody


class AppError(Exception):
    """Raise anywhere in a service to return a well-formed error envelope."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details
        self.headers = headers


def error_response(
    status_code: int,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {"code": code, "message": message}
    if details:
        body["details"] = details
    return JSONResponse(status_code=status_code, content={"error": body}, headers=headers)


def not_implemented(feature: str, requirements: str) -> AppError:
    """501 for features that are scaffolded but not built yet (try-on, hairstyle, scoring)."""
    return AppError(
        501,
        "NOT_IMPLEMENTED",
        f"{feature} is coming soon — it isn't available in this version yet.",
        {"feature": feature, "requirements": requirements},
    )


def _validation_details(exc: RequestValidationError) -> dict[str, Any]:
    errors = []
    for err in exc.errors():
        errors.append(
            {
                "field": ".".join(str(part) for part in err.get("loc", ()) if part != "body"),
                "message": str(err.get("msg", "")),
            }
        )
    return {"errors": errors}


def install_error_handlers(app: FastAPI) -> None:
    """Register handlers so every error leaves the service as an envelope."""

    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return error_response(exc.status_code, exc.code, exc.message, exc.details, exc.headers)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = STATUS_TO_CODE.get(exc.status_code, "ERROR")
        detail = exc.detail
        if isinstance(detail, dict) and "message" in detail:
            return error_response(
                exc.status_code,
                str(detail.get("code", code)),
                str(detail["message"]),
                detail.get("details"),
                getattr(exc, "headers", None),
            )
        return error_response(exc.status_code, code, str(detail), headers=getattr(exc, "headers", None))

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = _validation_details(exc)
        first = details["errors"][0]["message"] if details["errors"] else "Invalid request."
        # Pydantic prefixes custom validator messages with "Value error, ".
        message = first.removeprefix("Value error, ")
        return error_response(422, "VALIDATION_ERROR", message, details)

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error: %s", type(exc).__name__)
        return error_response(500, "INTERNAL_ERROR", "Something went wrong on our side. Please try again.")
