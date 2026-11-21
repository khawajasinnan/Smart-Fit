"""Role-based access control for /admin/* routes (SRDS §4.2 RBAC, SFR-039..042).

Mirrors the database's public.is_smartfit_admin(): an admin is a signed-in
user whose email is listed in ADMIN_EMAILS, or whose Supabase app_metadata
has role "admin" (settable only with the service key, never by the user).
"""

from __future__ import annotations

from fastapi import Depends

from gateway.middleware.auth import AuthUser, require_user
from shared.config import settings
from shared.schemas.errors import AppError


def is_admin(user: AuthUser) -> bool:
    email = (user.email or "").strip().lower()
    return email in settings.admin_email_list or user.app_metadata.get("role") == "admin"


async def require_admin(user: AuthUser = Depends(require_user)) -> AuthUser:
    if not is_admin(user):
        raise AppError(403, "FORBIDDEN", "This area is for SmartFit admins only.")
    return user
