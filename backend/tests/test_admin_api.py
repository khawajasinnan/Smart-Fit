"""Admin API (SFR-039..042) and account deletion (SFR-008) against an in-memory
Supabase stand-in (httpx MockTransport): no network, no real database."""

import json
from datetime import UTC, datetime

import httpx
import pytest
from fastapi.testclient import TestClient

from gateway import admin_data as ad
from gateway import proxy
from gateway.main import app
from gateway.middleware import auth as auth_mod
from gateway.middleware.rate_limit import limiter
from shared.config import settings
from tests.test_gateway import SECRET, SUPABASE_URL, make_token

ADMIN_ID = "00000000-0000-0000-0000-0000000000aa"
USER_ID = "11111111-1111-1111-1111-111111111111"
NOW = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)


# ── pure helpers ────────────────────────────────────────────────────────────


def test_user_status_precedence():
    assert ad.user_status({"is_banned": True, "deactivated_at": "x"}, NOW) == "banned"
    assert ad.user_status({"suspended_until": "2026-10-30T00:00:00Z", "profile_completed": True}, NOW) == "suspended"
    assert ad.user_status({"suspended_until": "2026-10-01T00:00:00Z", "profile_completed": True}, NOW) == "active"
    assert ad.user_status({"deactivated_at": "2026-10-20T00:00:00Z", "profile_completed": True}, NOW) == "deactivated"
    assert ad.user_status({"profile_completed": False}, NOW) == "incomplete"


def test_search_is_sanitised_for_postgrest_filters():
    assert ad.clean_search("ali),(role.eq.admin") == "alirole.eq.admin"
    f = ad.user_filters("sara@x.com", "all", NOW)
    assert f == {"or": "(email.ilike.*sara@x.com*,full_name.ilike.*sara@x.com*,username.ilike.*sara@x.com*)"}
    assert ad.user_filters("", "banned", NOW) == {"is_banned": "is.true"}
    assert "+" not in ad.user_filters("", "active", NOW)["and"]  # '+' would be read as a space


def test_daily_series_zero_fills_and_ignores_old_rows():
    rows = ["2026-10-24T08:00:00Z", "2026-10-24T09:00:00+00:00", "2026-10-22T23:59:00Z", "2026-09-01T00:00:00Z", None]
    series = ad.daily_series(rows, 3, NOW)
    assert series == [{"date": "2026-10-22", "count": 1}, {"date": "2026-10-23", "count": 0},
                      {"date": "2026-10-24", "count": 2}]


def test_top_counts_and_percentiles():
    assert ad.top_counts(["a", "b", "a", "", "a", "b", "c"], 2) == [{"id": "a", "count": 3}, {"id": "b", "count": 2}]
    assert ad.percentile([], 50) is None
    assert ad.percentile([120], 95) == 120.0
    assert ad.percentile([100, 200, 300], 50) == 200.0


# ── a fake Supabase ─────────────────────────────────────────────────────────


class FakeSupabase:
    def __init__(self):
        self.profiles = {
            USER_ID: {"id": USER_ID, "email": "user@example.com", "full_name": "Sara", "profile_completed": True,
                      "is_banned": False, "suspended_until": None, "deactivated_at": None},
        }
        self.files = {"avatars": [f"{USER_ID}/avatar.jpg"], "chat-images": [f"{USER_ID}/s1/a.jpg", f"{USER_ID}/s1/b.jpg"]}
        self.removed: dict[str, list[str]] = {}
        self.deleted_users: list[str] = []
        self.calls: list[str] = []

    def __call__(self, req: httpx.Request) -> httpx.Response:
        path = req.url.path
        self.calls.append(f"{req.method} {path}")
        if path.startswith("/storage/v1/object/list/"):
            bucket = path.rsplit("/", 1)[1]
            prefix = json.loads(req.content)["prefix"]
            names = set()
            out = []
            for f in self.files.get(bucket, []):
                if f.startswith(prefix + "/"):
                    rest = f[len(prefix) + 1:]
                    head = rest.split("/", 1)[0]
                    if head in names:
                        continue
                    names.add(head)
                    out.append({"name": head, "id": None if "/" in rest else "obj"})
            return httpx.Response(200, json=out)
        if path.startswith("/storage/v1/object/") and req.method == "DELETE":
            bucket = path.rsplit("/", 1)[1]
            self.removed.setdefault(bucket, []).extend(json.loads(req.content)["prefixes"])
            return httpx.Response(200, json=[])
        if path.startswith("/auth/v1/admin/users/") and req.method == "DELETE":
            uid = path.rsplit("/", 1)[1]
            self.deleted_users.append(uid)
            self.profiles.pop(uid, None)
            return httpx.Response(200, json={})
        if path == "/rest/v1/profiles":
            uid = (req.url.params.get("id") or "").removeprefix("eq.")
            rows = [self.profiles[uid]] if uid in self.profiles else ([] if uid else list(self.profiles.values()))
            if req.method == "PATCH":
                for row in rows:
                    row.update(json.loads(req.content))
            if "count=exact" in req.headers.get("prefer", ""):
                return httpx.Response(200, json=rows[:1], headers={"content-range": f"0-0/{len(rows)}"})
            return httpx.Response(200, json=rows)
        if path.startswith("/rest/v1/"):
            if "count=exact" in req.headers.get("prefer", ""):
                return httpx.Response(200, json=[], headers={"content-range": "*/0"})
            return httpx.Response(200, json=[])
        return httpx.Response(404, json={"message": "not found"})


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_service_key", "service-key")
    monkeypatch.setattr(settings, "supabase_jwt_secret", SECRET)
    monkeypatch.setattr(settings, "auth_required", False)
    limiter.reset()
    fake = FakeSupabase()
    with TestClient(app) as c:
        mock = httpx.AsyncClient(transport=httpx.MockTransport(fake))
        proxy.set_client(mock)
        auth_mod.init_verifier(mock)
        yield c, fake


def _headers(sub, email):
    return {"Authorization": f"Bearer {make_token(sub=sub, email=email)}"}


USER = _headers(USER_ID, "user@example.com")
ADMIN = _headers(ADMIN_ID, "admin@smartfit.pk")


# ── SFR-008: delete my account ──────────────────────────────────────────────


def test_delete_account_needs_typed_confirmation(api):
    c, fake = api
    res = c.request("DELETE", "/api/v1/account", json={"confirm": "yes"}, headers=USER)
    assert res.status_code == 400 and res.json()["error"]["code"] == "CONFIRMATION_REQUIRED"
    assert fake.deleted_users == []


def test_delete_account_removes_files_in_nested_folders_then_the_user(api):
    c, fake = api
    res = c.request("DELETE", "/api/v1/account", json={"confirm": "DELETE"}, headers=USER)
    assert res.status_code == 200, res.text
    assert res.json()["files_removed"]["avatars"] == 1 and res.json()["files_removed"]["chat-images"] == 2
    assert sorted(fake.removed["chat-images"]) == [f"{USER_ID}/s1/a.jpg", f"{USER_ID}/s1/b.jpg"]
    assert fake.deleted_users == [USER_ID]
    first_auth_delete = next(i for i, call in enumerate(fake.calls) if call.startswith("DELETE /auth"))
    assert all(not call.startswith("DELETE /storage") for call in fake.calls[first_auth_delete:])  # files first


def test_delete_account_requires_sign_in(api):
    c, _ = api
    assert c.request("DELETE", "/api/v1/account", json={"confirm": "DELETE"}).status_code == 401


# ── SFR-039: admin user management ──────────────────────────────────────────


def test_admin_routes_reject_normal_users(api):
    c, _ = api
    for method, path in [("GET", "/api/v1/admin/users"), ("GET", "/api/v1/admin/analytics"),
                         ("DELETE", f"/api/v1/admin/users/{USER_ID}"), ("GET", "/api/v1/admin/feedback")]:
        assert c.request(method, path, headers=USER).status_code == 403


def test_admin_lists_with_status_and_total(api):
    c, _ = api
    res = c.get("/api/v1/admin/users", headers=ADMIN)
    assert res.status_code == 200
    body = res.json()
    assert body["total"] == 1 and body["items"][0]["status"] == "active"


def test_admin_suspend_unsuspend_ban_and_guards(api):
    c, fake = api
    res = c.post(f"/api/v1/admin/users/{USER_ID}/suspend", json={"days": 3, "reason": "spam"}, headers=ADMIN)
    assert res.status_code == 200 and res.json()["status"] == "suspended"
    assert fake.profiles[USER_ID]["suspension_reason"] == "spam"
    assert c.post(f"/api/v1/admin/users/{USER_ID}/unsuspend", headers=ADMIN).json()["status"] == "active"
    assert c.post(f"/api/v1/admin/users/{USER_ID}/ban", json={}, headers=ADMIN).json()["status"] == "banned"
    assert fake.profiles[USER_ID]["ban_reason"] == "Policy violation"
    assert c.post(f"/api/v1/admin/users/{USER_ID}/unban", headers=ADMIN).json()["status"] == "active"
    # not yourself, not a bad id, not a missing user
    assert c.post(f"/api/v1/admin/users/{ADMIN_ID}/ban", json={}, headers=ADMIN).status_code == 400
    assert c.post("/api/v1/admin/users/not-a-uuid/ban", json={}, headers=ADMIN).status_code == 400
    missing = "22222222-2222-2222-2222-222222222222"
    assert c.post(f"/api/v1/admin/users/{missing}/ban", json={}, headers=ADMIN).status_code == 404
    assert c.post(f"/api/v1/admin/users/{USER_ID}/suspend", json={"days": 0}, headers=ADMIN).status_code == 422


def test_admin_permanent_delete(api):
    c, fake = api
    assert c.delete(f"/api/v1/admin/users/{ADMIN_ID}", headers=ADMIN).status_code == 400
    res = c.delete(f"/api/v1/admin/users/{USER_ID}", headers=ADMIN)
    assert res.status_code == 200 and fake.deleted_users == [USER_ID]
    assert c.delete(f"/api/v1/admin/users/{USER_ID}", headers=ADMIN).status_code == 404


def test_admin_analytics_shape(api):
    c, _ = api
    res = c.get("/api/v1/admin/analytics?days=7", headers=ADMIN)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["users"]["total"] == 1 and len(body["sessions"]["per_day"]) == 7
    assert {"requests", "top_products", "latency_ms_p50"} <= set(body["recommendations"])
    assert "gateway" in body["services"]


def test_admin_ml_status_is_admin_only_and_never_fails(api):
    """Self-learning status (spec §23.26); a service that is down shows as down."""
    c, _ = api
    assert c.get("/api/v1/admin/ml", headers=USER).status_code == 403
    res = c.get("/api/v1/admin/ml", headers=ADMIN)
    assert res.status_code == 200 and set(res.json()) == {"recommendation", "scoring"}
