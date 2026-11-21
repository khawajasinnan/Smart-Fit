"""Minimal async client for the Gemini generateContent REST API.

Same model, prompt and generation settings the Flutter app used before, but
the API key now stays on the server and is sent as a header (never in the URL,
so it can't leak into logs or proxies).
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from shared.config import settings
from shared.schemas.chat import ChatRequest
from shared.schemas.errors import AppError
from services.chat_orchestrator.system_prompt import SYSTEM_PROMPT

logger = logging.getLogger("smartfit.chat.gemini")

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
# Gemini 2.5's "thinking" tokens count towards maxOutputTokens. With 1200 and no thinking limit
# a long think left too little for the reply: on 20 Nov (E2E run) a reply stopped at "[SMARTFIT",
# so the product search was lost and the stub showed. Thinking is capped, and the reply always
# keeps ~2000 tokens (visible replies are a few hundred; only generated tokens are billed).
THINKING_BUDGET = 1024
GENERATION_CONFIG = {"temperature": 0.7, "topP": 0.9, "topK": 40, "maxOutputTokens": 3072,
                     "thinkingConfig": {"thinkingBudget": THINKING_BUDGET}}
EMPTY_REPLY_FALLBACK = "I'm having trouble thinking right now. Could you try rephrasing that?"
HISTORY_LIMIT = 16


def build_prompt_text(req: ChatRequest) -> str:
    """Compose the user turn exactly like the app did: profile, chat context, message."""
    parts: list[str] = []
    if req.profile_context and req.profile_context.strip():
        parts.append(f"User profile context:\n{req.profile_context}")
    if req.chat_context and req.chat_context.strip():
        parts.append(f"Current chat session context:\n{req.chat_context}")
    parts.append(req.message)
    return "\n\n".join(parts)


def build_contents(req: ChatRequest) -> list[dict[str, Any]]:
    contents: list[dict[str, Any]] = [
        {"role": turn.role, "parts": [{"text": turn.text}]} for turn in req.history[-HISTORY_LIMIT:]
    ]
    user_parts: list[dict[str, Any]] = [{"text": build_prompt_text(req)}]
    user_parts.extend(
        {"inline_data": {"mime_type": img.mime_type, "data": img.data_base64}} for img in req.images
    )
    contents.append({"role": "user", "parts": user_parts})
    return contents


def extract_text(data: dict[str, Any]) -> str:
    """Join the visible text parts of the first candidate (skipping 'thought' parts)."""
    candidates = data.get("candidates") or []
    if not candidates:
        return ""
    if candidates[0].get("finishReason") == "MAX_TOKENS":
        usage = data.get("usageMetadata") or {}
        logger.warning("Gemini reply cut off by the token limit (thinking %s, reply %s tokens)",
                       usage.get("thoughtsTokenCount"), usage.get("candidatesTokenCount"))
    parts = (candidates[0].get("content") or {}).get("parts") or []
    texts = [p.get("text", "") for p in parts if isinstance(p, dict) and not p.get("thought")]
    return "".join(texts).strip()


async def generate_reply(client: httpx.AsyncClient, req: ChatRequest) -> str:
    """Call Gemini and return the raw reply text (search trigger still included)."""
    if not settings.gemini_api_key:
        raise AppError(
            503,
            "CONFIG_MISSING",
            "The AI stylist isn't configured on the server yet (missing GEMINI_API_KEY).",
        )

    body = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": build_contents(req),
        "generationConfig": GENERATION_CONFIG,
    }
    url = f"{GEMINI_BASE_URL}/{settings.gemini_model}:generateContent"

    try:
        response = await client.post(
            url,
            json=body,
            headers={"x-goog-api-key": settings.gemini_api_key},
            timeout=settings.gemini_timeout_seconds,
        )
    except httpx.TimeoutException as exc:
        raise AppError(504, "UPSTREAM_TIMEOUT", "The AI stylist took too long to answer. Please try again.") from exc
    except httpx.HTTPError as exc:
        logger.warning("Gemini network error: %s", type(exc).__name__)
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the AI stylist. Please try again.") from exc

    if response.status_code == 200:
        text = extract_text(response.json())
        return text or EMPTY_REPLY_FALLBACK

    try:
        upstream_message = str((response.json().get("error") or {}).get("message", ""))
    except ValueError:
        upstream_message = ""
    logger.warning("Gemini API error %s: %s", response.status_code, upstream_message[:200])

    if response.status_code == 429:
        raise AppError(
            429,
            "RATE_LIMITED",
            "The AI stylist is a bit busy right now. Please wait about a minute and try again.",
            headers={"Retry-After": "60"},
        )
    if response.status_code in (401, 403):
        raise AppError(502, "UPSTREAM_AUTH", "The AI stylist's API key was rejected. Please tell the app admin.")
    if response.status_code == 400 and "not found" in upstream_message.lower():
        raise AppError(
            502,
            "UPSTREAM_BAD_REQUEST",
            f"The AI model '{settings.gemini_model}' is not available. Please tell the app admin.",
        )
    if response.status_code == 400:
        raise AppError(502, "UPSTREAM_BAD_REQUEST", "The AI stylist couldn't process that message.")
    raise AppError(502, "UPSTREAM_ERROR", "The AI stylist had a problem. Please try again.")
