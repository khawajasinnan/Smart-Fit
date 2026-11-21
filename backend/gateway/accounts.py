"""Permanent account removal (SFR-008 for the user, SFR-039 for an admin).

One code path for both: the user's files in every per-user Storage bucket
(folders are named after the user id, as the bucket policies require), then
the Supabase Auth user, whose deletion cascades to every table (profiles,
chats, wardrobe, feedback, analysis results). Needs the service key, which
never leaves the backend.
"""

from __future__ import annotations

import uuid

import httpx

from shared.config import settings
from shared.schemas.errors import AppError
from shared.supabase_client import auth_admin_delete_user, storage_list, storage_remove


def user_buckets() -> tuple[str, ...]:
    return ("avatars", "chat-images", settings.storage_bucket_tryon, settings.storage_bucket_hairstyle)


def _valid_user_id(user_id: str) -> str:
    try:
        return str(uuid.UUID(user_id))
    except ValueError as exc:
        raise AppError(400, "BAD_REQUEST", "That isn't a valid user id.") from exc


async def delete_user_completely(client: httpx.AsyncClient, user_id: str) -> dict[str, int]:
    """Files first (they are not cascaded), then the auth user. Returns files removed per bucket."""
    user_id = _valid_user_id(user_id)
    removed: dict[str, int] = {}
    for bucket in user_buckets():
        paths = await storage_list(client, bucket, user_id)
        await storage_remove(client, bucket, paths)
        removed[bucket] = len(paths)
    await auth_admin_delete_user(client, user_id)
    return removed
