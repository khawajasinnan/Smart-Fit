"""AI stylist chat orchestrator — SRDS SFR-014..018, SF-UC-04.

Owns the Gemini conversation that used to run inside the Flutter app (with the
API key shipped in the app). The service is stateless: the app sends recent
history with each request, so any replica can answer.

POST /chat -> {reply, search, search_raw, mood, open, model}
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from shared.config import settings
from shared.schemas.chat import ChatRequest, ChatResponse
from shared.schemas.errors import ErrorEnvelope
from shared.service_app import create_service_app
from services.chat_orchestrator.gemini_client import generate_reply
from services.chat_orchestrator.tools import parse_mood, parse_open, parse_reply

_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    global _client
    _client = httpx.AsyncClient()
    try:
        yield
    finally:
        await _client.aclose()
        _client = None


app = create_service_app(
    "chat-orchestrator",
    "SmartFit Chat Orchestrator",
    "Gemini-powered AI stylist conversation (SFR-014..018).",
    lifespan=lifespan,
    health_extra=lambda: {"gemini_configured": bool(settings.gemini_api_key), "model": settings.gemini_model},
)


@app.post(
    "/chat",
    response_model=ChatResponse,
    responses={429: {"model": ErrorEnvelope}, 502: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}},
)
async def chat(req: ChatRequest) -> ChatResponse:
    assert _client is not None, "lifespan not started"
    raw = await generate_reply(_client, req)
    _, mood = parse_mood(raw)
    _, screen = parse_open(raw)
    display, search, search_raw = parse_reply(raw)
    if search is not None:
        screen = None  # a product answer shows products, not a screen button
    return ChatResponse(reply=display, search=search, search_raw=search_raw, mood=mood, open=screen,
                        model=settings.gemini_model)
