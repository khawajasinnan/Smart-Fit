"""Scraper catalog management for the admin panel (SFR-040), on a temporary
local snapshot store."""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from services.scraper import catalog_admin
from services.scraper.main import app
from shared.config import settings

NEW = {
    "retailer": "breakout", "product_url": "https://www.breakout.com.pk/products/test-tee-blk",
    "name": "TEST TEE", "image_url": "https://cdn.shopify.com/s/files/1/0202/test.jpg", "price": 1999,
    "sizes_in_stock": ["S", "M"], "category": "t-shirts", "tryon_category": "upper", "gender": "men",
}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_store", "snapshot")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    resyncs = []

    async def fake_resync():
        resyncs.append(1)

    monkeypatch.setattr(catalog_admin, "_resync", fake_resync)
    with TestClient(app) as c:
        c.resyncs = resyncs
        yield c


def test_add_list_edit_delete(client):
    res = client.post("/catalog/products", json=NEW)
    assert res.status_code == 201, res.text
    assert res.json()["product_id"] == "breakout:test-tee-blk" and res.json()["source"] == "admin"
    assert client.post("/catalog/products", json=NEW).status_code == 409

    listing = client.get("/catalog/products", params={"search": "test tee"}).json()
    assert listing["total"] == 1 and listing["by_retailer"]["breakout"] == 1

    edited = client.patch("/catalog/products/breakout:test-tee-blk", json={"price": 2499, "sizes_in_stock": ["L"]})
    assert edited.status_code == 200 and edited.json()["price"] == 2499 and edited.json()["sizes"] == ["L"]
    assert client.patch("/catalog/products/breakout:test-tee-blk", json={"price": -5}).status_code == 400

    assert client.delete("/catalog/products/breakout:test-tee-blk").status_code == 200
    assert client.delete("/catalog/products/breakout:test-tee-blk").status_code == 404
    assert client.get("/catalog/products").json()["total"] == 0
    assert len(client.resyncs) == 3  # add, edit, delete


def test_rejects_wrong_hosts(client):
    bad = NEW | {"product_url": "https://evil.example/products/x"}
    res = client.post("/catalog/products", json=bad)
    assert res.status_code == 400 and "product_url" in res.json()["error"]["message"]
    bad = NEW | {"image_url": "http://cdn.shopify.com/x.jpg"}
    assert client.post("/catalog/products", json=bad).status_code == 400


def test_csv_import_reports_row_problems(client):
    csv_text = (Path(__file__).resolve().parents[1] / "services/scraper/templates/manual_catalog_template.csv"
                ).read_text(encoding="utf-8")
    csv_text += ("GOOD TEE,https://www.breakout.com.pk/products/good-tee,https://cdn.shopify.com/a.jpg,,2999,"
                 "S|M,,t-shirts,upper,men,Black\n")
    res = client.post("/catalog/import-csv", json={"retailer": "breakout", "csv_text": csv_text})
    assert res.status_code == 200
    body = res.json()
    assert body["stored"] == 2 and body["stored_in"] == "snapshot"  # the template's example row is valid too
    assert client.post("/catalog/import-csv", json={"retailer": "outfitters", "csv_text": csv_text}).status_code == 422
