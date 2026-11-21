"""Thin async helper for Supabase's REST API (PostgREST), called *as the user*.

Requests carry the user's own access token, so row-level security applies
exactly as it does for the mobile app — the backend never needs the
service-role key for user-scoped reads (SRDS §4.2, CLAUDE.md "Never Do").
"""

from __future__ import annotations

from typing import Any

import httpx

from shared.config import settings
from shared.schemas.errors import AppError


def _require_config() -> None:
    if not settings.supabase_url or not settings.supabase_anon_key:
        raise AppError(503, "CONFIG_MISSING", "Supabase isn't configured on the server yet.")


async def select_as_user(
    client: httpx.AsyncClient,
    table: str,
    user_token: str,
    params: dict[str, str],
) -> list[dict[str, Any]]:
    """GET /rest/v1/<table>?<params> with the user's token; RLS applies."""
    _require_config()
    try:
        res = await client.get(
            f"{settings.supabase_url.rstrip('/')}/rest/v1/{table}",
            params=params,
            headers={
                "apikey": settings.supabase_anon_key,
                "Authorization": f"Bearer {user_token}",
                "Accept": "application/json",
            },
            timeout=15.0,
        )
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database. Please try again.") from exc
    if res.status_code == 401:
        raise AppError(401, "UNAUTHORIZED", "Your session has expired. Please log in again.")
    if res.status_code >= 400:
        raise AppError(502, "UPSTREAM_ERROR", "The database rejected the request.")
    data = res.json()
    return data if isinstance(data, list) else []


# ── Service-role helpers (backend-only writes: Storage, catalog, config) ──────
#
# These use SUPABASE_SERVICE_KEY, which bypasses RLS. Only call them for data
# the backend owns (scraped catalog, scoring weights, generated images) — never
# to read or write another user's rows on a client's behalf.


def _service_headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    if not settings.supabase_url or not settings.supabase_service_key:
        raise AppError(503, "CONFIG_MISSING", "Supabase service access isn't configured on the server yet.")
    headers = {
        "apikey": settings.supabase_service_key,
        "Authorization": f"Bearer {settings.supabase_service_key}",
    }
    if extra:
        headers.update(extra)
    return headers


def _base() -> str:
    return settings.supabase_url.rstrip("/")


def _check(res: httpx.Response, what: str) -> None:
    """Raise with Supabase's own reason (PostgREST code/message/hint) so a
    missing column or migration is obvious. Never includes request data."""
    if res.status_code < 400:
        return
    reason: dict[str, Any] = {}
    try:
        body = res.json()
        if isinstance(body, dict):
            reason = {k: body[k] for k in ("code", "message", "hint", "error") if body.get(k)}
    except ValueError:
        pass
    detail = f": {reason.get('message') or reason.get('error')}" if reason else ""
    raise AppError(
        502, "UPSTREAM_ERROR", f"Supabase rejected the {what} request ({res.status_code}){detail}", details=reason or None
    )


async def service_select(
    client: httpx.AsyncClient, table: str, params: dict[str, str]
) -> list[dict[str, Any]]:
    """GET /rest/v1/<table> with the service key (RLS bypassed)."""
    headers = _service_headers({"Accept": "application/json"})
    try:
        res = await client.get(f"{_base()}/rest/v1/{table}", params=params, headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    _check(res, "select")
    data = res.json()
    return data if isinstance(data, list) else []


async def service_upsert(
    client: httpx.AsyncClient, table: str, rows: list[dict[str, Any]], on_conflict: str
) -> None:
    """POST /rest/v1/<table>?on_conflict=… as an upsert (merge duplicates)."""
    headers = _service_headers(
        {"Content-Type": "application/json", "Prefer": "resolution=merge-duplicates,return=minimal"}
    )
    try:
        res = await client.post(
            f"{_base()}/rest/v1/{table}",
            params={"on_conflict": on_conflict},
            json=rows,
            headers=headers,
            timeout=30.0,
        )
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    _check(res, "upsert")


async def storage_upload(
    client: httpx.AsyncClient, bucket: str, path: str, data: bytes, content_type: str
) -> str:
    """Upload (or overwrite) an object; returns its path inside the bucket."""
    headers = _service_headers({"Content-Type": content_type, "x-upsert": "true"})
    try:
        res = await client.post(
            f"{_base()}/storage/v1/object/{bucket}/{path.lstrip('/')}", content=data, headers=headers, timeout=60.0
        )
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach file storage.") from exc
    _check(res, "storage upload")
    return path.lstrip("/")


async def storage_signed_url(
    client: httpx.AsyncClient, bucket: str, path: str, expires_in: int | None = None
) -> str:
    """Time-limited URL for a private object (SRDS §4.2: no public buckets)."""
    headers = _service_headers({"Content-Type": "application/json"})
    try:
        res = await client.post(
            f"{_base()}/storage/v1/object/sign/{bucket}/{path.lstrip('/')}",
            json={"expiresIn": expires_in or settings.signed_url_ttl_seconds},
            headers=headers,
            timeout=15.0,
        )
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach file storage.") from exc
    _check(res, "signed URL")
    signed = res.json().get("signedURL") or res.json().get("signedUrl")
    if not signed:
        raise AppError(502, "UPSTREAM_ERROR", "Storage didn't return a signed URL.")
    return f"{_base()}/storage/v1{signed}" if signed.startswith("/") else signed


async def service_update(
    client: httpx.AsyncClient, table: str, filters: dict[str, str], patch: dict[str, Any]
) -> list[dict[str, Any]]:
    """PATCH /rest/v1/<table>?<filters>; returns the updated rows."""
    headers = _service_headers({"Content-Type": "application/json", "Prefer": "return=representation"})
    try:
        res = await client.patch(f"{_base()}/rest/v1/{table}", params=filters, json=patch, headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    _check(res, "update")
    data = res.json()
    return data if isinstance(data, list) else []


async def service_insert(client: httpx.AsyncClient, table: str, row: dict[str, Any]) -> dict[str, Any]:
    headers = _service_headers({"Content-Type": "application/json", "Prefer": "return=representation"})
    try:
        res = await client.post(f"{_base()}/rest/v1/{table}", json=row, headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    _check(res, "insert")
    data = res.json()
    return data[0] if isinstance(data, list) and data else {}


async def service_delete(client: httpx.AsyncClient, table: str, filters: dict[str, str]) -> int:
    """DELETE /rest/v1/<table>?<filters>; returns how many rows went. Refuses an
    unfiltered delete."""
    if not filters:
        raise ValueError("refusing to delete without a filter")
    headers = _service_headers({"Prefer": "return=representation"})
    try:
        res = await client.delete(f"{_base()}/rest/v1/{table}", params=filters, headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    _check(res, "delete")
    data = res.json() if res.content else []
    return len(data) if isinstance(data, list) else 0


async def service_count(client: httpx.AsyncClient, table: str, filters: dict[str, str] | None = None) -> int:
    """Exact row count (PostgREST Content-Range) without fetching rows."""
    headers = _service_headers({"Prefer": "count=exact", "Range-Unit": "items", "Range": "0-0"})
    params = {"select": "*", **(filters or {})}
    try:
        res = await client.get(f"{_base()}/rest/v1/{table}", params=params, headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the database.") from exc
    if res.status_code == 416:  # range not satisfiable: zero rows
        return 0
    _check(res, "count")
    total = res.headers.get("content-range", "*/0").rsplit("/", 1)[-1]
    return int(total) if total.isdigit() else 0


async def storage_list(client: httpx.AsyncClient, bucket: str, prefix: str, _depth: int = 0) -> list[str]:
    """Every object path under `prefix` (a user's folder), sub-folders included.
    A bucket that doesn't exist yields nothing."""
    headers = _service_headers({"Content-Type": "application/json"})
    base = prefix.rstrip("/")
    paths: list[str] = []
    offset = 0
    while True:
        try:
            res = await client.post(
                f"{_base()}/storage/v1/object/list/{bucket}",
                json={"prefix": base, "limit": 100, "offset": offset},
                headers=headers,
                timeout=15.0,
            )
        except httpx.HTTPError as exc:
            raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach file storage.") from exc
        if res.status_code in (400, 404) and "not found" in res.text.lower():
            return paths
        _check(res, "storage list")
        body = res.json()
        items = body if isinstance(body, list) else []
        for it in items:
            path = f"{base}/{it['name']}"
            if it.get("id"):
                paths.append(path)
            elif _depth < 4:  # no id: a folder
                paths += await storage_list(client, bucket, path, _depth + 1)
        if len(items) < 100:
            return paths
        offset += 100


async def storage_remove(client: httpx.AsyncClient, bucket: str, paths: list[str]) -> None:
    if not paths:
        return
    headers = _service_headers({"Content-Type": "application/json"})
    try:
        res = await client.request(
            "DELETE", f"{_base()}/storage/v1/object/{bucket}", json={"prefixes": paths}, headers=headers, timeout=30.0
        )
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach file storage.") from exc
    _check(res, "storage delete")


async def auth_admin_delete_user(client: httpx.AsyncClient, user_id: str) -> None:
    """Delete the Supabase Auth user; every table referencing it cascades."""
    headers = _service_headers()
    try:
        res = await client.delete(f"{_base()}/auth/v1/admin/users/{user_id}", headers=headers, timeout=15.0)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "Couldn't reach the authentication service.") from exc
    if res.status_code == 404:
        return  # already gone
    _check(res, "user delete")
