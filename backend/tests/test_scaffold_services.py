"""The shared error handlers produce the uniform envelope. (Every service is
implemented now: scoring is tested in tests/test_look_scoring.py, try-on and
hairstyle in their own test files.)"""

from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import BaseModel

from shared.service_app import create_service_app


class _Item(BaseModel):
    budget: int


def _demo_app():
    app = create_service_app("demo", "Demo", "demo")

    @app.post("/items")
    async def create(item: _Item):
        return item

    @app.get("/boom")
    async def boom():
        raise RuntimeError("database password is hunter2")

    @app.get("/missing")
    async def missing():
        raise HTTPException(status_code=404, detail="Product not found.")

    return app


def test_validation_error_envelope():
    res = TestClient(_demo_app()).post("/items", json={"budget": "abc"})
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"
    assert res.json()["error"]["details"]["errors"][0]["field"] == "budget"


def test_unhandled_error_never_leaks_internals():
    res = TestClient(_demo_app(), raise_server_exceptions=False).get("/boom")
    assert res.status_code == 500
    assert res.json() == {"error": {"code": "INTERNAL_ERROR", "message": "Something went wrong on our side. Please try again."}}
    assert "hunter2" not in res.text


def test_http_exception_envelope():
    res = TestClient(_demo_app()).get("/missing")
    assert res.status_code == 404
    assert res.json() == {"error": {"code": "NOT_FOUND", "message": "Product not found."}}
