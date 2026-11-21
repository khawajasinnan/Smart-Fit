"""Supabase JWT verification for the gateway (SRDS §4.2: JWT sessions, RBAC).

The app sends the user's Supabase access token as ``Authorization: Bearer``.
Three verification paths, picked per token:

1. Asymmetric (ES256 / RS256) — newer Supabase projects. Verified locally
   against the project's JWKS (cached ~10 min).
2. HS256 with ``SUPABASE_JWT_SECRET`` set — legacy projects, verified locally.
3. Otherwise — ask Supabase (``GET /auth/v1/user``) and cache the answer for
   60 s per token, so a session is checked at most once a minute.

``AUTH_REQUIRED=false`` lets anonymous calls through (local dev, old app
builds), but a token that *is* sent must still be valid.
"""

from __future__ import annotations

import hashlib
import logging
import time
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Any

import httpx
import jwt
from fastapi import Depends, Request
from starlette.concurrency import run_in_threadpool

from shared.config import settings
from shared.schemas.errors import AppError

logger = logging.getLogger("smartfit.gateway.auth")

AUDIENCE = "authenticated"
LEEWAY_SECONDS = 30
REMOTE_CACHE_TTL = 60.0
REMOTE_CACHE_MAX = 1024


@dataclass(frozen=True)
class AuthUser:
    id: str
    email: str | None = None
    role: str | None = None
    app_metadata: dict[str, Any] = field(default_factory=dict)


def _unauthorized(message: str = "Your session has expired. Please log in again.") -> AppError:
    return AppError(401, "UNAUTHORIZED", message, headers={"WWW-Authenticate": "Bearer"})


def _user_from_claims(claims: dict[str, Any]) -> AuthUser:
    sub = claims.get("sub")
    if not sub:
        raise _unauthorized()
    return AuthUser(
        id=str(sub),
        email=claims.get("email"),
        role=claims.get("role"),
        app_metadata=claims.get("app_metadata") or {},
    )


class TokenVerifier:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client
        self._jwks: jwt.PyJWKClient | None = None
        self._remote_cache: OrderedDict[str, tuple[float, AuthUser]] = OrderedDict()

    @property
    def _issuer(self) -> str | None:
        return f"{settings.supabase_url.rstrip('/')}/auth/v1" if settings.supabase_url else None

    def _jwks_client(self) -> jwt.PyJWKClient:
        if self._jwks is None:
            if not settings.supabase_url:
                raise _unauthorized("Login isn't configured on the server (missing SUPABASE_URL).")
            url = f"{settings.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"
            self._jwks = jwt.PyJWKClient(url, cache_keys=True, lifespan=600)
        return self._jwks

    def _decode_options(self) -> dict[str, Any]:
        return {"require": ["exp", "sub"], "verify_iss": self._issuer is not None}

    async def verify(self, token: str) -> AuthUser:
        try:
            header = jwt.get_unverified_header(token)
        except jwt.PyJWTError as exc:
            raise _unauthorized() from exc
        alg = header.get("alg")

        try:
            if alg in ("ES256", "RS256", "EdDSA"):
                signing_key = await run_in_threadpool(self._jwks_client().get_signing_key_from_jwt, token)
                claims = jwt.decode(
                    token,
                    signing_key.key,
                    algorithms=[alg],
                    audience=AUDIENCE,
                    issuer=self._issuer,
                    leeway=LEEWAY_SECONDS,
                    options=self._decode_options(),
                )
                return _user_from_claims(claims)
            if alg == "HS256" and settings.supabase_jwt_secret:
                claims = jwt.decode(
                    token,
                    settings.supabase_jwt_secret,
                    algorithms=["HS256"],
                    audience=AUDIENCE,
                    issuer=self._issuer,
                    leeway=LEEWAY_SECONDS,
                    options=self._decode_options(),
                )
                return _user_from_claims(claims)
        except jwt.PyJWTError as exc:
            raise _unauthorized() from exc

        return await self._verify_remote(token)

    async def _verify_remote(self, token: str) -> AuthUser:
        key = hashlib.sha256(token.encode()).hexdigest()
        now = time.monotonic()
        cached = self._remote_cache.get(key)
        if cached and cached[0] > now:
            return cached[1]

        if not settings.supabase_url or not settings.supabase_anon_key:
            raise _unauthorized("Login isn't configured on the server (missing Supabase settings).")
        try:
            res = await self._client.get(
                f"{settings.supabase_url.rstrip('/')}/auth/v1/user",
                headers={"apikey": settings.supabase_anon_key, "Authorization": f"Bearer {token}"},
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            logger.warning("Supabase auth check failed: %s", type(exc).__name__)
            raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't verify your session. Please try again.") from exc
        if res.status_code != 200:
            raise _unauthorized()

        data = res.json()
        user = AuthUser(
            id=str(data.get("id", "")),
            email=data.get("email"),
            role=data.get("role"),
            app_metadata=data.get("app_metadata") or {},
        )
        if not user.id:
            raise _unauthorized()

        self._remote_cache[key] = (now + REMOTE_CACHE_TTL, user)
        self._remote_cache.move_to_end(key)
        while len(self._remote_cache) > REMOTE_CACHE_MAX:
            self._remote_cache.popitem(last=False)
        return user


_verifier: TokenVerifier | None = None


def init_verifier(client: httpx.AsyncClient | None) -> None:
    global _verifier
    _verifier = TokenVerifier(client) if client is not None else None


def _bearer_token(request: Request) -> str | None:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    return token.strip()


async def get_optional_user(request: Request) -> AuthUser | None:
    """The signed-in user, or None for anonymous calls when AUTH_REQUIRED=false."""
    token = _bearer_token(request)
    if token is None:
        if settings.auth_required:
            raise _unauthorized("Please log in to continue.")
        return None
    if _verifier is None:
        raise RuntimeError("Token verifier not initialised (lifespan not started)")
    user = await _verifier.verify(token)
    request.state.user = user
    return user


async def require_user(user: AuthUser | None = Depends(get_optional_user)) -> AuthUser:
    """Always requires a valid session, regardless of AUTH_REQUIRED."""
    if user is None:
        raise _unauthorized("Please log in to continue.")
    return user
