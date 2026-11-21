"""Wardrobe (SFR-035..038). The app reads/writes saved items directly in
Supabase under RLS; this read-only route serves the same data, newest first,
for the admin panel and future clients."""

from typing import Any

from fastapi import APIRouter, Depends, Request

from gateway.middleware.auth import AuthUser, require_user
from gateway.proxy import get_client
from shared.schemas.errors import ErrorEnvelope
from shared.supabase_client import select_as_user

router = APIRouter(tags=["wardrobe"])


@router.get("/wardrobe", responses={401: {"model": ErrorEnvelope}})
async def my_wardrobe(request: Request, user: AuthUser = Depends(require_user)) -> list[dict[str, Any]]:
    token = request.headers["authorization"].split(" ", 1)[1].strip()
    return await select_as_user(
        get_client(),
        "saved_products",
        token,
        {"select": "*", "user_id": f"eq.{user.id}", "order": "created_at.desc"},
    )
