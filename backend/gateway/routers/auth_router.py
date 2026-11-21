"""Session introspection. Sign-up, login, OTP and password reset are handled
by Supabase Auth directly from the app (SFR-001..005); the gateway only
verifies the resulting JWT."""

from fastapi import APIRouter, Depends

from gateway.middleware.auth import AuthUser, require_user
from gateway.middleware.rbac import is_admin
from shared.schemas.errors import ErrorEnvelope

router = APIRouter(tags=["auth"])


@router.get("/auth/me", responses={401: {"model": ErrorEnvelope}})
async def me(user: AuthUser = Depends(require_user)) -> dict[str, object]:
    return {"id": user.id, "email": user.email, "role": user.role, "is_admin": is_admin(user)}
