"""The signed-in user's own account (SFR-008).

Deactivation is a profile flag the app sets itself (row-level security lets
a user update their own row); signing in again offers reactivation. Deletion
needs the service key, so it lives here.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from gateway.accounts import delete_user_completely
from gateway.middleware.auth import AuthUser, require_user
from gateway.middleware.rate_limit import rate_limit
from gateway.proxy import get_client
from shared.schemas.errors import AppError, ErrorEnvelope

router = APIRouter(tags=["account"])

CONFIRMATION = "DELETE"


class DeleteAccountRequest(BaseModel):
    confirm: str


@router.delete(
    "/account",
    dependencies=[Depends(rate_limit("account"))],
    responses={400: {"model": ErrorEnvelope}, 401: {"model": ErrorEnvelope}},
)
async def delete_my_account(body: DeleteAccountRequest, user: AuthUser = Depends(require_user)) -> dict[str, object]:
    if body.confirm.strip() != CONFIRMATION:
        raise AppError(400, "CONFIRMATION_REQUIRED", f'Type {CONFIRMATION} to confirm deleting your account.')
    removed = await delete_user_completely(get_client(), user.id)
    return {"deleted": True, "files_removed": removed}
