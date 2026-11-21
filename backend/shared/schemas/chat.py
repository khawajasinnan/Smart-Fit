"""Schemas for the AI stylist chat (chat_orchestrator service, SFR-014..018)."""

from __future__ import annotations

import base64
import binascii
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator

# Gemini accepts these inline image types; the app sends jpeg / png / webp.
ALLOWED_IMAGE_TYPES = ("image/jpeg", "image/png", "image/webp", "image/heic", "image/heif")
MAX_IMAGE_BYTES = 5 * 1024 * 1024  # per image, decoded


class ChatTurn(BaseModel):
    """One earlier turn of the conversation (text only — images are sent once)."""

    role: Literal["user", "model"]
    text: str = Field(..., max_length=16_000)


class ChatImage(BaseModel):
    mime_type: str
    data_base64: str

    @field_validator("mime_type")
    @classmethod
    def _allowed_type(cls, value: str) -> str:
        value = value.strip().lower()
        if value not in ALLOWED_IMAGE_TYPES:
            raise ValueError("Only JPEG, PNG, WEBP or HEIC photos are supported.")
        return value

    @field_validator("data_base64")
    @classmethod
    def _valid_size(cls, value: str) -> str:
        # Check the size before decoding so a huge payload never gets decoded.
        if len(value) * 3 // 4 > MAX_IMAGE_BYTES:
            raise ValueError("Each photo must be smaller than 5 MB.")
        try:
            base64.b64decode(value, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise ValueError("A photo could not be read. Please attach it again.") from exc
        return value


class ChatRequest(BaseModel):
    message: str = Field("", max_length=8_000)
    images: list[ChatImage] = Field(default_factory=list, max_length=4)
    profile_context: str | None = Field(None, max_length=16_000)
    chat_context: str | None = Field(None, max_length=24_000)
    history: list[ChatTurn] = Field(default_factory=list, max_length=32)


class ChatResponse(BaseModel):
    reply: str = Field(..., description="Stylist text to show the user (search trigger removed)")
    search: dict[str, Any] | None = Field(None, description="Parsed [SMARTFIT_SEARCH] trigger, if any")
    search_raw: str | None = Field(None, description="Raw trigger JSON exactly as the model wrote it")
    mood: str | None = Field(None, description="The mascot's mood for this reply (happy, sassy, confused, ...)")
    open: str | None = Field(None, description="App-help answers: a screen the app offers a button to "
                             "(home, tryon, hairstyle, chat, wardrobe, profile, edit_profile, help, privacy)")
    model: str
