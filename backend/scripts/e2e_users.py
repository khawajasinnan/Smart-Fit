"""Test shoppers for the Playwright end-to-end tests (e2e/), on the hosted Supabase.

    python scripts/e2e_users.py create    # two verified users: one woman, one man
    python scripts/e2e_users.py delete    # remove them and ALL their data (files too)

The user approved creating them for testing on 20 Nov 2026, and deleting them
afterwards. Their logins go only to e2e/.env.local (gitignored); passwords are
never printed. `delete` only touches the ids written by `create`, and only
accounts whose email starts with E2E_PREFIX, through the same deletion path as
"Delete account" (gateway/accounts.py: storage files, then the auth user, which
cascades to every table).
"""

from __future__ import annotations

import asyncio
import secrets
import string
import sys
from pathlib import Path

import httpx

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from gateway.accounts import delete_user_completely  # noqa: E402
from shared.config import settings  # noqa: E402

ENV_FILE = BACKEND.parent / "e2e" / ".env.local"
E2E_PREFIX = "smartfit.e2e."
USERS = {  # role -> profile basics the app asks for later (the E2E test fills the rest in the app)
    "WOMAN": {"full_name": "Ayesha Test", "date_of_birth": "2000-05-14"},
    "MAN": {"full_name": "Bilal Test", "date_of_birth": "1998-09-02"},
}


def _password() -> str:
    """Meets the app's rules: 8+ chars, upper, lower, digit, special."""
    body = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(14))
    return f"Aa1!{body}"


def _read_env() -> dict[str, str]:
    if not ENV_FILE.exists():
        return {}
    out = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _write_env(values: dict[str, str]) -> None:
    ENV_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# Playwright E2E logins (gitignored). Test shoppers: made by backend/scripts/e2e_users.py.",
             "# Admin tests: put the admin panel login here yourself as E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD."]
    lines += [f"{k}={v}" for k, v in values.items()]
    ENV_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _headers() -> dict[str, str]:
    key = settings.supabase_service_key
    if not (settings.supabase_url and key):
        raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_KEY are not set in the backend .env")
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


async def create() -> None:
    env = _read_env()
    if any(k.startswith("E2E_WOMAN_ID") or k.startswith("E2E_MAN_ID") for k in env):
        raise SystemExit("Test users already exist (e2e/.env.local). Run `delete` first.")
    run = secrets.token_hex(3)
    async with httpx.AsyncClient(timeout=20) as client:
        for role, meta in USERS.items():
            email = f"{E2E_PREFIX}{role.lower()}.{run}@example.com"
            password = _password()
            res = await client.post(f"{settings.supabase_url.rstrip('/')}/auth/v1/admin/users", headers=_headers(),
                                    json={"email": email, "password": password, "email_confirm": True,
                                          "user_metadata": meta})
            if res.status_code not in (200, 201):
                raise SystemExit(f"creating the {role.lower()} test user failed: HTTP {res.status_code}")
            env |= {f"E2E_{role}_EMAIL": email, f"E2E_{role}_PASSWORD": password, f"E2E_{role}_ID": res.json()["id"]}
            print(f"created the {role.lower()} test user ({email})")
    _write_env(env)
    print(f"logins written to {ENV_FILE} (gitignored)")


async def delete() -> None:
    env = _read_env()
    async with httpx.AsyncClient(timeout=30) as client:
        for role in USERS:
            uid, email = env.get(f"E2E_{role}_ID"), env.get(f"E2E_{role}_EMAIL", "")
            if not uid:
                continue
            if not email.startswith(E2E_PREFIX):
                raise SystemExit(f"refusing to delete {role.lower()}: not an E2E test account")
            removed = await delete_user_completely(client, uid)
            print(f"deleted the {role.lower()} test user and its data (files removed: {sum(removed.values())})")
            for k in ("EMAIL", "PASSWORD", "ID"):
                env.pop(f"E2E_{role}_{k}", None)
    _write_env(env)


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action not in ("create", "delete"):
        raise SystemExit(__doc__)
    asyncio.run(create() if action == "create" else delete())
