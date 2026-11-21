"""Try-on service (SFR-026..028): the job API, the SFR-027 "unavailable" cases,
photo validation, caching, privacy between users, and the image framing.

Runs in TEST MODE (MockRunner) with the catalog, the store's product photo and
Supabase Storage replaced by in-memory fakes, so no GPU, network or database
is touched. The real GPU path (modal_app.py) is checked on Modal itself."""

from __future__ import annotations

import base64
import io
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import services.tryon.main as tryon
from services.tryon import gpu_runner, imaging
from services.tryon.gpu_runner import ViewOutcome
from shared.config import settings
from shared.schemas.catalog import ScrapedProduct
from shared.schemas.errors import AppError

USER = {"x-user-id": "user-a"}
OTHER = {"x-user-id": "user-b"}


def product(pid="outfitters:tee", slot="upper", name="Relaxed Fit Hoodie - F0123/24"):
    return ScrapedProduct(product_id=pid, retailer="outfitters", name=name,
                          product_url="https://outfitters.com.pk/products/tee", image_url="https://cdn.example/tee.jpg",
                          image_urls=["https://cdn.example/model.jpg"], price=4990, sizes=["M"], category="hoodies",
                          tryon_category=slot, gender="men", colors=["Black"], source="shopify_feed",
                          scraped_at=datetime(2026, 11, 8, tzinfo=UTC))


def photo_b64(size=(900, 1200), colour=(120, 140, 160), fmt="JPEG") -> str:
    buf = io.BytesIO()
    Image.new("RGB", size, colour).save(buf, fmt)
    return base64.b64encode(buf.getvalue()).decode()


def flatlay() -> Image.Image:
    img = Image.new("RGB", (600, 800), (250, 250, 250))
    img.paste((20, 20, 30), (150, 150, 450, 650))  # a dark garment on white
    return img


env_state: dict = {}  # the env fixture's fakes, for tests that change them


@pytest.fixture
def env(monkeypatch):
    store: dict[str, bytes] = {}
    catalog = {"outfitters:tee": product(), "outfitters:fabric": product("outfitters:fabric", None),
               "outfitters:dress": product("outfitters:dress", "dress", "Printed Lawn Frock")}
    fetched: list[str] = []

    async def get_product(_client, pid):
        return catalog.get(pid)

    # the scraper's store re-check for products missing from the catalog (default: gone)
    store_answers: dict[str, dict] = {}
    rechecked: list[str] = []

    async def recheck(pid):
        rechecked.append(pid)
        return store_answers.get(pid, {"status": "gone", "product": None})

    photos: dict[str, Image.Image] = {}  # url -> the store's photo (default: a flat-lay)

    async def fetch_image(url):
        fetched.append(url)
        return photos.get(url, flatlay())

    async def upload(_client, bucket, path, data, content_type):
        assert bucket == "tryon-results" and content_type == "image/jpeg"
        store[path] = data
        return path

    async def signed(_client, bucket, path, expires_in=None):
        if path not in store:
            raise AppError(502, "UPSTREAM_ERROR", "Object not found")
        return f"https://signed.example/{bucket}/{path}?token=t"

    body_cm = {"chest_cm": 96.0, "waist_cm": 82.0, "hip_cm": 98.0}  # the user's profile measurements
    # clothing, no clear kind: passes for any chosen kind (tests set clear answers themselves)
    clothes = {"scores": {"upper": 0.34, "lower": 0.33, "dress": 0.31, "other": 0.02}}

    async def body_measurements(user_id):
        return None if body_cm.get("unreadable") else dict(body_cm)

    estimated: dict = {"size": None}  # the user's standard size from the profile (default: unknown)

    async def estimated_size(user_id):
        return estimated["size"]

    async def classify(_jpeg):
        return clothes["scores"]

    persons: dict = {"verdicts": {}, "calls": []}  # angle -> HRNet verdict (default: ok)

    async def person_verdict(angle, _jpeg, category):
        persons["calls"].append((angle, category))
        return persons["verdicts"].get(angle, {"ok": True})

    monkeypatch.setattr(tryon, "_body_measurements", body_measurements)
    monkeypatch.setattr(tryon, "_estimated_size", estimated_size)
    monkeypatch.setattr(tryon, "_classify_garment", classify)
    monkeypatch.setattr(tryon, "_person_verdict", person_verdict)
    monkeypatch.setattr(tryon.catalog_store, "get_product", get_product)
    monkeypatch.setattr(tryon, "_recheck_at_store", recheck)
    wears: dict = {"value": "men"}  # the test user's profile gender (product() is menswear)

    async def profile_wears(user_id):
        return wears["value"]

    monkeypatch.setattr(tryon, "_profile_wears", profile_wears)
    # the gender models' answers per kind ("garment" / "face"); None = not sure
    genders: dict = {"garment": None, "face": None, "calls": [], "face_photo": None}

    async def gender_verdict(jpeg, kind, photo=None):
        genders["calls"].append(kind)
        if kind == "face":
            genders["face_photo"] = photo  # the whole front photo, sent as a second opinion
        return genders[kind]

    monkeypatch.setattr(tryon, "_gender_verdict", gender_verdict)
    monkeypatch.setattr(tryon, "_fetch_image", fetch_image)
    # the sleeve length the recommendation service sees in a garment photo (default: not sure)
    sleeve_seen: dict = {"value": None, "calls": 0}

    async def garment_sleeve(_jpeg):
        sleeve_seen["calls"] += 1
        return sleeve_seen["value"]

    monkeypatch.setattr(tryon, "_garment_sleeve", garment_sleeve)
    # people the CV service sees in each product photo, in fetch order (default: nobody)
    people_in_photos: list[int | None] = []
    people_checked: list[int] = []  # one entry per photo checked for people

    async def people_in_photo(_img):
        people_checked.append(1)
        return people_in_photos.pop(0) if people_in_photos else 0

    monkeypatch.setattr(tryon, "_people_in_photo", people_in_photo)
    monkeypatch.setattr(tryon, "storage_upload", upload)
    monkeypatch.setattr(tryon, "storage_signed_url", signed)
    monkeypatch.setattr(settings, "tryon_backend", "mock")
    monkeypatch.setattr(settings, "tryon_mock_delay_seconds", 0.0)
    monkeypatch.setattr(settings, "lora_weights_enabled", True)
    monkeypatch.setattr(settings, "tryon_lora_categories", "upper,lower,dress")
    monkeypatch.setattr(settings, "max_concurrent_tryon_jobs", 5)
    tryon._jobs.clear()
    tryon._known_results.clear()
    gpu_runner.reset_runner()
    env_state.update(body=body_cm, clothes=clothes, catalog=catalog, persons=persons,
                     store_answers=store_answers, rechecked=rechecked, wears=wears, genders=genders,
                     people_in_photos=people_in_photos, people_checked=people_checked, sleeve=sleeve_seen,
                     estimated=estimated, photos=photos)
    with TestClient(tryon.app) as client:
        yield client, store, fetched
    tryon._jobs.clear()
    tryon._known_results.clear()
    gpu_runner.reset_runner()


def body(pid="outfitters:tee", angles=("front",), **extra):
    return {"product_id": pid, "views": [{"angle": a, "image_base64": photo_b64(colour=(10 * i, 90, 160))}
                                         for i, a in enumerate(angles)], **extra}


# ── SFR-026: the job ─────────────────────────────────────────────────────────


def test_four_view_job_runs_and_returns_private_signed_images(env):
    client, store, _ = env
    res = client.post("/tryon", json=body(angles=("left", "front", "back", "right")), headers=USER)
    assert res.status_code == 202
    job = res.json()
    assert job["status"] == "running" and job["mode"] == "mock"
    assert job["model_version"] == "idm-vton+dresscode-v1"
    assert [v["angle"] for v in job["views"]] == ["front", "right", "back", "left"]  # turntable order

    done = client.get(f"/tryon/{job['job_id']}", headers=USER).json()
    assert done["status"] == "done"
    for view in done["views"]:
        assert view["status"] == "done"
        assert view["storage_path"].startswith("user-a/")  # the user's own folder
        assert view["image_url"].startswith("https://signed.example/tryon-results/user-a/")
    assert len(store) == 4
    out = Image.open(io.BytesIO(next(iter(store.values()))))
    assert out.size == (768, 1024)  # >= 720p-equivalent (SRDS §4.1)


def test_same_photo_and_product_is_reused_not_regenerated(env):
    client, store, _ = env
    first = client.post("/tryon", json=body(), headers=USER).json()
    client.get(f"/tryon/{first['job_id']}", headers=USER)
    tryon._known_results.clear()  # even after a restart: found in Storage
    again = client.post("/tryon", json=body(), headers=USER).json()
    assert again["status"] == "done" and again["views"][0]["cached"] is True
    assert len(store) == 1


def test_lora_is_switchable_per_category(env, monkeypatch):
    client, _, _ = env
    monkeypatch.setattr(settings, "tryon_lora_categories", "upper")
    assert client.post("/tryon", json=body("outfitters:dress"), headers=USER).json()["model_version"] == "idm-vton"


def test_flat_lay_product_photo_is_preferred(env):
    client, _, fetched = env
    client.post("/tryon", json=body(), headers=USER)
    # the candidates are downloaded together; the first was already a flat-lay, so the choice stops there
    assert sorted(fetched) == ["https://cdn.example/model.jpg", "https://cdn.example/tee.jpg"]
    assert len(env_state["people_checked"]) == 1


def test_a_model_on_a_plain_background_is_not_taken_for_the_flat_lay(env):
    """20 Nov 2026: Outfitters' first photo (a model in the tee and trousers, plain
    background) was used as the tee's flat-lay; the real flat-lay came later."""
    client, _, fetched = env
    env_state["people_in_photos"].extend([1, 0])  # photo 1: a model; photo 2: just the garment
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202
    assert len(env_state["people_checked"]) == 2 and env_state["people_in_photos"] == []  # photo 2 chosen


def test_with_no_flat_lay_the_main_photo_is_used(env):
    client, _, fetched = env
    env_state["people_in_photos"].extend([1, 1])  # every photo shows a model
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202
    assert fetched == ["https://cdn.example/tee.jpg", "https://cdn.example/model.jpg"]
    assert env_state["people_in_photos"] == []


def test_people_count_unknown_keeps_the_background_test(env):
    client, _, fetched = env
    env_state["people_in_photos"].append(None)  # CV service down: as before
    client.post("/tryon", json=body(), headers=USER)
    assert len(env_state["people_checked"]) == 1  # the first photo was taken on the background test alone


def faint_flatlay() -> Image.Image:
    """A white garment on a pale grey studio backdrop (Outfitters' flat-lays): too faint for the flat-lay test."""
    img = Image.new("RGB", (600, 800), (226, 230, 233))
    img.paste((246, 247, 248), (150, 150, 450, 650))
    return img


def closeup() -> Image.Image:
    """A detail shot: the garment fills the frame and runs off its edges."""
    img = Image.new("RGB", (600, 800), (240, 240, 240))
    img.paste((30, 40, 120), (0, 100, 600, 800))
    return img


def picked(env) -> str:
    """The product photo the try-on would use for the test product."""
    import asyncio

    return asyncio.run(tryon._garment(product()))[1]


MAIN, SECOND = "https://cdn.example/tee.jpg", "https://cdn.example/model.jpg"


def test_the_photo_tests_tell_a_faint_flat_lay_from_the_rest():
    assert not imaging.looks_like_flatlay(faint_flatlay()) and imaging.plain_backdrop(faint_flatlay())
    assert imaging.looks_like_flatlay(flatlay()) and imaging.plain_backdrop(flatlay())
    assert not imaging.plain_backdrop(closeup())  # runs off the edges
    dark = Image.new("RGB", (600, 800), (40, 40, 40))
    dark.paste((240, 240, 240), (150, 150, 450, 650))
    assert not imaging.plain_backdrop(dark)  # a dark backdrop isn't a studio product shot


def test_a_white_garment_on_grey_is_used_instead_of_the_model_photo(env):
    """20 Nov 2026 (E2E run): a white cropped shirt's flat-lay on pale grey failed the flat-lay
    test, the main photo (a model in the shirt and jeans) was used, and the try-on came
    out with dark long sleeves under the shirt's short ones."""
    env_state["photos"][SECOND] = faint_flatlay()
    env_state["people_in_photos"].extend([1, 0])  # main photo: a model; the faint one: nobody
    assert picked(env) == SECOND


def test_a_faint_photo_needs_the_cv_service_to_say_it_is_empty(env):
    env_state["photos"][SECOND] = faint_flatlay()
    env_state["people_in_photos"].extend([1, None])  # can't tell: a model on grey looks the same
    assert picked(env) == MAIN


def test_a_faint_photo_with_a_person_is_not_used(env):
    env_state["photos"][SECOND] = faint_flatlay()
    env_state["people_in_photos"].extend([1, 1])
    assert picked(env) == MAIN


def test_a_real_flat_lay_still_wins_over_an_earlier_faint_one(env):
    env_state["photos"][MAIN] = faint_flatlay()  # first, but faint
    assert picked(env) == SECOND  # the clear flat-lay (nobody in it) comes first in preference
    assert len(env_state["people_checked"]) == 1  # the faint one never needed a check


def test_a_close_up_is_never_taken_for_the_garment(env):
    env_state["photos"][SECOND] = closeup()
    env_state["people_in_photos"].extend([1])  # main photo: a model; the close-up isn't even checked
    assert picked(env) == MAIN
    assert len(env_state["people_checked"]) == 1


# ── the user's own clothes photo ─────────────────────────────────────────────


def own(category="lower", name="Blue denim jeans 501", angles=("front",), garment_image=None, chest=55.0, waist=44.0):
    # flat widths: chest 55 -> 110 cm around (body 96), waist 44 -> 88 cm (body 82): fits
    return {"garment": {"image_base64": garment_image or photo_b64(size=(500, 600), colour=(30, 60, 140)),
                        "category": category, "name": name, "chest_width_cm": chest, "waist_width_cm": waist},
            "views": [{"angle": a, "image_base64": photo_b64(colour=(10 * i, 90, 160))} for i, a in enumerate(angles)]}


def test_own_clothes_photo_is_tried_on_without_the_catalog(env, monkeypatch):
    client, store, fetched = env
    runner = gpu_runner.get_runner()
    sent = []
    real_submit = runner.submit
    monkeypatch.setattr(runner, "submit", lambda task: sent.append(task) or real_submit(task))
    res = client.post("/tryon", json=own(angles=("front", "back")), headers=USER)
    assert res.status_code == 202
    job = res.json()
    assert job["product_id"].startswith("custom:") and job["category"] == "lower"
    assert fetched == []  # no store photo is downloaded
    assert {t.category for t in sent} == {"lower_body"} and sent[0].caption == "blue denim jeans"
    garment = Image.open(io.BytesIO(sent[0].garment_jpeg))
    assert garment.size == (768, 1024)
    done = client.get(f"/tryon/{job['job_id']}", headers=USER).json()
    assert done["status"] == "done" and len(store) == 2  # only the results are stored, never the garment photo


def test_own_clothes_without_a_name_uses_the_category_word(env, monkeypatch):
    client, _, _ = env
    runner = gpu_runner.get_runner()
    sent = []
    monkeypatch.setattr(runner, "submit", lambda task: sent.append(task) or "call-1")
    assert client.post("/tryon", json=own(category="dress", name=None), headers=USER).status_code == 202
    assert sent[0].caption == "dress" and sent[0].category == "dresses"


def test_same_own_clothes_photo_is_reused(env):
    client, store, _ = env
    image = photo_b64(size=(500, 600), colour=(200, 20, 20))
    first = client.post("/tryon", json=own(garment_image=image), headers=USER).json()
    client.get(f"/tryon/{first['job_id']}", headers=USER)
    again = client.post("/tryon", json=own(garment_image=image), headers=USER).json()
    assert again["views"][0]["cached"] is True and len(store) == 1
    other = client.post("/tryon", json=own(garment_image=photo_b64(size=(500, 600), colour=(20, 200, 20))),
                        headers=USER).json()
    assert other["views"][0]["cached"] is False  # a different garment is a new try-on


def test_bad_own_clothes_photo_is_named_as_the_garment(env):
    client, _, _ = env
    res = client.post("/tryon", json=own(garment_image=photo_b64(size=(120, 150))), headers=USER)
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "IMAGE_TOO_SMALL" and res.json()["error"]["details"]["angle"] == "garment"


@pytest.mark.parametrize("extra", [
    {},  # neither
    {"product_id": "outfitters:tee", "garment": {"image_base64": "x" * 200, "category": "upper"}},  # both
])
def test_exactly_one_garment_source(env, extra):
    client, _, _ = env
    req = {"views": [{"angle": "front", "image_base64": photo_b64()}], **extra}
    assert client.post("/tryon", json=req, headers=USER).status_code == 422


def test_own_clothes_category_must_be_known(env):
    client, _, _ = env
    assert client.post("/tryon", json=own(category="shoes"), headers=USER).status_code == 422


# ── size is reported, never a refusal (SFR-025; user's call, 15 Nov 2026) ───


def test_own_clothes_that_fit_are_tried_on_and_say_why(env):
    client, _, _ = env
    job = client.post("/tryon", json=own(category="dress"), headers=USER).json()
    assert job["fit"]["status"] == "fits" and job["fit"]["basis"] == "measurements"
    assert job["fit"]["note"] == "Chest 110 cm on you 96 cm; waist 88 cm on you 82 cm"


@pytest.mark.parametrize(("category", "chest", "waist", "part"), [
    ("upper", 49.0, None, "chest"),  # 98 cm around: less than 96 + 4 cm room
    ("lower", None, 40.0, "waist"),  # 80 cm around: smaller than an 82 cm waist
    ("dress", 60.0, 39.0, "waist"),  # chest fine, waist too small
])
def test_own_clothes_that_are_small_are_still_tried_on_and_say_so(env, category, chest, waist, part):
    client, _, _ = env
    res = client.post("/tryon", json=own(category=category, chest=chest, waist=waist), headers=USER)
    assert res.status_code == 202  # the user sees it on themselves and decides
    fit = res.json()["fit"]
    assert fit["status"] == "small"
    assert f"Too small at the {part}" in fit["note"]


def test_own_clothes_that_are_far_too_big_say_so(env):
    client, _, _ = env  # 180 cm around a 96 cm chest: 84 cm of room
    res = client.post("/tryon", json=own(category="upper", chest=90.0), headers=USER)
    assert res.status_code == 202
    fit = res.json()["fit"]
    assert fit["status"] == "big" and "Loose at the chest" in fit["note"]


def test_a_missing_tape_measurement_only_skips_the_check(env):
    client, _, _ = env
    res = client.post("/tryon", json=own(category="upper", chest=None), headers=USER)
    assert res.status_code == 202
    fit = res.json()["fit"]
    assert fit["status"] == "unknown" and "chest" in fit["note"]


def test_a_missing_profile_measurement_only_skips_the_check(env):
    client, _, _ = env
    env_state["body"].pop("waist_cm")
    fit = client.post("/tryon", json=own(category="lower"), headers=USER).json()["fit"]
    assert fit["status"] == "unknown" and "profile" in fit["note"]
    env_state["body"]["unreadable"] = True
    tryon._jobs.clear()  # the first try-on actually ran; one job per user
    res = client.post("/tryon", json=own(category="upper"), headers=USER)
    assert res.status_code == 202 and res.json()["fit"]["status"] == "unknown"


def test_a_catalog_item_too_small_by_its_chart_is_still_tried_on(env):
    client, _, _ = env
    small = product("outfitters:small").model_copy(update={
        "sizes": ["S", "M"], "size_chart": {"S": {"chest_cm": 88.0}, "M": {"chest_cm": 94.0}}})
    env_state["catalog"]["outfitters:small"] = small
    res = client.post("/tryon", json=body("outfitters:small"), headers=USER)
    assert res.status_code == 202  # brand clothes are never refused for size
    fit = res.json()["fit"]
    assert fit["status"] == "small"
    assert "largest size is smaller than your chest" in fit["note"]


def test_catalog_item_that_fits_by_its_chart_names_the_size(env):
    client, _, _ = env
    env_state["catalog"]["outfitters:fits"] = product("outfitters:fits").model_copy(update={
        "sizes": ["M", "L"], "size_chart": {"M": {"chest_cm": 98.0}, "L": {"chest_cm": 104.0}}})
    job = client.post("/tryon", json=body("outfitters:fits"), headers=USER).json()
    assert job["fit"] == {"status": "fits", "basis": "size_chart", "size": "L",
                          "note": "Size L from this product's size chart"}


def test_catalog_item_without_a_chart_is_allowed_with_a_warning(env):
    client, _, _ = env
    job = client.post("/tryon", json=body(), headers=USER).json()
    assert job["fit"]["status"] == "unknown" and "doesn't publish a size chart" in job["fit"]["note"]


# ── SFR-025: the user's size sold out at the store (user's decision, 20 Nov 2026) ──


def test_your_size_sold_out_by_the_chart_is_not_tried_on(env):
    client, _, _ = env
    env_state["catalog"]["outfitters:soldout"] = product("outfitters:soldout").model_copy(update={
        "sizes": ["M"], "all_sizes": ["M", "L"],
        "size_chart": {"M": {"chest_cm": 98.0}, "L": {"chest_cm": 104.0}}})  # chest 96: your size is L
    res = client.post("/tryon", json=body("outfitters:soldout"), headers=USER)
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "TRYON_UNAVAILABLE" and err["details"]["reason"] == "size_sold_out"
    assert "Your size (L) is sold out at Outfitters" in err["message"]
    assert not tryon._jobs  # nothing sent to the GPU


def test_your_size_sold_out_by_the_profile_estimate_is_not_tried_on(env):
    client, _, _ = env
    env_state["estimated"]["size"] = "L"
    env_state["catalog"]["outfitters:tee"] = product().model_copy(update={"sizes": ["S", "M"],
                                                                          "all_sizes": ["S", "M", "L"]})
    err = client.post("/tryon", json=body(), headers=USER).json()["error"]
    assert err["details"]["reason"] == "size_sold_out" and "(L)" in err["message"]


def test_2xl_and_xxl_are_the_same_size(env):
    client, _, _ = env
    env_state["estimated"]["size"] = "XXL"
    env_state["catalog"]["outfitters:tee"] = product().model_copy(update={"sizes": ["L"],
                                                                          "all_sizes": ["L", "2XL"]})
    assert client.post("/tryon", json=body(), headers=USER).json()["error"]["details"]["reason"] == "size_sold_out"


def test_a_product_never_made_in_your_size_still_runs(env):
    client, _, _ = env
    env_state["estimated"]["size"] = "XL"
    env_state["catalog"]["outfitters:tee"] = product().model_copy(update={"sizes": ["S", "M"],
                                                                          "all_sizes": ["S", "M"]})
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202  # a fit question, not stock


def test_your_size_in_stock_runs_and_names_it(env):
    client, _, _ = env
    env_state["estimated"]["size"] = "M"
    env_state["catalog"]["outfitters:tee"] = product().model_copy(update={"sizes": ["S", "M"],
                                                                          "all_sizes": ["S", "M", "L"]})
    res = client.post("/tryon", json=body(), headers=USER)
    assert res.status_code == 202 and res.json()["fit"]["status"] == "fits" and res.json()["fit"]["size"] == "M"


def test_estimated_size_needs_real_measurements(monkeypatch):
    import asyncio

    async def select(_client, table, params):
        return [{"gender": "Female", "chest_cm": None, "height_cm": None, "weight_kg": None}]

    monkeypatch.setattr(tryon, "service_select", select)
    monkeypatch.setattr(tryon, "_client", object())
    uid = "11111111-2222-3333-4444-555555555555"
    assert asyncio.run(tryon._estimated_size(uid)) is None  # nothing to go on: no guess

    async def select2(_client, table, params):
        return [{"gender": "Female", "chest_cm": 95.0, "height_cm": 165, "weight_kg": 60}]

    monkeypatch.setattr(tryon, "service_select", select2)
    assert asyncio.run(tryon._estimated_size(uid)) == "L"  # women's chart: 92-98 cm chest


# ── the clothes photo must show clothing of the chosen kind ──────────────────


def test_a_photo_that_is_not_clothing_is_refused(env):
    client, _, _ = env
    env_state["clothes"]["scores"] = {"upper": 0.1, "lower": 0.05, "dress": 0.05, "other": 0.8}
    res = client.post("/tryon", json=own(category="upper"), headers=USER)
    err = res.json()["error"]
    assert res.status_code == 422 and err["code"] == "NOT_CLOTHING" and err["details"]["angle"] == "garment"


def test_an_obvious_type_mix_up_is_refused_with_a_suggestion(env):
    client, _, _ = env
    env_state["clothes"]["scores"] = {"upper": 0.03, "lower": 0.9, "dress": 0.05, "other": 0.02}
    err = client.post("/tryon", json=own(category="upper"), headers=USER).json()["error"]
    assert err["code"] == "GARMENT_MISMATCH" and err["details"]["suggested"] == "lower"
    assert "This looks like a bottom" in err["message"]


def test_a_close_call_between_top_and_outfit_is_allowed(env):
    client, _, _ = env  # a long kurta can look like a dress: not a clear mix-up
    env_state["clothes"]["scores"] = {"upper": 0.35, "lower": 0.02, "dress": 0.6, "other": 0.03}
    assert client.post("/tryon", json=own(category="upper"), headers=USER).status_code == 202


def test_try_on_still_works_when_the_clothes_checker_is_down(env, monkeypatch):
    client, _, _ = env

    async def down(_jpeg):
        return None

    monkeypatch.setattr(tryon, "_classify_garment", down)
    assert client.post("/tryon", json=own(), headers=USER).status_code == 202


# ── HRNet person check, before any GPU work ──────────────────────────────────


def test_every_photo_is_checked_for_the_garment_kind(env):
    client, _, _ = env
    res = client.post("/tryon", json=body("outfitters:dress", angles=("front", "back")), headers=USER)
    assert res.status_code == 202
    assert env_state["persons"]["calls"] == [("front", "dress"), ("back", "dress")]


def test_a_photo_that_fails_the_person_check_is_refused_by_side(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["back"] = {
        "ok": False, "code": "BODY_CUT_OFF", "message": "Trousers need your legs down to the ankles in the back photo."}
    res = client.post("/tryon", json=body(angles=("front", "back")), headers=USER)
    err = res.json()["error"]
    assert res.status_code == 422 and err["code"] == "BODY_CUT_OFF" and err["details"]["angle"] == "back"
    assert "ankles" in err["message"]
    assert not tryon._jobs  # nothing was sent to the GPU


def test_try_on_still_works_when_the_person_checker_is_down(env, monkeypatch):
    client, _, _ = env

    async def down(_angle, _jpeg, _category):
        return None

    monkeypatch.setattr(tryon, "_person_verdict", down)
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202


def test_an_unknown_checker_answer_does_not_block(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": False, "code": "SOMETHING_NEW"}
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202


# ── SFR-027: unavailable, with a reason the app can show ─────────────────────


def test_unstitched_fabric_is_unavailable_not_an_error(env):
    client, _, _ = env
    res = client.post("/tryon", json=body("outfitters:fabric"), headers=USER)
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "TRYON_UNAVAILABLE" and err["details"]["reason"] == "not_supported"


def test_the_apps_size_flag_never_blocks_a_try_on(env):
    client, _, _ = env
    for flag in (False, None, True):
        tryon._jobs.clear()  # each one really starts; one job per user
        res = client.post("/tryon", json=body(size_compatible=flag), headers=USER)
        assert res.status_code == 202, flag


def test_a_product_no_longer_sold_is_unavailable_with_the_brand_named_never_a_bare_404(env):
    client, _, _ = env
    res = client.post("/tryon", json=body("outfitters:old-jacket"), headers=USER)
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "TRYON_UNAVAILABLE" and err["details"]["reason"] == "gone"
    assert "Outfitters no longer sells" in err["message"]
    assert env_state["rechecked"] == ["outfitters:old-jacket"]


@pytest.mark.parametrize("status, words", [("sold_out", "sold out at Outfitters"),
                                           ("not_clothing", "isn't available"),
                                           ("unknown_brand", "isn't in our catalog")])
def test_every_store_answer_has_its_own_message(env, status, words):
    client, _, _ = env
    env_state["store_answers"]["outfitters:x"] = {"status": status, "product": None}
    res = client.post("/tryon", json=body("outfitters:x"), headers=USER)
    assert res.status_code == 422 and res.json()["error"]["details"]["reason"] == "gone"
    assert words in res.json()["error"]["message"]


def test_a_saved_item_the_catalog_dropped_but_the_brand_still_sells_is_tried_on(env):
    """The daily refresh keeps each brand's newest items: an older saved item is
    re-checked at the store and tried on as usual."""
    client, _, _ = env
    restored = product("outfitters:older-hoodie")
    env_state["store_answers"]["outfitters:older-hoodie"] = {
        "status": "available", "product": restored.model_dump(mode="json")}
    res = client.post("/tryon", json=body("outfitters:older-hoodie"), headers=USER)
    assert res.status_code == 202 and res.json()["product_id"] == "outfitters:older-hoodie"


def test_a_catalog_product_is_not_rechecked(env):
    client, _, _ = env
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202
    assert env_state["rechecked"] == []


def test_store_unreachable_is_a_retryable_503(env):
    client, _, _ = env
    env_state["store_answers"]["outfitters:x"] = {"status": "unreachable"}
    res = client.post("/tryon", json=body("outfitters:x"), headers=USER)
    assert res.status_code == 503 and res.json()["error"]["code"] == "STORE_UNREACHABLE"
    assert res.headers["retry-after"] == "60"


def test_recheck_never_raises_when_the_scraper_is_down(monkeypatch):
    class Down:
        async def post(self, *a, **k):
            raise tryon.httpx.ConnectError("down")
    monkeypatch.setattr(tryon, "_client", Down())
    import asyncio
    assert asyncio.run(tryon._recheck_at_store("outfitters:x")) == {"status": "unreachable"}


def test_not_connected_gives_clear_503(env, monkeypatch):
    client, _, _ = env
    monkeypatch.setattr(settings, "tryon_backend", "")
    gpu_runner.reset_runner()
    res = client.post("/tryon", json=body(), headers=USER)
    assert res.status_code == 503 and res.json()["error"]["code"] == "TRYON_NOT_CONNECTED"


def test_person_not_found_becomes_a_friendly_view_message(env, monkeypatch):
    client, _, _ = env
    runner = gpu_runner.get_runner()
    monkeypatch.setattr(runner, "poll", lambda _cid: ViewOutcome("failed", error_code="NO_PERSON"))
    job = client.post("/tryon", json=body(angles=("front", "back")), headers=USER).json()
    res = client.get(f"/tryon/{job['job_id']}", headers=USER).json()
    assert res["status"] == "failed"
    assert res["views"][1]["error_code"] == "NO_PERSON"
    assert "back photo" in res["views"][1]["message"]


# ── photo validation (rules.md §5: server-side, before any GPU work) ─────────


@pytest.mark.parametrize(("image", "code"), [
    ("not-base64-at-all!" * 10, "INVALID_IMAGE"),
    (base64.b64encode(b"GIF89a" + b"0" * 200).decode(), "INVALID_IMAGE"),
    (photo_b64(size=(200, 300)), "IMAGE_TOO_SMALL"),
])
def test_bad_photos_are_rejected_with_the_side_named(env, image, code):
    client, _, _ = env
    req = {"product_id": "outfitters:tee", "views": [{"angle": "front", "image_base64": image}]}
    res = client.post("/tryon", json=req, headers=USER)
    assert res.status_code == 422
    assert res.json()["error"]["code"] == code
    assert res.json()["error"]["details"]["angle"] == "front"


@pytest.mark.parametrize(("size", "ok"), [
    ((330, 1200), True),   # tightly cropped full-body photo: framed to 900 x 1200, sharp enough (20 Nov 2026)
    ((900, 1200), True),
    ((384, 512), True),    # exactly the minimum frame
    ((800, 400), False),   # wide but short: only a 300 x 400 frame
    ((600, 500), False),
])
def test_person_photos_are_judged_by_their_framed_size(env, size, ok):
    client, _, _ = env
    req = {"product_id": "outfitters:tee", "views": [{"angle": "front", "image_base64": photo_b64(size=size)}]}
    res = client.post("/tryon", json=req, headers=USER)
    if ok:
        assert res.status_code == 202
    else:
        assert res.status_code == 422 and res.json()["error"]["code"] == "IMAGE_TOO_SMALL"


def test_front_photo_required_and_sides_unique(env):
    client, _, _ = env
    assert client.post("/tryon", json=body(angles=("back",)), headers=USER).status_code == 422
    assert client.post("/tryon", json=body(angles=("front", "front")), headers=USER).status_code == 422


def test_data_url_prefix_and_png_are_accepted(env):
    client, _, _ = env
    req = {"product_id": "outfitters:tee",
           "views": [{"angle": "front", "image_base64": "data:image/png;base64," + photo_b64(fmt="PNG")}]}
    assert client.post("/tryon", json=req, headers=USER).status_code == 202


# ── privacy and limits ───────────────────────────────────────────────────────


def test_requires_user(env):
    client, _, _ = env
    assert client.post("/tryon", json=body()).status_code == 401


def test_another_user_cannot_see_a_job(env):
    client, _, _ = env
    job = client.post("/tryon", json=body(), headers=USER).json()
    assert client.get(f"/tryon/{job['job_id']}", headers=OTHER).status_code == 404


def test_one_running_job_per_user(env, monkeypatch):
    client, _, _ = env
    monkeypatch.setattr(settings, "tryon_mock_delay_seconds", 60.0)
    gpu_runner.reset_runner()
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202
    res = client.post("/tryon", json=body("outfitters:dress"), headers=USER)
    assert res.status_code == 429 and res.json()["error"]["code"] == "TRYON_IN_PROGRESS"
    assert client.post("/tryon", json=body(), headers=OTHER).status_code == 202


def test_sign_only_signs_the_users_own_results(env):
    client, store, _ = env
    job = client.post("/tryon", json=body(), headers=USER).json()
    path = client.get(f"/tryon/{job['job_id']}", headers=USER).json()["views"][0]["storage_path"]
    store["user-b/secret.jpg"] = b"x"
    urls = client.post("/tryon/sign", json={"paths": [path, "user-b/secret.jpg", "user-a/../user-b/secret.jpg"]},
                       headers=USER).json()["urls"]
    assert list(urls) == [path]


def test_health_reports_test_mode(env):
    client, _, _ = env
    health = client.get("/health").json()
    assert health["implemented"] is True and health["test_mode"] is True and health["connected"] is True


# ── framing (imaging.py) ─────────────────────────────────────────────────────


def test_tall_phone_photo_is_padded_not_cropped():
    tall = Image.new("RGB", (900, 1600), (200, 200, 200))
    tall.paste((255, 0, 0), (0, 0, 900, 40))  # a red "head" band at the very top
    framed = imaging.frame_person(tall)
    assert framed.size == (768, 1024)
    assert framed.getpixel((384, 5))[0] > 200  # the top is still there


def test_wide_photo_is_cropped_to_3_by_4():
    assert imaging.frame_person(Image.new("RGB", (1600, 900))).size == (768, 1024)


def test_reencoding_drops_metadata():
    img = Image.new("RGB", (800, 1000))
    exif = Image.Exif()
    exif[0x8825] = {2: (33, 0, 0)}  # a GPS tag
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    clean = Image.open(io.BytesIO(imaging.to_jpeg(imaging.open_image(buf.getvalue()))))
    assert not clean.getexif()


def test_garment_caption_keeps_words_drops_codes():
    assert imaging.garment_caption("Relaxed Fit Hoodie - F0123/24") == "relaxed fit hoodie"
    assert imaging.garment_caption("2PC SUIT 0042") == "suit"
    assert imaging.garment_caption("0042 / 2PC", "kurta-sets") == "kurta sets"  # nothing usable: the category


# ── menswear on men, womenswear on women (18 Nov 2026) ───────────────────────


def test_womenswear_is_not_tried_on_a_male_profile(env):
    client, _, fetched = env
    env_state["catalog"]["outfitters:frock"] = product("outfitters:frock", "dress", "Embroidered Frock").model_copy(
        update={"gender": "women"})
    res = client.post("/tryon", json=body("outfitters:frock"), headers=USER)
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "TRYON_UNAVAILABLE" and err["details"]["reason"] == "gender"
    assert "women's outfit" in err["message"] and "set to male" in err["message"]
    assert fetched == []  # stopped before any photo or GPU work


def test_menswear_is_not_tried_on_a_female_profile(env):
    client, _, _ = env
    env_state["wears"]["value"] = "women"
    res = client.post("/tryon", json=body(), headers=USER)  # product() is menswear
    assert res.status_code == 422 and res.json()["error"]["details"]["reason"] == "gender"
    assert "men's outfit" in res.json()["error"]["message"]


@pytest.mark.parametrize("wears", ["men", None])
def test_matching_or_unset_gender_is_tried_on(env, wears):
    client, _, _ = env
    env_state["wears"]["value"] = wears
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202


def test_unisex_items_are_tried_on_anyone(env):
    client, _, _ = env
    env_state["wears"]["value"] = "women"
    env_state["catalog"]["outfitters:tee"] = product().model_copy(update={"gender": "unisex"})
    assert client.post("/tryon", json=body(), headers=USER).status_code == 202


@pytest.mark.parametrize("stored, wears", [("Male", "men"), ("female", "women"), ("Non-binary", None),
                                           ("Prefer not to say", None), ("", None)])
def test_profile_gender_mapping(monkeypatch, stored, wears):
    import asyncio

    async def select(_client, table, params):
        assert table == "profiles" and params["select"] == "gender"
        return [{"gender": stored}]

    monkeypatch.setattr(tryon, "service_select", select)
    monkeypatch.setattr(tryon, "_client", object())
    assert asyncio.run(tryon._profile_wears("11111111-2222-3333-4444-555555555555")) == wears


# ── the photo decides who wears it; the user's own clothes are checked too ───

HEAD = [{"name": n, "x": x, "y": y, "confidence": 0.9} for n, x, y in [
    ("nose", 0.5, 0.15), ("left_eye", 0.47, 0.13), ("right_eye", 0.53, 0.13), ("left_ear", 0.44, 0.14),
    ("right_ear", 0.56, 0.14), ("left_shoulder", 0.38, 0.27), ("right_shoulder", 0.62, 0.27)]]


def own_clothes_body(category="dress"):
    b = body(None)
    b.pop("product_id")
    return {**b, "garment": {"image_base64": photo_b64(colour=(200, 30, 90)), "category": category}}


def test_womens_clothes_photo_is_not_tried_on_a_man_in_the_photo(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": HEAD}
    env_state["genders"].update(garment="women", face="man")
    res = client.post("/tryon", json=own_clothes_body(), headers=USER)
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["details"]["reason"] == "gender"
    assert "women's clothing" in err["message"] and "looks like a man" in err["message"]
    assert sorted(env_state["genders"]["calls"]) == ["face", "garment"]
    # the face check gets the whole front photo too, as a second opinion
    assert isinstance(env_state["genders"]["face_photo"], bytes) and len(env_state["genders"]["face_photo"]) > 100


def test_mens_clothes_photo_is_not_tried_on_a_woman_in_the_photo(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": HEAD}
    env_state["genders"].update(garment="men", face="woman")
    env_state["wears"]["value"] = "men"  # the photo wins over the profile
    res = client.post("/tryon", json=own_clothes_body("upper"), headers=USER)
    assert res.status_code == 422 and "looks like a woman" in res.json()["error"]["message"]


def test_the_photo_wins_over_the_profile_for_a_catalog_item(env):
    """A man's profile trying a women's catalog dress on a woman's photo (e.g. for his sister)."""
    client, _, _ = env
    env_state["catalog"]["outfitters:frock"] = product("outfitters:frock", "dress", "Frock").model_copy(
        update={"gender": "women"})
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": HEAD}
    env_state["genders"]["face"] = "woman"
    assert client.post("/tryon", json=body("outfitters:frock"), headers=USER).status_code == 202


def test_matching_own_clothes_are_tried_on(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": HEAD}
    env_state["genders"].update(garment="women", face="woman")
    env_state["wears"]["value"] = "women"
    assert client.post("/tryon", json=own_clothes_body(), headers=USER).status_code == 202


@pytest.mark.parametrize("garment, face, wears", [
    (None, "man", "men"),  # the garment model isn't sure: never blocks
    ("women", None, None),  # face not sure and no profile gender: never blocks
])
def test_unsure_answers_never_block(env, garment, face, wears):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": HEAD}
    env_state["genders"].update(garment=garment, face=face)
    env_state["wears"]["value"] = wears
    assert client.post("/tryon", json=own_clothes_body(), headers=USER).status_code == 202


def test_face_not_visible_falls_back_to_the_profile(env):
    client, _, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": []}  # no head found
    env_state["genders"]["garment"] = "women"
    env_state["wears"]["value"] = "men"
    res = client.post("/tryon", json=own_clothes_body(), headers=USER)
    assert res.status_code == 422 and "profile is set to male" in res.json()["error"]["message"]
    assert env_state["genders"]["calls"] == ["garment"]  # no face crop, so no face check


def test_head_crop_from_keypoints():
    from shared.head_crop import head_box
    box = head_box(HEAD, 900, 1200)
    assert box is not None
    left, top, right, bottom = box
    assert left < 450 < right and top < 180 < bottom and 60 < right - left < 400
    assert head_box(HEAD[:2], 900, 1200) is None  # too few head points


# ── sleeve length in the caption (20 Nov 2026: a long-sleeved shirt came out elbow-length) ──


def test_sleeve_words_from_names():
    assert imaging.sleeve_from_name("Full Sleeve Kurta") == "long sleeve"
    assert imaging.sleeve_from_name("LONG SLEEVES SHIRT") == "long sleeve"
    assert imaging.sleeve_from_name("Half-Sleeve Polo") == "short sleeve"
    assert imaging.sleeve_from_name("Sleeveless Top") == "sleeveless"
    assert imaging.sleeve_from_name("3/4 Sleeve Kurti") == "cropped sleeve"
    assert imaging.sleeve_from_name("Button Up Shirt") is None
    assert imaging.sleeve_from_name("Sleeveless top with full sleeve shrug") is None  # two answers: not sure
    assert imaging.with_sleeve("button up shirt", "long sleeve") == "long sleeve button up shirt"
    assert imaging.with_sleeve("short sleeve tee", "long sleeve") == "short sleeve tee"  # already says it
    assert imaging.with_sleeve("tee", None) == "tee"
    assert imaging.canonical_sleeve("half sleeve graphic tee", "short sleeve") == "short sleeve graphic tee"
    assert imaging.canonical_sleeve("kurta full sleeves", "long sleeve") == "long sleeve kurta"


def _captions(client, monkeypatch, req):
    runner = gpu_runner.get_runner()
    sent = []
    monkeypatch.setattr(runner, "submit", lambda task: sent.append(task) or "call-1")
    assert client.post("/tryon", json=req, headers=USER).status_code == 202
    return [t.caption for t in sent]


def test_catalog_top_gets_the_sleeve_seen_in_its_photo(env, monkeypatch):
    client, _, _ = env
    env_state["sleeve"]["value"] = "long sleeve"
    assert _captions(client, monkeypatch, body()) == ["long sleeve relaxed fit hoodie"]


def test_sleeve_named_in_the_product_name_wins_without_a_photo_check(env, monkeypatch):
    client, _, _ = env
    env_state["catalog"]["outfitters:tee"] = product(name="Half Sleeve Graphic Tee")
    env_state["sleeve"]["value"] = "long sleeve"  # the photo would say otherwise: the name is the brand's own word
    assert _captions(client, monkeypatch, body()) == ["short sleeve graphic tee"]
    assert env_state["sleeve"]["calls"] == 0


def test_unsure_sleeve_leaves_the_caption_alone(env, monkeypatch):
    client, _, _ = env
    assert _captions(client, monkeypatch, body()) == ["relaxed fit hoodie"]


def test_bottoms_never_get_a_sleeve(env, monkeypatch):
    client, _, _ = env
    env_state["sleeve"]["value"] = "long sleeve"
    assert _captions(client, monkeypatch, own(category="lower")) == ["blue denim jeans"]
    assert env_state["sleeve"]["calls"] == 0


def test_own_top_gets_the_sleeve_seen_in_its_photo(env, monkeypatch):
    client, _, _ = env
    env_state["sleeve"]["value"] = "sleeveless"
    assert _captions(client, monkeypatch, own(category="upper", name="Cotton top")) == ["sleeveless cotton top"]


def test_a_new_caption_makes_a_new_result():
    a = tryon._cache_key(b"p", "outfitters:tee", "u", "v", "mock", "relaxed fit hoodie")
    b = tryon._cache_key(b"p", "outfitters:tee", "u", "v", "mock", "long sleeve relaxed fit hoodie")
    assert a != b


def test_a_360_try_on_sends_its_four_views_to_the_gpu_together(env, monkeypatch):
    """20 Nov 2026: one view at a time made a 360° start take up to ~20 s."""
    import threading
    import time as _time

    client, _, _ = env
    runner = gpu_runner.get_runner()
    running, most = [0], [0]
    lock = threading.Lock()

    def slow_submit(task):
        with lock:
            running[0] += 1
            most[0] = max(most[0], running[0])
        _time.sleep(0.2)
        with lock:
            running[0] -= 1
        return f"call-{task.angle}"

    monkeypatch.setattr(runner, "submit", slow_submit)
    res = client.post("/tryon", json=body(angles=("front", "right", "back", "left")), headers=USER)
    assert res.status_code == 202
    assert most[0] >= 2  # submitted at the same time, not one after another
    assert {v["status"] for v in res.json()["views"]} == {"running"}



# ── cloth warping preview (21 Nov 2026) ──────────────────────────────────────


def _keypoints() -> list[dict]:
    pts = {"left_shoulder": (0.62, 0.30), "right_shoulder": (0.38, 0.30), "left_hip": (0.57, 0.58),
           "right_hip": (0.43, 0.58), "left_elbow": (0.66, 0.45), "right_elbow": (0.34, 0.45),
           "left_knee": (0.56, 0.76), "right_knee": (0.44, 0.76)}
    return [{"name": n, "x": x, "y": y, "confidence": 0.9} for n, (x, y) in pts.items()]


def test_a_fitting_preview_is_made_from_the_photo_checks_body_points(env):
    client, store, _ = env
    env_state["persons"]["verdicts"]["front"] = {"ok": True, "keypoints": _keypoints()}
    job = client.post("/tryon", json=body(), headers=USER).json()
    import time as _time
    for _ in range(50):  # made in the background, while the GPU works
        if any(p.endswith("_fit.jpg") for p in store):
            break
        _time.sleep(0.1)
    fit_path = next(p for p in store if p.endswith("_fit.jpg"))
    assert fit_path.startswith("user-a/")  # the user's own private folder
    view = client.get(f"/tryon/{job['job_id']}", headers=USER).json()["views"][0]
    assert view["fitting_url"].startswith("https://signed.example/tryon-results/user-a/")
    assert view["fitting_path"] == fit_path


def test_without_body_points_there_is_no_fitting_preview(env):
    client, store, _ = env
    job = client.post("/tryon", json=body(), headers=USER).json()  # the default check has no keypoints
    view = client.get(f"/tryon/{job['job_id']}", headers=USER).json()["views"][0]
    assert view["fitting_url"] is None and not any(p.endswith("_fit.jpg") for p in store)
