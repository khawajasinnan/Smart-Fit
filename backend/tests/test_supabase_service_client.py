"""Service-role Supabase helpers: correct URLs/headers, errors mapped to the envelope."""

import asyncio
import json

import httpx
import pytest

from shared import supabase_client as sc
from shared.config import settings
from shared.schemas.errors import AppError


@pytest.fixture(autouse=True)
def _configured(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", "https://proj.supabase.co/")
    monkeypatch.setattr(settings, "supabase_service_key", "service-key")


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def test_missing_service_key_is_config_error(monkeypatch):
    monkeypatch.setattr(settings, "supabase_service_key", "")

    async def run():
        async with _client(lambda r: httpx.Response(200, json=[])) as c:
            await sc.service_select(c, "products", {})

    with pytest.raises(AppError) as err:
        asyncio.run(run())
    assert err.value.status_code == 503 and err.value.code == "CONFIG_MISSING"


def test_upload_then_signed_url():
    seen = []

    def handler(req: httpx.Request):
        seen.append(req)
        if "/object/sign/" in req.url.path:
            assert json.loads(req.content) == {"expiresIn": 600}
            return httpx.Response(200, json={"signedURL": "/object/sign/tryon-results/u1/a.jpg?token=t"})
        return httpx.Response(200, json={"Key": "tryon-results/u1/a.jpg"})

    async def run():
        async with _client(handler) as c:
            path = await sc.storage_upload(c, "tryon-results", "/u1/a.jpg", b"jpg", "image/jpeg")
            return await sc.storage_signed_url(c, "tryon-results", path, expires_in=600)

    url = asyncio.run(run())
    assert url == "https://proj.supabase.co/storage/v1/object/sign/tryon-results/u1/a.jpg?token=t"
    upload = seen[0]
    assert upload.url.path == "/storage/v1/object/tryon-results/u1/a.jpg"
    assert upload.headers["authorization"] == "Bearer service-key"
    assert upload.headers["x-upsert"] == "true"


def test_upsert_sends_merge_duplicates():
    def handler(req: httpx.Request):
        assert req.url.params["on_conflict"] == "product_id"
        assert "merge-duplicates" in req.headers["prefer"]
        assert json.loads(req.content) == [{"product_id": "p1"}]
        return httpx.Response(201)

    async def run():
        async with _client(handler) as c:
            await sc.service_upsert(c, "products", [{"product_id": "p1"}], on_conflict="product_id")

    asyncio.run(run())


def test_upstream_error_maps_to_502():
    async def run():
        async with _client(lambda r: httpx.Response(400, json={"message": "bad"})) as c:
            await sc.service_select(c, "products", {})

    with pytest.raises(AppError) as err:
        asyncio.run(run())
    assert err.value.status_code == 502


def test_llm_api_key_alias(monkeypatch):
    from shared.config import Settings

    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("LLM_API_KEY", "llm-key")
    assert Settings(_env_file=None).gemini_api_key == "llm-key"
