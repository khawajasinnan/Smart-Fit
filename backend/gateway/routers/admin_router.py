"""Admin-only API for the web admin panel (admin-panel/), SFR-039 .. SFR-042.

Every route requires an admin (RBAC, SRDS §4.2). Users, analytics, feedback,
moderation and scraper settings are read and written with the service key
(admins act on other users' rows by design); catalog changes go through the
scraper service, which owns the catalog.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, Query
from pydantic import BaseModel, Field

from gateway import admin_data as ad
from gateway.accounts import delete_user_completely
from gateway.middleware.auth import AuthUser
from gateway.middleware.rbac import require_admin
from gateway.proxy import get_client
from shared.config import settings
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.supabase_client import service_count, service_select, service_update

router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    responses={401: {"model": ErrorEnvelope}, 403: {"model": ErrorEnvelope}},
)

PROFILE_LIST_FIELDS = ("id,email,full_name,username,gender,avatar_url,photo_url,profile_completed,is_banned,"
                       "ban_reason,banned_at,suspended_until,suspension_reason,deactivated_at,created_at")
_running_scrapes: set[str] = set()


def _now() -> datetime:
    return datetime.now(UTC)


def _uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError as exc:
        raise AppError(400, "BAD_REQUEST", "That isn't a valid id.") from exc


# ── services health (SF-UC-11) ──────────────────────────────────────────────


def _services() -> dict[str, str]:
    return {
        "cv-analysis": settings.cv_analysis_url,
        "recommendation": settings.recommendation_url,
        "scraper": settings.scraper_url,
        "chat-orchestrator": settings.chat_orchestrator_url,
        "tryon": settings.tryon_url,
        "hairstyle": settings.hairstyle_url,
        "scoring": settings.scoring_url,
    }


async def _probe(name: str, url: str) -> tuple[str, dict[str, Any]]:
    try:
        res = await get_client().get(f"{url.rstrip('/')}/health", timeout=5.0)
        return name, {"up": res.status_code == 200, **(res.json() if res.status_code == 200 else {})}
    except (httpx.HTTPError, ValueError):
        return name, {"up": False}


@router.get("/services")
async def services_health(_: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    results = await asyncio.gather(*(_probe(n, u) for n, u in _services().items()))
    return {"gateway": {"up": True}, **dict(results)}


@router.get("/ml")
async def ml_status(_: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    """Self-learning status (spec §23.26): the live recommendation and look
    models, their metrics and the last retraining attempts."""

    async def one(name: str, url: str) -> tuple[str, dict[str, Any]]:
        try:
            res = await get_client().get(f"{url.rstrip('/')}/ml/status", timeout=5.0)
            return name, res.json() if res.status_code == 200 else {"up": False}
        except (httpx.HTTPError, ValueError):
            return name, {"up": False}

    results = await asyncio.gather(one("recommendation", settings.recommendation_url),
                                   one("scoring", settings.scoring_url))
    return dict(results)


# ── users (SFR-039) ─────────────────────────────────────────────────────────


@router.get("/users")
async def list_users(
    search: str = "",
    status: Literal["all", "active", "suspended", "banned", "deactivated", "incomplete"] = "all",
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    _: AuthUser = Depends(require_admin),
) -> dict[str, Any]:
    now = _now()
    filters = ad.user_filters(search, status, now)
    client = get_client()
    total, rows = await asyncio.gather(
        service_count(client, "profiles", filters),
        service_select(client, "profiles", {
            **filters, "select": PROFILE_LIST_FIELDS, "order": "created_at.desc",
            "limit": str(page_size), "offset": str((page - 1) * page_size),
        }),
    )
    return {"items": [r | {"status": ad.user_status(r, now)} for r in rows],
            "total": total, "page": page, "page_size": page_size}


@router.get("/users/{user_id}")
async def user_detail(user_id: str, _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    user_id = _uuid(user_id)
    client = get_client()
    rows = await service_select(client, "profiles", {"select": "*", "id": f"eq.{user_id}"})
    if not rows:
        raise AppError(404, "NOT_FOUND", "That user doesn't exist.")
    sessions, saved, feedback = await asyncio.gather(
        service_count(client, "chat_sessions", {"user_id": f"eq.{user_id}"}),
        service_count(client, "saved_products", {"user_id": f"eq.{user_id}"}),
        service_count(client, "user_feedback", {"user_id": f"eq.{user_id}"}),
    )
    profile = rows[0]
    return {"profile": profile | {"status": ad.user_status(profile, _now())},
            "counts": {"chat_sessions": sessions, "saved_items": saved, "feedback": feedback}}


class SuspendBody(BaseModel):
    days: int = Field(ge=1, le=365)
    reason: str = Field("", max_length=500)


class BanBody(BaseModel):
    reason: str = Field("", max_length=500)


async def _update_profile(user_id: str, patch: dict[str, Any]) -> dict[str, Any]:
    rows = await service_update(get_client(), "profiles", {"id": f"eq.{user_id}"},
                                patch | {"updated_at": ad.iso_z(_now())})
    if not rows:
        raise AppError(404, "NOT_FOUND", "That user doesn't exist.")
    return rows[0] | {"status": ad.user_status(rows[0], _now())}


def _not_self(admin: AuthUser, user_id: str, action: str) -> None:
    if admin.id == user_id:
        raise AppError(400, "NOT_ALLOWED", f"You can't {action} your own admin account.")


@router.post("/users/{user_id}/suspend")
async def suspend_user(user_id: str, body: SuspendBody, admin: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    user_id = _uuid(user_id)
    _not_self(admin, user_id, "suspend")
    now = _now()
    return await _update_profile(user_id, {
        "suspended_until": ad.iso_z(now + timedelta(days=body.days)),
        "suspension_reason": body.reason.strip() or "Temporary safety suspension",
        "suspended_at": ad.iso_z(now),
    })


@router.post("/users/{user_id}/unsuspend")
async def unsuspend_user(user_id: str, _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    return await _update_profile(_uuid(user_id), {"suspended_until": None, "suspension_reason": None,
                                                  "suspended_at": None})


@router.post("/users/{user_id}/ban")
async def ban_user(user_id: str, body: BanBody, admin: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    user_id = _uuid(user_id)
    _not_self(admin, user_id, "ban")
    return await _update_profile(user_id, {
        "is_banned": True, "ban_reason": body.reason.strip() or "Policy violation", "banned_at": ad.iso_z(_now()),
        "suspended_until": None, "suspension_reason": None, "suspended_at": None,
    })


@router.post("/users/{user_id}/unban")
async def unban_user(user_id: str, _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    return await _update_profile(_uuid(user_id), {"is_banned": False, "ban_reason": None, "banned_at": None})


@router.delete("/users/{user_id}")
async def delete_user(user_id: str, admin: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    user_id = _uuid(user_id)
    _not_self(admin, user_id, "delete")
    if not await service_select(get_client(), "profiles", {"select": "id", "id": f"eq.{user_id}"}):
        raise AppError(404, "NOT_FOUND", "That user doesn't exist.")
    return {"deleted": user_id, "files_removed": await delete_user_completely(get_client(), user_id)}


# ── catalog (SFR-040): forwarded to the scraper service ─────────────────────


async def _scraper(method: str, path: str, **kwargs) -> Any:
    try:
        res = await get_client().request(method, f"{settings.scraper_url.rstrip('/')}{path}", timeout=60.0, **kwargs)
    except httpx.HTTPError as exc:
        raise AppError(503, "SERVICE_UNAVAILABLE", "The catalog service isn't reachable right now.") from exc
    try:
        body = res.json()
    except ValueError:
        body = {}
    if res.status_code >= 400:
        err = body.get("error", {}) if isinstance(body, dict) else {}
        raise AppError(res.status_code if res.status_code < 500 else 502, err.get("code", "UPSTREAM_ERROR"),
                       err.get("message", "The catalog service rejected the request."))
    return body


@router.get("/products")
async def list_products(
    search: str = "", retailer: str = "", tryon_category: str = "",
    page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    _: AuthUser = Depends(require_admin),
) -> Any:
    return await _scraper("GET", "/catalog/products", params={
        "search": search, "retailer": retailer, "tryon_category": tryon_category,
        "page": page, "page_size": page_size})


@router.post("/products", status_code=201)
async def add_product(body: dict[str, Any], _: AuthUser = Depends(require_admin)) -> Any:
    return await _scraper("POST", "/catalog/products", json=body)


@router.patch("/products/{product_id}")
async def edit_product(product_id: str, body: dict[str, Any], _: AuthUser = Depends(require_admin)) -> Any:
    return await _scraper("PATCH", f"/catalog/products/{product_id}", json=body)


@router.delete("/products/{product_id}")
async def remove_product(product_id: str, _: AuthUser = Depends(require_admin)) -> Any:
    return await _scraper("DELETE", f"/catalog/products/{product_id}")


@router.post("/catalog/import-csv")
async def import_csv(body: dict[str, Any], _: AuthUser = Depends(require_admin)) -> Any:
    return await _scraper("POST", "/catalog/import-csv", json=body)


# ── scraper configuration (SFR-040) ─────────────────────────────────────────


class ScraperPatch(BaseModel):
    enabled: bool | None = None
    max_products: int | None = Field(None, ge=1, le=2000)


@router.get("/scraper")
async def scraper_config(_: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    rows = await service_select(get_client(), "scraper_config", {"select": "*", "order": "retailer.asc"})
    return {"retailers": [r | {"running": r["retailer"] in _running_scrapes} for r in rows]}


@router.patch("/scraper/{retailer}")
async def update_scraper(retailer: str, body: ScraperPatch, _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    patch = body.model_dump(exclude_none=True)
    if not patch:
        raise AppError(400, "BAD_REQUEST", "Nothing to change.")
    rows = await service_update(get_client(), "scraper_config", {"retailer": f"eq.{retailer}"},
                                patch | {"updated_at": ad.iso_z(_now())})
    if not rows:
        raise AppError(404, "NOT_FOUND", "Unknown retailer.")
    return rows[0]


async def _run_refresh(retailer: str, max_products: int) -> None:
    status, summary = "failed", {}
    try:
        res = await get_client().post(f"{settings.scraper_url.rstrip('/')}/catalog/refresh",
                                      json={"retailers": [retailer], "max_products": max_products}, timeout=1800.0)
        summary = res.json() if res.content else {}
        status = "ok" if res.status_code == 200 and not summary.get("errors") else "failed"
    except (httpx.HTTPError, ValueError) as exc:
        summary = {"error": f"scraper unreachable: {type(exc).__name__}"}
    finally:
        _running_scrapes.discard(retailer)
    try:
        await service_update(get_client(), "scraper_config", {"retailer": f"eq.{retailer}"}, {
            "last_run_at": ad.iso_z(_now()), "last_run_status": status, "last_run_summary": summary})
    except AppError:
        pass


@router.post("/scraper/{retailer}/run", status_code=202)
async def run_scraper(retailer: str, background: BackgroundTasks, _: AuthUser = Depends(require_admin)) -> dict:
    rows = await service_select(get_client(), "scraper_config", {"select": "*", "retailer": f"eq.{retailer}"})
    if not rows:
        raise AppError(404, "NOT_FOUND", "Unknown retailer.")
    cfg = rows[0]
    if cfg["mode"] != "feed":
        raise AppError(400, "NOT_A_FEED", "This retailer is imported from a CSV; use Import CSV instead.")
    if not cfg["enabled"]:
        raise AppError(400, "DISABLED", "Enable this retailer before running it.")
    if retailer in _running_scrapes:
        raise AppError(409, "ALREADY_RUNNING", "A refresh for this retailer is already running.")
    _running_scrapes.add(retailer)
    await service_update(get_client(), "scraper_config", {"retailer": f"eq.{retailer}"},
                         {"last_run_status": "running", "last_run_at": ad.iso_z(_now())})
    background.add_task(_run_refresh, retailer, cfg["max_products"])
    return {"started": retailer}


# ── analytics (SFR-041) ─────────────────────────────────────────────────────


async def _product_names(ids: list[str]) -> dict[str, dict[str, Any]]:
    wanted = sorted({i for i in ids if i and '"' not in i and "\\" not in i})
    if not wanted:
        return {}
    quoted = ",".join(f'"{i}"' for i in wanted)  # ids contain ':', so quote each
    rows = await service_select(get_client(), "products", {
        "select": "product_id,name,image_url,retailer,price", "product_id": f"in.({quoted})"})
    return {r["product_id"]: r for r in rows}


@router.get("/analytics")
async def analytics(days: int = Query(14, ge=7, le=90), _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    client, now = get_client(), _now()
    window = ad.since(now, days)
    stamp = ad.iso_z(now)
    (users_total, new_7d, new_30d, completed, banned, suspended, deactivated, sessions_total, messages_total,
     products_total, active_rows, session_rows, rec_rows, fb_rows, health) = await asyncio.gather(
        service_count(client, "profiles"),
        service_count(client, "profiles", {"created_at": f"gte.{ad.since(now, 7)}"}),
        service_count(client, "profiles", {"created_at": f"gte.{ad.since(now, 30)}"}),
        service_count(client, "profiles", {"profile_completed": "is.true"}),
        service_count(client, "profiles", {"is_banned": "is.true"}),
        service_count(client, "profiles", {"suspended_until": f"gt.{stamp}"}),
        service_count(client, "profiles", {"deactivated_at": "not.is.null"}),
        service_count(client, "chat_sessions"),
        service_count(client, "chat_messages"),
        service_count(client, "products"),
        service_select(client, "chat_sessions", {"select": "user_id", "updated_at": f"gte.{ad.since(now, 7)}",
                                                 "limit": "10000"}),
        service_select(client, "chat_sessions", {"select": "created_at", "created_at": f"gte.{window}",
                                                 "limit": "10000"}),
        service_select(client, "recommendation_events", {"select": "product_ids,latency_ms,created_at",
                                                          "created_at": f"gte.{window}", "limit": "10000"}),
        service_select(client, "user_feedback", {"select": "product_id,feedback_type,created_at",
                                                 "created_at": f"gte.{window}", "limit": "10000"}),
        services_health(),
    )
    latencies = [r["latency_ms"] for r in rec_rows if r.get("latency_ms") is not None]
    top_recommended = ad.top_counts((pid for r in rec_rows for pid in (r.get("product_ids") or [])), 10)
    top_loved = ad.top_counts((r["product_id"] for r in fb_rows if r["feedback_type"] == "loved_fit"), 10)
    names = await _product_names([t["id"] for t in top_recommended + top_loved])
    for item in top_recommended + top_loved:
        item["product"] = names.get(item["id"])
    by_type: dict[str, int] = {}
    for r in fb_rows:
        by_type[r["feedback_type"]] = by_type.get(r["feedback_type"], 0) + 1
    return {
        "window_days": days,
        "users": {"total": users_total, "new_7d": new_7d, "new_30d": new_30d, "profile_completed": completed,
                  "active_7d": len({r["user_id"] for r in active_rows}), "banned": banned, "suspended": suspended,
                  "deactivated": deactivated},
        "sessions": {"total": sessions_total, "messages_total": messages_total,
                     "per_day": ad.daily_series((r["created_at"] for r in session_rows), days, now)},
        "recommendations": {
            "requests": len(rec_rows), "per_day": ad.daily_series((r["created_at"] for r in rec_rows), days, now),
            "empty_results": sum(1 for r in rec_rows if not r.get("product_ids")),
            "latency_ms_p50": ad.percentile(latencies, 50), "latency_ms_p95": ad.percentile(latencies, 95),
            "top_products": top_recommended, "catalog_size": products_total},
        "feedback": {"total": len(fb_rows), "by_type": by_type, "top_loved": top_loved,
                     "per_day": ad.daily_series((r["created_at"] for r in fb_rows), days, now)},
        "services": health,
    }


# ── feedback review (SFR-042) ───────────────────────────────────────────────


@router.get("/feedback")
async def feedback(
    feedback_type: str = "", page: int = Query(1, ge=1), page_size: int = Query(25, ge=1, le=100),
    _: AuthUser = Depends(require_admin),
) -> dict[str, Any]:
    client = get_client()
    filters = {"feedback_type": f"eq.{feedback_type}"} if feedback_type else {}
    total, rows = await asyncio.gather(
        service_count(client, "user_feedback", filters),
        service_select(client, "user_feedback", {
            **filters, "select": "id,product_id,feedback_type,feedback_data,created_at,profiles(email,full_name)",
            "order": "created_at.desc", "limit": str(page_size), "offset": str((page - 1) * page_size)}),
    )
    names = await _product_names(list({r["product_id"] for r in rows}))
    return {"items": [r | {"product": names.get(r["product_id"])} for r in rows],
            "total": total, "page": page, "page_size": page_size}


# ── chat moderation ─────────────────────────────────────────────────────────


@router.get("/moderation")
async def moderation(
    status: Literal["pending", "reviewed", "all"] = "pending", page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100), _: AuthUser = Depends(require_admin),
) -> dict[str, Any]:
    filters = {"metadata->moderation->>flagged": "eq.true"}
    if status == "pending":
        filters["reviewed_at"] = "is.null"
    elif status == "reviewed":
        filters["reviewed_at"] = "not.is.null"
    client = get_client()
    total, rows = await asyncio.gather(
        service_count(client, "chat_messages", filters),
        service_select(client, "chat_messages", {
            **filters, "select": "id,content,metadata,reviewed_at,created_at,"
                                 "chat_sessions(title,user_id,profiles(email,full_name))",
            "order": "created_at.desc", "limit": str(page_size), "offset": str((page - 1) * page_size)}),
    )
    return {"items": rows, "total": total, "page": page, "page_size": page_size}


@router.post("/moderation/{message_id}/reviewed")
async def mark_reviewed(message_id: str, _: AuthUser = Depends(require_admin)) -> dict[str, Any]:
    message_id = _uuid(message_id)
    client = get_client()
    rows = await service_select(client, "chat_messages", {"select": "id,metadata", "id": f"eq.{message_id}"})
    if not rows:
        raise AppError(404, "NOT_FOUND", "That message doesn't exist.")
    metadata = rows[0].get("metadata") or {}
    moderation = dict(metadata.get("moderation") or {}) | {"review_status": "reviewed"}
    updated = await service_update(client, "chat_messages", {"id": f"eq.{message_id}"},
                                   {"metadata": metadata | {"moderation": moderation},
                                    "reviewed_at": ad.iso_z(_now())})
    return updated[0] if updated else {"id": message_id}
