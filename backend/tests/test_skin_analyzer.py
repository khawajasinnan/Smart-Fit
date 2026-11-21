"""Skin tone analyzer (21 Nov 2026): depth on the Monk scale, undertone, and clothing advice."""

from __future__ import annotations

import base64

import pytest

cv2 = pytest.importorskip("cv2")
pytest.importorskip("mediapipe")

import numpy as np  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from services.cv_analysis import main  # noqa: E402
from services.cv_analysis import skin_tone as st  # noqa: E402
from services.cv_analysis.face import FaceBox  # noqa: E402
from shared.color_harmony import skin_harmony  # noqa: E402
from shared.skin_palette import palette  # noqa: E402

FACE = FaceBox(x=100, y=100, w=200, h=200, score=0.99)


def photo(skin_bgr, background_bgr=(200, 200, 200), outfit_bgr=None) -> np.ndarray:
    img = np.full((600, 400, 3), background_bgr, np.uint8)
    if outfit_bgr is not None:
        img[320:600, 40:360] = outfit_bgr  # a big coloured top under the face
    img[FACE.y:FACE.y + FACE.h, FACE.x:FACE.x + FACE.w] = skin_bgr
    return img


# ── measurement ──────────────────────────────────────────────────────────────


def test_monk_swatches_map_to_their_own_level():
    assert [st.monk_level(lab) for lab in st._MONK_LAB] == list(range(1, 11))


def test_a_lighter_skin_never_gets_a_deeper_monk_level():
    light = st.analyze_skin_detail(photo((150, 180, 225)), FACE)
    deep = st.analyze_skin_detail(photo((60, 85, 120)), FACE)
    assert light["monk_level"] < deep["monk_level"]


def test_a_neutral_background_leaves_the_colour_as_it_is():
    assert np.allclose(st.neutral_gains(photo((120, 160, 210)), FACE), 1.0, atol=0.01)


def test_a_big_red_top_does_not_change_the_skin_reading():
    """21 Nov 2026: grey-world white balance read a fair woman in a red top as Brown, Monk 7."""
    plain = st.analyze_skin_detail(photo((150, 180, 225)), FACE)
    red_top = st.analyze_skin_detail(photo((150, 180, 225), outfit_bgr=(30, 30, 200)), FACE)
    assert red_top["monk_level"] == plain["monk_level"] and red_top["app_label"] == plain["app_label"]


def test_a_tinted_light_is_corrected_by_the_grey_wall():
    true = st.analyze_skin_detail(photo((130, 165, 210)), FACE)
    tint = np.array([0.92, 1.0, 1.08])  # warm lamp: a little less blue, a little more red
    lamp = np.clip(photo((130, 165, 210)) * tint, 0, 255).astype(np.uint8)
    corrected = st.analyze_skin_detail(lamp, FACE)
    raw = lamp[FACE.y + 100, FACE.x + 100].astype(float)
    assert corrected["white_balanced"] is True
    measured = np.array([int(corrected["measured_hex"][i:i + 2], 16) for i in (5, 3, 1)], float)  # BGR
    expected = np.array([int(true["measured_hex"][i:i + 2], 16) for i in (5, 3, 1)], float)
    assert np.abs(measured - expected).max() < np.abs(raw - expected).max()  # closer to the true skin


def test_without_neutral_pixels_nothing_is_corrected():
    img = photo((120, 160, 210), background_bgr=(40, 140, 40))  # a green wall: nothing neutral
    assert st.neutral_gains(img, FACE) is None
    assert st.analyze_skin_detail(img, FACE)["white_balanced"] is False


@pytest.mark.parametrize("bucket", list(st.UNDERTONE_CUTS))
def test_undertone_cut_offs_per_depth(bucket):
    cool_cut, warm_cut = st.UNDERTONE_CUTS[bucket]
    assert st.undertone_from_hue(cool_cut - 5, bucket)[0] == "cool"
    assert st.undertone_from_hue((cool_cut + warm_cut) / 2, bucket)[0] == "neutral"
    assert st.undertone_from_hue(warm_cut + 5, bucket)[0] == "warm"
    assert st.undertone_from_hue(warm_cut + 0.5, bucket)[1] == "low"  # right at the line


def test_deep_skin_undertone_is_always_marked_less_sure():
    assert st.undertone_from_hue(80, "deep")[1] == "low"


def test_no_skin_pixels_gives_none():
    assert st.analyze_skin_detail(photo((255, 0, 0)), FACE) is None  # pure blue is never skin


# ── advice ───────────────────────────────────────────────────────────────────


def test_white_and_jewel_tones_for_deep_skin():
    """The user's example: a full white suit looks beautiful on dark skin."""
    p = palette("Dark", "warm")
    assert "white" in p["white"].lower() and "suit" in p["white"].lower()
    assert any("white" in idea.lower() for idea in p["outfits"])
    assert {"white", "gold"} & {c["name"] for c in p["best"]}


def test_warm_and_cool_advice_differ_the_right_way():
    warm, cool = palette("Medium", "warm"), palette("Medium", "cool")
    warm_best, cool_best = {c["name"] for c in warm["best"]}, {c["name"] for c in cool["best"]}
    assert "mustard" in warm_best and "mustard" not in cool_best
    assert warm["metal"] == "Gold" and cool["metal"] == "Silver"


def test_best_and_avoid_never_overlap():
    for tone in ("Fair", "Light", "Medium", "Olive", "Brown", "Dark"):
        for u in ("warm", "cool", "neutral", None):
            p = palette(tone, u)
            assert not {c["name"] for c in p["best"]} & {c["name"] for c in p["avoid"]}, (tone, u)
            assert p["best"] and p["outfits"] and p["white"] and p["metal"]


def test_without_an_undertone_the_advice_asks_for_it():
    assert "two quick questions" in palette("Brown")["summary"]
    assert palette(None) is None and palette("purple") is None


def test_recommendations_use_the_undertone_too():
    warm = skin_harmony(["mustard"], "Medium", "warm").score
    cool = skin_harmony(["mustard"], "Medium", "cool").score
    unknown = skin_harmony(["mustard"], "Medium").score
    assert warm > unknown > cool


# ── endpoints ────────────────────────────────────────────────────────────────


class FakeFaces:
    def __init__(self, faces):
        self.faces = faces

    def detect(self, _img):
        return self.faces

    def close(self):
        pass


@pytest.fixture
def client(monkeypatch):
    with TestClient(main.app) as c:
        monkeypatch.setattr(main, "_faces", FakeFaces([FACE]))
        yield c


def b64(img) -> str:
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return base64.b64encode(buf.tobytes()).decode()


def test_analyze_endpoint(client):
    res = client.post("/skin-tone/analyze", json={"image_base64": b64(photo((120, 160, 210)))})
    assert res.status_code == 200
    body = res.json()
    assert body["skin_tone"] in {"Fair", "Light", "Medium", "Olive", "Brown", "Dark"}
    assert 1 <= body["monk_level"] <= 10 and body["undertone"] in {"warm", "cool", "neutral"}
    assert body["palette"]["best"] and body["palette"]["outfits"]


def test_no_face_is_a_clear_message(client, monkeypatch):
    monkeypatch.setattr(main, "_faces", FakeFaces([]))
    monkeypatch.setattr(main, "_pose", None)
    res = client.post("/skin-tone/analyze", json={"image_base64": b64(photo((120, 160, 210)))})
    assert res.status_code == 422 and res.json()["error"]["code"] == "NO_FACE"


def test_palette_endpoint(client):
    res = client.get("/skin-tone/palette", params={"skin_tone": "Dark", "undertone": "cool"})
    assert res.status_code == 200 and res.json()["metal"] == "Silver"
    assert client.get("/skin-tone/palette", params={"skin_tone": "nope"}).status_code == 422


def test_the_advice_never_contradicts_its_own_summary():
    """21 Nov 2026 (E2E screenshot): "Light skin with a warm undertone: earthy, golden colours" listed navy,
    royal blue and black, because the light-skin lists lean cool. A known undertone now wins for its own colours."""
    warm = {c["name"] for c in palette("Light", "warm")["best"]}
    cool = {c["name"] for c in palette("Light", "cool")["best"]}
    assert {"coral", "rust", "cream"} & warm and not {"royal blue", "plum", "lavender"} & warm
    assert {"navy", "plum", "royal blue"} & cool and not {"cream", "ivory", "peach", "rust"} & cool
    assert skin_harmony(["cream"], "Fair", "warm").score > skin_harmony(["cream"], "Fair", "cool").score
