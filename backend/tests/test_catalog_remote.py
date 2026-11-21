"""Catalog refresh through the cloud runner (SCRAPER_BACKEND=modal,
services/scraper/modal_app.py) and the restart-safe refresh schedule.

Modal itself is replaced by a fake function: these tests check that a cloud
read is saved, validated and error-handled exactly like a local one, and that
no store is contacted from this machine."""

import asyncio
from datetime import UTC, datetime, timedelta

import httpx
import pytest

pytest.importorskip("protego")

from shared import catalog_store  # noqa: E402
from shared.config import settings  # noqa: E402
from shared.feed_brands import BY_KEY  # noqa: E402
from services.scraper import main as scraper_main  # noqa: E402
from services.scraper import remote  # noqa: E402
from services.scraper.catalog import parse_shopify_product  # noqa: E402
from services.scraper.catalog_service import refresh_feeds  # noqa: E402

NOW = datetime(2026, 11, 13, tzinfo=UTC)


def product_json(retailer="lulusar", handle="kurta"):
    item = {"id": 1, "handle": handle, "title": "Embroidered Lawn Kurta", "product_type": "Kurta", "tags": ["women"],
            "images": [{"src": "https://cdn.shopify.com/s/files/k.jpg"}],
            "variants": [{"option1": "M", "price": "4990.00", "available": True}],
            "options": [{"name": "Size", "values": ["M"]}]}
    p, _ = parse_shopify_product(item, BY_KEY[retailer], NOW)
    return p.model_dump(mode="json")


class FakeFunction:
    """Stands in for modal.Function.from_name(...): records calls, returns canned answers."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []
        fake = self

        class _Remote:
            async def aio(self, key, max_products, charts):
                fake.calls.append((key, max_products, charts))
                answer = fake.answers[key]
                if isinstance(answer, list):  # one answer per try
                    answer = answer.pop(0)
                if isinstance(answer, Exception):
                    raise answer
                return answer

        self.remote = _Remote()


@pytest.fixture
def cloud(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_store", "snapshot")
    monkeypatch.setattr(settings, "catalog_snapshot_path", str(tmp_path / "catalog.jsonl"))
    monkeypatch.setattr(settings, "scraper_backend", "modal")
    waits: list[float] = []

    async def no_wait(seconds):
        waits.append(seconds)

    monkeypatch.setattr(remote, "_sleep", no_wait)

    def install(answers):
        fn = FakeFunction(answers)
        monkeypatch.setattr(remote, "_function", lambda: fn)
        return fn

    return install


def no_network():
    def handler(req: httpx.Request):
        raise AssertionError(f"the store was contacted from this machine: {req.url}")

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def run_refresh(keys):
    async def go():
        async with no_network() as c:
            return await refresh_feeds(c, keys, 50, notify=False)

    return asyncio.run(go())


def test_cloud_read_is_saved_like_a_local_one(cloud):
    fn = cloud({"lulusar": {"ok": True, "products": [product_json()],
                            "stats": {"pages": 1, "seen": 3, "kept": 1, "skipped": {"kids_or_ungendered": 2}}}})
    result = run_refresh(["lulusar"])
    assert result.kept == {"lulusar": 1} and result.skipped["lulusar"] == {"kids_or_ungendered": 2}
    assert fn.calls[0][:2] == ("lulusar", 50)
    saved = asyncio.run(catalog_store.load_products(httpx.AsyncClient()))
    assert [p.product_id for p in saved] == ["lulusar:kurta"]


def test_invalid_or_foreign_products_from_the_cloud_are_dropped(cloud):
    bad = product_json() | {"price": -5}  # fails validation
    other_brand = product_json("saya", "shirt")  # not the brand that was asked for
    cloud({"lulusar": {"ok": True, "products": [product_json(), bad, other_brand], "stats": {}}})
    result = run_refresh(["lulusar"])
    assert result.kept == {"lulusar": 1} and result.skipped["lulusar"] == {"invalid": 1}


def test_rate_limit_in_the_cloud_stops_the_run(cloud):
    fn = cloud({"lulusar": {"ok": False, "kind": "rate_limited", "message": "still rate-limited after 1 waits"},
                "saya": {"ok": True, "products": [], "stats": {}}})
    result = run_refresh(["lulusar", "saya"])
    assert result.rate_limited and result.not_reached == ["saya"] and "rate-limited" in result.errors["lulusar"]
    assert [c[0] for c in fn.calls] == ["lulusar"]  # Saya is never asked


def test_robots_no_and_unreachable_cloud_are_reported_per_brand(cloud):
    cloud({"lulusar": {"ok": False, "kind": "robots", "message": "robots.txt disallows /products.json"},
           "saya": ConnectionError("modal down")})
    result = run_refresh(["lulusar", "saya"])
    assert "robots.txt forbids it" in result.errors["lulusar"]
    assert "cloud scraper not reachable" in result.errors["saya"] and not result.kept


def test_known_size_charts_are_sent_so_they_are_not_fetched_again(cloud):
    old = catalog_store  # the previous refresh's products, with a chart for lulusar:kurta
    with_chart = product_json() | {"size_chart_tag": "chart-a", "size_chart_raw": [["Size", "M"], ["Chest", "40"]]}
    asyncio.run(old.save_products(httpx.AsyncClient(), [old.ScrapedProduct.model_validate(with_chart)]))
    fn = cloud({"lulusar": {"ok": True, "products": [product_json()], "stats": {}}})
    run_refresh(["lulusar"])
    assert fn.calls[0][2] == [{"product_id": "lulusar:kurta", "size_chart_tag": "chart-a",
                               "size_chart_raw": [["Size", "M"], ["Chest", "40"]]}]


# ── the schedule survives restarts ───────────────────────────────────────────


def test_restart_waits_for_the_saved_schedule(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "catalog_refresh_state_path", str(tmp_path / "state.json"))
    monkeypatch.setattr(settings, "catalog_refresh_start_delay_seconds", 120.0)
    assert scraper_main.first_refresh_delay(NOW, scraper_main._saved_next_run()) == 120.0  # never run: soon
    scraper_main._save_next_run(NOW + timedelta(hours=5))
    assert scraper_main.first_refresh_delay(NOW, scraper_main._saved_next_run()) == 5 * 3600  # not before it's due
    scraper_main._save_next_run(NOW - timedelta(hours=1))
    assert scraper_main.first_refresh_delay(NOW, scraper_main._saved_next_run()) == 120.0  # overdue: soon


def test_a_damaged_schedule_file_is_ignored(tmp_path, monkeypatch):
    path = tmp_path / "state.json"
    path.write_text("{not json", encoding="utf-8")
    monkeypatch.setattr(settings, "catalog_refresh_state_path", str(path))
    assert scraper_main._saved_next_run() is None


class StreamTerminatedError(Exception):
    """Same name as Modal's: the connection dropped mid-call."""


class NotFoundError(Exception):
    """Same name as Modal's: the app isn't deployed."""


def test_a_dropped_connection_is_retried_and_the_brand_is_saved(cloud):
    fn = cloud({"lulusar": [StreamTerminatedError("stream reset"),
                            {"ok": True, "products": [product_json()], "stats": {"pages": 1, "seen": 1}}]})
    result = run_refresh(["lulusar"])
    assert result.kept == {"lulusar": 1} and not result.errors
    assert len(fn.calls) == 2


def test_three_dropped_connections_report_the_brand_and_keep_its_products(cloud):
    fn = cloud({"lulusar": [StreamTerminatedError("a"), StreamTerminatedError("b"), StreamTerminatedError("c")]})
    result = run_refresh(["lulusar"])
    assert "not reachable after 3 tries" in result.errors["lulusar"] and "previous products kept" in result.errors["lulusar"]
    assert len(fn.calls) == 3


def test_not_deployed_is_not_retried_and_says_how_to_fix_it(cloud):
    fn = cloud({"lulusar": NotFoundError("App smartfit-scraper not found")})
    result = run_refresh(["lulusar"])
    assert "modal deploy" in result.errors["lulusar"]
    assert len(fn.calls) == 1
