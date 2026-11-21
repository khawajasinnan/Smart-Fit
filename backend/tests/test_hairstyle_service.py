"""Hairstyle service (SFR-029..031): face check, ranking, overlay, catalog build, endpoints.

Real-photo checks (14 Nov 2026, see the module headers): the face check on
VITON-HD faces scaled to selfie size caught every blurred, dark, bright,
backlit, off-centre, too far / too close, two-person and empty frame; a
full request with the real models took 0.3 s. These tests pin each rule with
synthetic inputs, so they run without the models or the dataset.
"""

import base64
import io
import json
import sys
from pathlib import Path

import pytest

pytest.importorskip("cv2")
pytest.importorskip("mediapipe")

import cv2  # noqa: E402
import numpy as np  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

import services.hairstyle.main as hs  # noqa: E402
from services.cv_analysis.structure import FACE_CONTOURS  # noqa: E402
from services.hairstyle.catalog import CatalogEntry, load_catalog  # noqa: E402
from services.hairstyle.face_gate import (  # noqa: E402
    Circle,
    GateResult,
    head_pose,
    light_and_focus,
    placement,
)
from services.hairstyle.face_mesh import anchors  # noqa: E402
from services.hairstyle.overlay import (  # noqa: E402
    HairAsset,
    coverage,
    covers_eyes,
    match_light,
    render,
    transform,
)
from services.hairstyle.shape_classifier import StyleFeatures, reason_text, suitability  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import build_hairstyle_catalog as builder  # noqa: E402

# ── face shape -> style rules ───────────────────────────────────────────────


def style(gender="female", length="medium", bangs=False, wavy=False, top=0.2, side=1.3) -> StyleFeatures:
    return StyleFeatures(gender, length, bangs, wavy, top, side)


def test_bangs_suit_heart_and_oblong_faces():
    for shape in ("Heart", "Oblong"):
        assert suitability(shape, style(bangs=True)).score > suitability(shape, style()).score
    assert "forehead" in reason_text("Heart", suitability("Heart", style(bangs=True)))


def test_round_faces_want_height_not_width():
    tall = suitability("Round", style(length="long", top=0.4))
    wide = suitability("Round", style(side=1.7))
    assert tall.score > 0.6 > wide.score
    assert "height" in reason_text("Round", tall).lower()


def test_square_faces_get_waves_oval_faces_suit_anything():
    assert suitability("Square", style(wavy=True)).score > suitability("Square", style(length="short")).score
    assert suitability("Oval", style()).score >= 0.65
    assert reason_text("Oval", suitability("Oval", style(length="long"))).startswith("Oval faces")


def test_scores_stay_between_0_and_1():
    for shape in ("Oval", "Round", "Square", "Heart", "Oblong", "Diamond"):
        for f in (style(bangs=True, wavy=True, top=0.6, side=2.0), style(length="short", top=0.0, side=1.0)):
            assert 0.0 <= suitability(shape, f).score <= 1.0


def test_unknown_reason_is_neutral():
    assert reason_text("Round", suitability("Round", style())) == "A neutral choice for a round face."


# ── ranking: gender, own hair, variety ──────────────────────────────────────


def entry(i: int, **features) -> CatalogEntry:
    return CatalogEntry(id=f"s{i}", name=f"Style {i}", colour="black", features=style(**features),
                        asset=HairAsset(np.zeros((4, 4, 4), np.uint8), {}, None), source="test")


def test_rank_filters_gender_and_ranks_own_hair_showing_lower_never_refuses():
    entries = [entry(0, bangs=True), entry(1, gender="male", bangs=True), entry(2), entry(3, length="long")]
    # overlay: uncovered lists every style that passed the eye check, with how much own hair it leaves
    picked = hs.rank(entries, "Heart", "female", 6, uncovered={"s0": 0.0, "s1": 0.0, "s2": 0.0, "s3": 0.9})
    assert [e.id for e, _, _ in picked] == ["s0", "s2", "s3"]  # bangs first (heart); s3 kept, last; male out


def test_rank_drops_styles_that_failed_the_eye_check():
    entries = [entry(0, bangs=True), entry(1), entry(2)]
    # s1 is absent: it would have hung over an eye on this face
    picked = hs.rank(entries, "Heart", "female", 6, uncovered={"s0": 0.0, "s2": 0.0})
    assert [e.id for e, _, _ in picked] == ["s0", "s2"]


def test_rank_prefers_variety_before_repeats():
    entries = [entry(0, bangs=True), entry(1, bangs=True), entry(2, wavy=True)]
    picked = hs.rank(entries, "Heart", None, 2)
    assert {e.id for e, _, _ in picked} in ({"s0", "s2"}, {"s1", "s2"})  # not both bangs styles


# ── overlay geometry ────────────────────────────────────────────────────────

ASSET_ANCHORS = {"left_eye": [70.0, 50.0], "right_eye": [30.0, 50.0], "chin": [50.0, 110.0]}


def red_hair_asset() -> HairAsset:
    rgba = np.zeros((120, 100, 4), np.uint8)
    rgba[0:30, 20:80] = (0, 0, 255, 255)  # a red block above the eyes
    return HairAsset(rgba, ASSET_ANCHORS, skin_luma=None)


def test_hair_lands_where_the_anchors_say():
    user = {"left_eye": [340.0, 300.0], "right_eye": [260.0, 300.0], "chin": [300.0, 420.0]}  # twice the size
    matrix = transform(ASSET_ANCHORS, user)
    assert matrix @ np.array([50, 50, 1.0]) == pytest.approx([300, 300], abs=1e-3)
    out = render(np.full((600, 600, 3), 255, np.uint8), user, red_hair_asset())
    ys, xs = np.nonzero((out[..., 2] > 200) & (out[..., 0] < 50))
    assert ys.min() == pytest.approx(200, abs=3) and ys.max() == pytest.approx(260, abs=3)
    assert xs.min() == pytest.approx(240, abs=3) and xs.max() == pytest.approx(360, abs=3)


def test_a_style_hanging_over_an_eye_is_rejected():
    user = {"left_eye": [340.0, 300.0], "right_eye": [260.0, 300.0], "chin": [300.0, 420.0]}
    clear = np.zeros((600, 600), np.float32)
    clear[0:240] = 1.0  # hair stops above the eyes: fine, even as a fringe
    assert covers_eyes(user, clear) is False
    over = clear.copy()
    over[250:340, 230:370] = 1.0  # drops over both eyes
    assert covers_eyes(user, over) is True


def test_coverage_and_light_matching():
    own = np.zeros((10, 10), np.float32)
    own[:4] = 1.0
    new = np.zeros((10, 10), np.float32)
    new[:3] = 1.0
    assert coverage(own, new) == pytest.approx(0.25)  # one of four hair rows stays visible
    assert coverage(np.zeros((10, 10)), new) == 0.0
    rgb = np.full((2, 2, 3), 100.0)
    assert match_light(rgb, 100, 200)[0, 0, 0] == pytest.approx(135)  # clamped at x1.35
    assert match_light(rgb, None, 200)[0, 0, 0] == 100


def mesh_points(scale: float = 1.0) -> list[tuple[float, float]]:
    pts = [(0.5, 0.3)] * 478
    for i in FACE_CONTOURS["left_eye"]:
        pts[i] = (0.58, 0.30)
    for i in FACE_CONTOURS["right_eye"]:
        pts[i] = (0.42, 0.30)
    pts[234], pts[454] = (0.36, 0.33), (0.64, 0.33)  # cheekbones
    pts[10], pts[152] = (0.5, 0.18), (0.5, 0.18 + 0.336 * scale)  # forehead top, chin
    pts[54], pts[284] = (0.381, 0.22), (0.619, 0.22)
    pts[172], pts[397] = (0.388, 0.45), (0.612, 0.45)
    pts[1] = (0.5, 0.36)
    return pts


def test_anchors_from_the_mesh():
    a = anchors(mesh_points(), 1000, 1000)
    assert a == {"left_eye": [580.0, 300.0], "right_eye": [420.0, 300.0], "chin": [500.0, 516.0],
                 "forehead": [500.0, 180.0]}
    assert anchors([], 10, 10) is None


# ── face check rules ────────────────────────────────────────────────────────


def test_placement_in_the_circle():
    circle = Circle(0.5, 0.4, 0.3)  # 1000 px wide frame: radius 300 px
    assert placement((370, 320, 260, 260), 1000, 1000, circle) is None  # centred, fills 43 %
    assert placement((600, 325, 250, 250), 1000, 1000, circle) == "OFF_CENTER"
    assert placement((450, 350, 100, 100), 1000, 1000, circle) == "TOO_FAR"
    assert placement((240, 160, 520, 520), 1000, 1000, circle) == "TOO_CLOSE"
    assert placement((0, 0, 90, 90), 1000, 1000, None) == "FACE_TOO_SMALL"
    assert placement((0, 0, 200, 200), 1000, 1000, None) is None


def test_head_pose_from_dlib_points():
    straight = [(100, 100), (130, 100), (170, 100), (200, 100), (150, 140)]
    assert head_pose(straight) is None
    tilted = [(100, 100), (130, 108), (170, 118), (200, 126), (150, 150)]  # ~15 degrees
    assert head_pose(tilted) == "HEAD_TILTED"
    turned = [(100, 100), (130, 100), (170, 100), (200, 100), (185, 140)]  # nose far to one side
    assert head_pose(turned) == "FACE_TURNED"
    assert head_pose([]) == "FACE_TURNED"


def test_light_and_focus():
    rng = np.random.default_rng(0)
    sharp = rng.integers(60, 200, (400, 400, 3), dtype=np.uint8)  # lots of fine detail
    face, eyes = (100, 100, 200, 200), (120, 150, 280, 190)
    assert light_and_focus(sharp, face, eyes)[0] is None
    assert light_and_focus(cv2.GaussianBlur(sharp, (0, 0), 4), face, eyes)[0] == "BLURRY"
    assert light_and_focus((sharp * 0.2).astype(np.uint8), face, eyes)[0] == "TOO_DARK"
    bright = np.full((400, 400, 3), 240, np.uint8)
    assert light_and_focus(bright, face, eyes)[0] == "TOO_BRIGHT"
    backlit = np.full((400, 400, 3), 250, np.uint8)
    backlit[100:300, 100:300] = sharp[100:300, 100:300] // 2 + 20
    assert light_and_focus(backlit, face, eyes)[0] == "BACKLIT"


# ── catalog builder (CelebAMask-HQ format) ──────────────────────────────────


def test_read_attributes(tmp_path):
    f = tmp_path / "attrs.txt"
    f.write_text("2\nMale Bangs Wavy_Hair\n0.jpg  1 -1 -1\n1.jpg -1  1  1\n", encoding="utf-8")
    names, table = builder.read_attributes(f)
    assert names == ["Male", "Bangs", "Wavy_Hair"]
    assert table[0] == {"Male": True, "Bangs": False, "Wavy_Hair": False}
    assert table[1]["Bangs"] and table[1]["Wavy_Hair"]


def test_masks_cut_off_at_the_top_or_sides_are_rejected():
    ok = np.zeros((200, 200), bool)
    ok[20:120, 40:160] = True
    assert builder.mask_is_usable(ok) == (True, False)
    top = ok.copy()
    top[0:20, 40:160] = True
    assert builder.mask_is_usable(top)[0] is False
    side = ok.copy()
    side[20:120, 0:40] = True
    assert builder.mask_is_usable(side)[0] is False
    long = ok.copy()
    long[120:200, 50:150] = True
    assert builder.mask_is_usable(long) == (True, True)  # runs off the bottom: long hair, faded out
    pieces = np.zeros((200, 200), bool)
    pieces[20:60, 20:60] = pieces[100:140, 100:140] = True
    assert builder.mask_is_usable(pieces)[0] is False


def test_measure_length_classes():
    a = {"forehead": [100.0, 40.0], "chin": [100.0, 140.0], "left_eye": [120.0, 80.0], "right_eye": [80.0, 80.0]}
    mask = np.zeros((300, 200), bool)
    mask[10:150, 50:150] = True  # ends just below the chin
    m = builder.measure(mask, a, face_w=80.0, off_bottom=False)
    assert m["length"] == "short" and m["top_volume"] == pytest.approx(0.3) and m["side_width"] == pytest.approx(99 / 80, abs=1e-3)
    mask[150:220] = mask[149]
    assert builder.measure(mask, a, 80.0, False)["length"] == "medium"
    assert builder.measure(mask, a, 80.0, True)["length"] == "long"


def test_cutout_moves_anchors_and_fades_long_hair():
    img = np.full((200, 200, 3), 50, np.uint8)
    mask = np.zeros((200, 200), bool)
    mask[30:200, 40:160] = True
    a = {"left_eye": [120.0, 80.0], "right_eye": [80.0, 80.0], "chin": [100.0, 130.0], "forehead": [100.0, 40.0]}
    rgba, moved = builder.cutout(img, mask, off_bottom=True, a=a)
    assert rgba.shape[2] == 4
    x0, y0 = 80.0 - moved["right_eye"][0], 80.0 - moved["right_eye"][1]
    assert 28 <= x0 <= 36 and 18 <= y0 <= 26  # about 6 px (pad) before the soft edge of the mask
    assert moved["left_eye"][0] - moved["right_eye"][0] == 40.0  # every anchor moved by the same offset
    assert moved["chin"] == [100.0 - x0, 130.0 - y0]
    assert rgba[-1, :, 3].max() < 20  # the bottom edge fades out
    assert rgba[60, 60, 3] > 200


def test_select_keeps_variety_per_gender():
    def cand(i, gender="female", length="long", bangs=False, quality=0.5):
        return builder.Candidate(i, gender, length, bangs, False, "black", 0.2, 1.3, quality)

    pool = [cand(0, quality=0.9), cand(1, quality=0.8), cand(2, bangs=True, quality=0.4),
            cand(3, "male", "short"), cand(4, "male", "short", quality=0.6)]
    chosen = builder.select(pool, per_gender=2)
    assert [c.index for c in chosen] == [0, 2, 4, 3]  # best of each look before a second long-straight one


def test_style_names():
    assert builder.style_name("female", "medium", True, True) == "Shoulder-length wavy hair with bangs"
    assert builder.style_name("male", "short", False, True) == "Short textured cut with a fringe"


# ── catalog loading ─────────────────────────────────────────────────────────


def write_catalog(directory: Path, n: int = 3) -> None:
    items = []
    for i in range(n):
        rgba = np.zeros((120, 100, 4), np.uint8)
        rgba[0:30, 20:80] = (40 + 30 * i, 40, 40, 255)
        cv2.imwrite(str(directory / f"s{i}.png"), rgba)
        items.append({"id": f"s{i}", "name": f"Style {i}", "colour": "black", "file": f"s{i}.png",
                      "anchors": ASSET_ANCHORS, "skin_luma": 150.0,
                      "features": {"gender": "female", "length": ["short", "medium", "long"][i % 3], "bangs": i == 0,
                                   "wavy": False, "top_volume": 0.2, "side_width": 1.3},
                      "source": "test"})
    items.append({"id": "broken", "file": "missing.png"})
    (directory / "index.json").write_text(json.dumps(items), encoding="utf-8")


def test_load_catalog_skips_broken_entries(tmp_path):
    write_catalog(tmp_path)
    entries = load_catalog(tmp_path)
    assert [e.id for e in entries] == ["s0", "s1", "s2"]
    assert entries[0].asset.rgba.shape == (120, 100, 4)
    assert load_catalog(tmp_path / "nowhere") == []


# ── decoding ────────────────────────────────────────────────────────────────


def jpeg_b64(img_bgr: np.ndarray) -> str:
    ok, buf = cv2.imencode(".jpg", img_bgr)
    assert ok
    return base64.b64encode(buf.tobytes()).decode()


def test_decode_applies_the_phone_rotation():
    pil = Image.new("RGB", (800, 400), (10, 20, 30))
    exif = Image.Exif()
    exif[0x0112] = 6  # "rotate 90 degrees": a phone held upright
    buf = io.BytesIO()
    pil.save(buf, "JPEG", exif=exif)
    img = hs.decode(base64.b64encode(buf.getvalue()).decode())
    assert img.shape[:2] == (800, 400)  # upright


def test_decode_rejects_bad_and_tiny_images():
    with pytest.raises(hs.AppError) as bad:
        hs.decode(base64.b64encode(b"not a photo").decode())
    assert bad.value.code == "INVALID_IMAGE"
    with pytest.raises(hs.AppError) as tiny:
        hs.decode(jpeg_b64(np.zeros((100, 100, 3), np.uint8)))
    assert tiny.value.code == "IMAGE_TOO_SMALL"


# ── endpoints (stand-in models) ─────────────────────────────────────────────


class FakeGate:
    def __init__(self, result: GateResult):
        self.result = result
        self.circles = []

    def check(self, _img, circle):
        self.circles.append(circle)
        return self.result


class FakeMesh:
    def __init__(self, points):
        self.points = points

    def detect(self, _img):
        return self.points

    def close(self):
        pass


class FakeHair:
    def hair_mask(self, img):
        return np.zeros(img.shape[:2], np.float32)

    def close(self):
        pass


READY = GateResult(True, None, "Perfect, hold still!", (0.4, 0.2, 0.2, 0.2), 40.0, 120.0)


@pytest.fixture
def client(monkeypatch, tmp_path):
    write_catalog(tmp_path)

    def no_model(*_args, **_kwargs):
        raise RuntimeError("tests use stand-in models")

    # The real models aren't loaded at start-up (slow); the stand-ins are set below.
    import services.cv_analysis.face as face_module
    import services.cv_analysis.face_landmarks as mesh_module
    monkeypatch.setattr(face_module, "FaceDetector", no_model)
    monkeypatch.setattr(mesh_module, "FaceLandmarker", no_model)
    with TestClient(hs.app) as c:
        monkeypatch.setattr(hs, "_gate", FakeGate(READY))
        monkeypatch.setattr(hs, "_mesh", FakeMesh(mesh_points()))
        monkeypatch.setattr(hs, "_hair", FakeHair())
        monkeypatch.setattr(hs, "_catalog", load_catalog(tmp_path))
        yield c


def photo() -> str:
    return jpeg_b64(np.full((800, 600, 3), 170, np.uint8))


def test_face_check_passes_the_circle_through(client):
    res = client.post("/hairstyles/face-check", json={"image_base64": photo(), "circle": {"cx": 0.5, "cy": 0.4, "r": 0.3}})
    assert res.status_code == 200 and res.json()["ready"] is True
    assert hs._gate.circles == [Circle(0.5, 0.4, 0.3)]


def test_face_check_reports_the_problem(client, monkeypatch):
    monkeypatch.setattr(hs, "_gate", FakeGate(GateResult(False, "TOO_FAR", "Come a little closer.", None)))
    body = client.post("/hairstyles/face-check", json={"image_base64": photo()}).json()
    assert body == {"ready": False, "code": "TOO_FAR", "message": "Come a little closer.", "face_box": None,
                    "sharpness": None, "brightness": None}


def test_suggestions_with_previews(client):
    res = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 3})
    assert res.status_code == 200
    body = res.json()
    assert body["face_shape"] in {"Oval", "Round", "Square", "Heart", "Oblong", "Diamond"}
    assert len(body["alternatives"]) == 2
    ids = [body["default"]["hairstyle_id"]] + [a["hairstyle_id"] for a in body["alternatives"]]
    assert sorted(ids) == ["s0", "s1", "s2"]
    for b64 in [body["original_base64"], body["default"]["preview_base64"]]:
        img = cv2.imdecode(np.frombuffer(base64.b64decode(b64), np.uint8), cv2.IMREAD_COLOR)
        assert img is not None and img.shape[0] > 0
    assert body["default"]["reason"].endswith(".")


def test_male_users_only_get_male_styles(client):
    """The test catalog has no men's styles: a setup problem, never blamed on the user's hair."""
    res = client.post("/hairstyles", json={"image_base64": photo(), "gender": "male"})
    assert res.status_code == 503 and res.json()["error"]["code"] == "CATALOG_MISSING"


def test_a_photo_that_fails_the_face_check_is_refused(client, monkeypatch):
    monkeypatch.setattr(hs, "_gate", FakeGate(GateResult(False, "BLURRY", "Hold still, the picture is blurry.")))
    res = client.post("/hairstyles", json={"image_base64": photo()})
    err = res.json()["error"]
    assert res.status_code == 422 and err["code"] == "BLURRY" and err["details"]["reason"] == "BLURRY"


def test_turned_face_has_no_face_shape(client, monkeypatch):
    pts = mesh_points()
    pts[1] = (0.40, 0.36)  # nose far to one side
    monkeypatch.setattr(hs, "_mesh", FakeMesh(pts))
    res = client.post("/hairstyles", json={"image_base64": photo()})
    assert res.status_code == 422 and res.json()["error"]["code"] == "FACE_TURNED"


def test_no_catalog_or_no_models_is_503(client, monkeypatch):
    monkeypatch.setattr(hs, "_catalog", [])
    res = client.post("/hairstyles", json={"image_base64": photo()})
    assert res.status_code == 503 and res.json()["error"]["code"] == "CATALOG_MISSING"
    monkeypatch.setattr(hs, "_gate", None)
    assert client.post("/hairstyles/face-check", json={"image_base64": photo()}).status_code == 503


def test_health_reports_the_catalog(client):
    health = client.get("/health").json()
    assert health["implemented"] is True and health["catalog_styles"] == 3


# ── spec §23.27: nobody refused, AI previews, personal fit ─────────────────

class FullHair(FakeHair):
    """Long, full hair everywhere around the face (the photo that used to be refused)."""

    def hair_mask(self, img):
        m = np.ones(img.shape[:2], np.float32)
        h, w = m.shape
        m[int(h * 0.25):int(h * 0.75), int(w * 0.3):int(w * 0.7)] = 0.0  # the face
        return m


def test_long_full_hair_is_never_refused(client, monkeypatch):
    monkeypatch.setattr(hs, "_hair", FullHair())
    res = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 3})
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["renderer"] == "overlay" and body["default"]["renderer"] == "overlay"
    assert body["hair_length"] == "long" and body["skipped_shorter"] == 0


def test_ai_previews_come_from_the_gpu(client, monkeypatch):
    from services.hairstyle import gpu_client

    calls = {}

    def fake_render(face_jpeg, ids, timeout=None):
        calls["ids"] = ids
        assert face_jpeg[:2] == b"\xff\xd8"  # a JPEG of the whole photo
        ok = cv2.imencode(".jpg", np.full((64, 64, 3), 90, np.uint8))[1].tobytes()
        return {"ok": True, "original": ok, "previews": {i: ok for i in ids[:-1]}, "failed": {ids[-1]: "x"}}

    monkeypatch.setattr(gpu_client, "enabled", lambda: True)
    monkeypatch.setattr(gpu_client, "render", fake_render)
    body = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 3}).json()
    assert body["renderer"] == "ai" and body["note"] == ""
    shown = [body["default"]["hairstyle_id"]] + [a["hairstyle_id"] for a in body["alternatives"]]
    assert shown == calls["ids"][:-1]  # same order as ranked; the style that failed is left out
    assert all(p["renderer"] == "ai" for p in [body["default"], *body["alternatives"]])


def test_gpu_trouble_falls_back_to_the_overlay_and_says_so(client, monkeypatch):
    from services.hairstyle import gpu_client

    monkeypatch.setattr(gpu_client, "enabled", lambda: True)
    monkeypatch.setattr(gpu_client, "render", lambda *a, **k: None)
    body = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 2}).json()
    assert body["renderer"] == "overlay" and "isn't available right now" in body["note"]


def test_face_check_warms_the_gpu(client, monkeypatch):
    from services.hairstyle import gpu_client

    warmed = []
    monkeypatch.setattr(gpu_client, "warm", lambda: warmed.append(1))
    client.post("/hairstyles/face-check", json={"image_base64": photo()})
    assert warmed == [1]


def test_the_users_own_texture_wins(client):
    body = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 2,
                                            "hair_texture": "wavy", "occasion": "mehndi"}).json()
    assert body["hair_texture"] == "wavy" and body["hair_texture_source"] == "user"


def test_personal_fit_rules():
    from services.hairstyle.personal_fit import personal_fit
    from services.hairstyle.shape_classifier import StyleFeatures

    def style(length="medium", wavy=False, top=0.2, side=1.2):
        return StyleFeatures(gender="female", length=length, bangs=False, wavy=wavy, top_volume=top, side_width=side)

    grow, _ = personal_fit(style("long"), "short", None, None)
    same, why = personal_fit(style("short"), "short", None, None)
    assert grow < 0 < same and "current length" in why[0]
    wavy_match, why = personal_fit(style(wavy=True), None, True, None)
    assert wavy_match > 0 and why == ["suits your natural waves"]
    assert personal_fit(style(wavy=True), None, False, None)[0] < 0
    formal, why = personal_fit(style(), None, None, "Nikah")
    assert formal > 0 and why == ["neat enough for nikah"]
    festive, why = personal_fit(style(wavy=True), None, None, "mehndi")
    assert festive > 0 and why == ["has the volume for mehndi"]
    assert personal_fit(style(), None, None, None) == (0.0, [])


def test_hair_length_uses_the_catalogs_rule():
    from services.hairstyle.hair_profile import hair_length

    a = {"forehead": [50.0, 20.0], "chin": [50.0, 120.0], "left_eye": [60.0, 50.0], "right_eye": [40.0, 50.0]}
    m = np.zeros((400, 100), bool)
    m[0:30] = True
    assert hair_length(m, a) == "short"
    m[0:160] = True  # 0.4 face lengths below the chin
    assert hair_length(m, a) == "medium"
    m[:] = False
    m[0:400] = True  # off the bottom of the photo
    assert hair_length(m, a) == "long"
    assert hair_length(np.zeros((400, 100), bool), a) is None


def test_gpu_client_is_off_without_the_setting_and_never_raises(monkeypatch):
    from services.hairstyle import gpu_client
    from shared.config import settings

    gpu_client.reset()
    monkeypatch.setattr(settings, "hairstyle_backend", "")
    assert not gpu_client.enabled() and gpu_client.render(b"x", ["a"]) is None
    gpu_client.warm()  # no-op

    class Broken:
        def __call__(self):
            return self

        @property
        def render(self):
            raise RuntimeError("modal down")

    monkeypatch.setattr(settings, "hairstyle_backend", "modal")
    monkeypatch.setattr(gpu_client, "_cls", Broken())
    assert gpu_client.render(b"x", ["a"]) is None
    gpu_client.reset()


# ── SFR-029: the chosen outfit's style category (20 Nov 2026) ─────────────────


def test_outfit_style_categories():
    from services.hairstyle.personal_fit import outfit_style

    assert outfit_style("Embroidered Sherwani, sherwani") == "formal"
    assert outfit_style("Wool Blazer") == "formal"
    assert outfit_style("Bridal Lehenga") == "festive"
    assert outfit_style("Embroidered Chiffon Formals") == "festive"  # Pakistani "formals" = party wear
    assert outfit_style("2 Piece Embroidered Lawn Suit") == "casual"  # day wear, not a formal suit
    assert outfit_style("Activewear Graphic T-Shirt") == "sporty"
    assert outfit_style("Relaxed Fit Hoodie") == "casual"
    assert outfit_style("Relaxed Fit Trousers") is None and outfit_style(None) is None


def test_outfit_steers_the_suggestions():
    from services.hairstyle.personal_fit import personal_fit
    from services.hairstyle.shape_classifier import StyleFeatures

    sleek = StyleFeatures(gender="female", length="medium", bangs=False, wavy=False, top_volume=0.2, side_width=1.2)
    waves = StyleFeatures(gender="female", length="long", bangs=False, wavy=True, top_volume=0.2, side_width=1.2)
    d, why = personal_fit(sleek, None, None, None, "Prince Coat")
    assert d > 0 and why == ["neat enough for your formal outfit"]
    d, why = personal_fit(waves, None, None, None, "Bridal Lehenga")
    assert d > 0 and why == ["has the volume to match your festive outfit"]
    assert personal_fit(sleek, None, None, None, "Bridal Lehenga") == (0.0, [])  # no volume: no bonus
    d, why = personal_fit(waves, None, None, None, "Graphic Tee")
    assert d > 0 and why == ["relaxed, like your casual outfit"]
    assert personal_fit(sleek, None, None, None, None) == (0.0, [])


def test_the_outfit_reaches_the_ranking_and_previews_carry_a_thumbnail(client):
    body = client.post("/hairstyles", json={"image_base64": photo(), "gender": "female", "count": 3,
                                            "outfit": "Bridal Lehenga, lehenga"}).json()
    for p in [body["default"], *body["alternatives"]]:
        thumb = cv2.imdecode(np.frombuffer(base64.b64decode(p["thumb_base64"]), np.uint8), cv2.IMREAD_COLOR)
        assert thumb is not None and thumb.shape[1] <= 160  # small, for the wardrobe card
    assert client.post("/hairstyles", json={"image_base64": photo(), "outfit": "x" * 161}).status_code == 422
