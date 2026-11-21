"""Gateway: proxying, JWT auth, RBAC, rate limiting, body-size limit.
All upstream calls go to an in-memory httpx MockTransport — no network."""

import json
import time

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import FastAPI
from fastapi.testclient import TestClient

from gateway import proxy
from gateway.main import BodySizeLimitMiddleware, app
from gateway.middleware import auth as auth_mod
from gateway.middleware.rate_limit import limiter
from shared.config import settings

SECRET = "test-jwt-secret-that-is-long-enough-for-hs256"
SUPABASE_URL = "https://example.supabase.co"


def make_token(sub="user-1", email="user@example.com", *, secret=SECRET, exp_in=3600, **extra):
    claims = {
        "sub": sub,
        "email": email,
        "role": "authenticated",
        "aud": "authenticated",
        "iss": f"{SUPABASE_URL}/auth/v1",
        "exp": int(time.time()) + exp_in,
        **extra,
    }
    return jwt.encode(claims, secret, algorithm="HS256")


def upstream_handler(request: httpx.Request) -> httpx.Response:
    if request.url.host == "dead-service":
        raise httpx.ConnectError("connection refused", request=request)
    if request.url.path == "/health":
        return httpx.Response(200, json={"status": "ok"})
    echo = {
        "path": request.url.path,
        "user": request.headers.get("x-user-id"),
        "body": json.loads(request.content or b"null"),
    }
    return httpx.Response(200, json=echo)


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_jwt_secret", SECRET)
    monkeypatch.setattr(settings, "auth_required", False)
    limiter.reset()
    with TestClient(app) as c:
        mock = httpx.AsyncClient(transport=httpx.MockTransport(upstream_handler))
        proxy.set_client(mock)
        auth_mod.init_verifier(mock)
        yield c


def test_health(client):
    assert client.get("/health").json() == {"status": "ok", "service": "gateway"}


def test_legacy_recommend_path_is_forwarded_with_body(client):
    res = client.post("/api/v1/scrape/recommend", json={"user_message": "kurta"})
    assert res.status_code == 200
    assert res.json() == {"path": "/recommend/app", "user": None, "body": {"user_message": "kurta"}}


def test_cv_and_chat_paths_route_to_their_services(client):
    assert client.post("/api/v1/cv/analyze", json={}).json()["path"] == "/analyze/app"
    assert client.post("/api/v1/chat", json={}).json()["path"] == "/chat"


def test_valid_token_forwards_user_id(client):
    res = client.post("/api/v1/chat", json={}, headers={"Authorization": f"Bearer {make_token()}"})
    assert res.json()["user"] == "user-1"


def test_invalid_or_expired_token_is_rejected_even_when_auth_optional(client):
    for token in (make_token(secret="wrong-secret-wrong-secret-wrong-secret!!"), make_token(exp_in=-3600), "garbage"):
        res = client.post("/api/v1/chat", json={}, headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 401
        assert res.json()["error"]["code"] == "UNAUTHORIZED"


def test_auth_required_blocks_anonymous(client, monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True)
    res = client.post("/api/v1/chat", json={})
    assert res.status_code == 401
    assert res.json()["error"]["message"] == "Please log in to continue."


def test_auth_me(client):
    assert client.get("/api/v1/auth/me").status_code == 401
    res = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {make_token()}"})
    assert res.json() == {"id": "user-1", "email": "user@example.com", "role": "authenticated", "is_admin": False}


def test_es256_token_verified_via_jwks(client, monkeypatch):
    monkeypatch.setattr(settings, "supabase_jwt_secret", "")
    private_key = ec.generate_private_key(ec.SECP256R1())

    class FakeJwks:
        def get_signing_key_from_jwt(self, _token):
            return type("Key", (), {"key": private_key.public_key()})()

    monkeypatch.setattr(auth_mod._verifier, "_jwks", FakeJwks())
    claims = {
        "sub": "es-user",
        "aud": "authenticated",
        "iss": f"{SUPABASE_URL}/auth/v1",
        "exp": int(time.time()) + 600,
    }
    token = jwt.encode(claims, private_key, algorithm="ES256", headers={"kid": "k1"})
    res = client.post("/api/v1/chat", json={}, headers={"Authorization": f"Bearer {token}"})
    assert res.json()["user"] == "es-user"


def test_admin_route_requires_admin(client):
    user = {"Authorization": f"Bearer {make_token()}"}
    admin = {"Authorization": f"Bearer {make_token(sub='admin-1', email='admin@smartfit.pk')}"}
    assert client.get("/api/v1/admin/services").status_code == 401
    forbidden = client.get("/api/v1/admin/services", headers=user)
    assert forbidden.status_code == 403
    assert forbidden.json()["error"]["code"] == "FORBIDDEN"
    ok = client.get("/api/v1/admin/services", headers=admin)
    assert ok.status_code == 200
    assert ok.json()["gateway"] == {"up": True}


def test_rate_limit_returns_429_with_retry_after(client, monkeypatch):
    monkeypatch.setattr(settings, "rate_limit_chat_per_min", 2)
    headers = {"Authorization": f"Bearer {make_token(sub='rate-user')}"}
    assert client.post("/api/v1/chat", json={}, headers=headers).status_code == 200
    assert client.post("/api/v1/chat", json={}, headers=headers).status_code == 200
    res = client.post("/api/v1/chat", json={}, headers=headers)
    assert res.status_code == 429
    assert res.json()["error"]["code"] == "RATE_LIMITED"
    assert int(res.headers["retry-after"]) >= 1


def test_unreachable_service_gives_503_envelope(client, monkeypatch):
    monkeypatch.setattr(settings, "tryon_url", "http://dead-service:8005")
    res = client.post("/api/v1/tryon", json={}, headers={"Authorization": f"Bearer {make_token()}"})
    assert res.status_code == 503
    assert res.json()["error"]["code"] == "SERVICE_UNAVAILABLE"


def test_tryon_requires_login_even_when_auth_is_optional(client):
    # Results are private to their owner, so try-on never runs anonymously.
    for res in (client.post("/api/v1/tryon", json={}), client.get("/api/v1/tryon/job-1"),
                client.post("/api/v1/tryon/sign", json={"paths": ["x"]})):
        assert res.status_code == 401


def test_tryon_routes_forward_the_user(client):
    headers = {"Authorization": f"Bearer {make_token(sub='tryon-user')}"}
    assert client.post("/api/v1/tryon", json={"a": 1}, headers=headers).json() == {
        "path": "/tryon", "user": "tryon-user", "body": {"a": 1}}
    assert client.get("/api/v1/tryon/job-1", headers=headers).json()["path"] == "/tryon/job-1"
    assert client.post("/api/v1/tryon/sign", json={}, headers=headers).json()["path"] == "/tryon/sign"


def test_starting_tryons_has_its_own_tight_rate_limit(client, monkeypatch):
    monkeypatch.setattr(settings, "rate_limit_tryon_per_min", 1)
    headers = {"Authorization": f"Bearer {make_token(sub='gpu-user')}"}
    assert client.post("/api/v1/tryon", json={}, headers=headers).status_code == 200
    assert client.post("/api/v1/tryon", json={}, headers=headers).status_code == 429
    # polling isn't limited by the start limit
    assert client.get("/api/v1/tryon/job-1", headers=headers).status_code == 200


def test_hairstyle_routes_need_login_and_forward_the_user(client):
    # Face photos: never anonymous.
    assert client.post("/api/v1/hairstyles", json={}).status_code == 401
    assert client.post("/api/v1/hairstyles/face-check", json={}).status_code == 401
    headers = {"Authorization": f"Bearer {make_token(sub='hair-user')}"}
    assert client.post("/api/v1/hairstyles", json={"a": 1}, headers=headers).json() == {
        "path": "/hairstyles", "user": "hair-user", "body": {"a": 1}}
    assert client.post("/api/v1/hairstyles/face-check", json={}, headers=headers).json()["path"] == "/hairstyles/face-check"


def test_camera_face_checks_have_their_own_higher_limit(client, monkeypatch):
    monkeypatch.setattr(settings, "rate_limit_hairstyle_per_min", 1)
    monkeypatch.setattr(settings, "rate_limit_face_check_per_min", 3)
    headers = {"Authorization": f"Bearer {make_token(sub='camera-user')}"}
    assert [client.post("/api/v1/hairstyles/face-check", json={}, headers=headers).status_code
            for _ in range(4)] == [200, 200, 200, 429]
    assert client.post("/api/v1/hairstyles", json={}, headers=headers).status_code == 200  # separate limit
    assert client.post("/api/v1/hairstyles", json={}, headers=headers).status_code == 429


def test_body_size_limit():
    small = FastAPI()

    @small.post("/x")
    async def x():
        return {"ok": True}

    small.add_middleware(BodySizeLimitMiddleware, max_bytes=10)
    c = TestClient(small)
    assert c.post("/x", content=b"12345").status_code == 200
    res = c.post("/x", content=b"x" * 50)
    assert res.status_code == 413
    assert res.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"
