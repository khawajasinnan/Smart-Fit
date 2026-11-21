"""In-memory sliding-window rate limiting (SRDS §4.2 / rules.md §5: required on
auth and AI-inference endpoints).

Keyed by user id when signed in, otherwise by client IP. Limits are per
process — move to Redis before running more than one gateway replica.
"""

from __future__ import annotations

import asyncio
import math
import time
from collections import deque

from fastapi import Depends, Request

from gateway.middleware.auth import AuthUser, get_optional_user
from shared.config import settings
from shared.schemas.errors import AppError

WINDOW_SECONDS = 60.0
_MAX_KEYS = 10_000


class SlidingWindowLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = {}
        self._lock = asyncio.Lock()

    async def hit(self, key: str, limit: int, window: float = WINDOW_SECONDS) -> float | None:
        """Record a hit. Returns seconds to wait if the limit is exceeded, else None."""
        now = time.monotonic()
        async with self._lock:
            hits = self._hits.setdefault(key, deque())
            while hits and hits[0] <= now - window:
                hits.popleft()
            if len(hits) >= limit:
                return max(0.0, hits[0] + window - now)
            hits.append(now)
            if len(self._hits) > _MAX_KEYS:
                self._prune(now, window)
            return None

    def _prune(self, now: float, window: float) -> None:
        stale = [k for k, d in self._hits.items() if not d or d[-1] <= now - window]
        for k in stale:
            del self._hits[k]

    def reset(self) -> None:
        self._hits.clear()


limiter = SlidingWindowLimiter()


def _limit_for(group: str) -> int:
    return {
        "chat": settings.rate_limit_chat_per_min,
        "recommend": settings.rate_limit_recommend_per_min,
        "cv": settings.rate_limit_cv_per_min,
        "tryon": settings.rate_limit_tryon_per_min,
        "face_check": settings.rate_limit_face_check_per_min,
        "hairstyle": settings.rate_limit_hairstyle_per_min,
    }.get(group, settings.rate_limit_default_per_min)


def rate_limit(group: str):
    """FastAPI dependency factory: ``dependencies=[Depends(rate_limit("chat"))]``."""

    async def _dependency(request: Request, user: AuthUser | None = Depends(get_optional_user)) -> None:
        who = user.id if user else (request.client.host if request.client else "unknown")
        retry_after = await limiter.hit(f"{group}:{who}", _limit_for(group))
        if retry_after is not None:
            raise AppError(
                429,
                "RATE_LIMITED",
                "You're going a bit fast — please wait a moment and try again.",
                {"retry_after_seconds": math.ceil(retry_after)},
                headers={"Retry-After": str(max(1, math.ceil(retry_after)))},
            )

    return _dependency
