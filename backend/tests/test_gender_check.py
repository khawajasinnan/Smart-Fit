"""The try-on gender checks' classifier (services/recommendation/gender_check.py):
only confident answers count; a missing model never blocks anything."""

from __future__ import annotations

import base64
import io

import joblib
import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sklearn.linear_model import LogisticRegression

import services.recommendation.main as rec
from services.recommendation.gender_check import GenderChecker


class FakeEmbedder:
    """Image -> a 2-d vector: (red, blue) share, so "pink" and "blue" are easy to tell apart."""

    def embed_images(self, images):
        out = []
        for img in images:
            r, _, b = np.asarray(img.convert("RGB"), dtype=float).reshape(-1, 3).mean(0)
            out.append([r / 255, b / 255])
        return np.asarray(out, dtype=np.float32)


def solid(colour) -> Image.Image:
    return Image.new("RGB", (64, 64), colour)


@pytest.fixture
def model_dir(tmp_path):
    x = np.asarray([[1, 0], [0.9, 0.1], [0, 1], [0.1, 0.9]], dtype=float)
    y = np.asarray([1, 1, 0, 0])  # 1 = second label (women / woman)
    for kind, labels in (("garment", ("men", "women")), ("face", ("man", "woman"))):
        m = LogisticRegression(C=100).fit(x, y)
        joblib.dump({"model": m, "labels": labels, "threshold": 0.85}, tmp_path / f"{kind}_gender.joblib")
    return tmp_path


def test_confident_answers(model_dir):
    c = GenderChecker(FakeEmbedder(), model_dir)
    assert c.check(solid((255, 0, 0)), "garment").label == "women"
    assert c.check(solid((0, 0, 255)), "garment").label == "men"
    assert c.check(solid((255, 0, 0)), "face").label == "woman"


def test_unsure_is_none(model_dir):
    v = GenderChecker(FakeEmbedder(), model_dir).check(solid((128, 0, 128)), "garment")  # half way
    assert v.label is None and v.available


def test_one_threshold_per_side(model_dir):
    import joblib as jl

    bundle = jl.load(model_dir / "face_gender.joblib")
    bundle["thresholds"] = (0.99, 0.6)  # "man" needs 0.99, "woman" only 0.6
    jl.dump(bundle, model_dir / "face_gender.joblib")
    c = GenderChecker(FakeEmbedder(), model_dir)
    leaning_woman = solid((200, 0, 90))
    leaning_man = solid((90, 0, 200))
    assert c.check(leaning_woman, "face").label == "woman"
    assert c.check(leaning_man, "face").label is None  # not sure enough for "man"


def test_person_needs_the_whole_photo_to_agree(model_dir):
    c = GenderChecker(FakeEmbedder(), model_dir)
    womanly_face = solid((255, 0, 0))
    assert c.check_person(womanly_face, solid((255, 0, 0))).label == "woman"  # photo agrees
    assert c.check_person(womanly_face, solid((0, 0, 255))).label is None  # photo disagrees: not sure
    assert c.check_person(womanly_face, None).label == "woman"  # no photo: the face alone


def test_person_without_the_garment_model_uses_the_face_alone(model_dir):
    (model_dir / "garment_gender.joblib").unlink()
    c = GenderChecker(FakeEmbedder(), model_dir)
    assert c.check_person(solid((255, 0, 0)), solid((0, 0, 255))).label == "woman"


def test_a_missing_model_is_reported_not_guessed(tmp_path):
    v = GenderChecker(FakeEmbedder(), tmp_path).check(solid((255, 0, 0)), "face")
    assert v.label is None and v.available is False


def test_endpoint(model_dir, monkeypatch):
    monkeypatch.setattr(rec, "_require_model", lambda: FakeEmbedder())
    monkeypatch.setattr(rec, "_gender_checker", GenderChecker(FakeEmbedder(), model_dir))
    monkeypatch.setattr(rec.GenderChecker, "__init__", lambda self, e: None)  # never reload from disk
    buf = io.BytesIO()
    solid((255, 0, 0)).save(buf, "JPEG")
    img = base64.b64encode(buf.getvalue()).decode()
    monkeypatch.setattr(rec.settings, "fashionclip_autoload", False)
    with TestClient(rec.app) as client:
        checker = rec._gender_checker
        checker._embedder = rec._require_model()  # same object as the endpoint's
        monkeypatch.setattr(rec, "_require_model", lambda: checker._embedder)
        res = client.post("/gender/check", json={"image_base64": img, "kind": "garment"})
        assert res.status_code == 200 and res.json()["label"] == "women" and res.json()["available"]
        bad = client.post("/gender/check", json={"image_base64": "x" * 200, "kind": "face"})
        assert bad.status_code == 422
        buf = io.BytesIO()
        solid((0, 0, 255)).save(buf, "JPEG")
        blue = base64.b64encode(buf.getvalue()).decode()
        res = client.post("/gender/check", json={"image_base64": img, "kind": "face", "photo_base64": blue})
        assert res.status_code == 200 and res.json()["label"] is None  # face and photo disagree
        res = client.post("/gender/check", json={"image_base64": img, "kind": "face", "photo_base64": img})
        assert res.json()["label"] == "woman"
