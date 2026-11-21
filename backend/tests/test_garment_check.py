"""The clothes-photo check (recommendation service, POST /garment/check) used
by try-on with the user's own clothes. A fake embedder stands in for
FashionCLIP: it maps the photo's colour and each description's group to
vectors, so the zero-shot maths is tested without the model. (The real model
was checked on 49 dataset photos: all correctly classified, 14 Nov 2026.)"""

import base64
import io

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

import services.recommendation.main as rec
from services.recommendation.garment_check import PROMPTS, SLEEVE_PROMPTS, GarmentClassifier

COLOUR_GROUP = {(255, 0, 0): "upper", (0, 255, 0): "lower", (0, 0, 255): "dress", (90, 90, 90): "other"}
AXIS = {"upper": 0, "lower": 1, "dress": 2, "other": 3, "long sleeve": 4, "short sleeve": 5, "sleeveless": 6}
# The bottom-right pixel says the sleeve length (any other colour: no clear sleeve).
COLOUR_SLEEVE = {(250, 250, 0): "long sleeve", (0, 250, 250): "short sleeve", (250, 0, 250): "sleeveless"}


class FakeEmbedder:
    def embed_texts(self, texts):
        out = np.zeros((len(texts), 7), dtype=np.float32)
        for i, t in enumerate(texts):
            group = next(g for g, prompts in (PROMPTS | SLEEVE_PROMPTS).items() if t in prompts)
            out[i, AXIS[group]] = 1.0
        return out

    def embed_images(self, images):
        out = np.zeros((len(images), 7), dtype=np.float32)
        for i, img in enumerate(images):
            out[i, AXIS[COLOUR_GROUP[img.getpixel((0, 0))]]] = 1.0
            sleeve = COLOUR_SLEEVE.get(img.getpixel((img.width - 1, img.height - 1)))
            if sleeve:
                out[i, AXIS[sleeve]] = 1.0
        return out


def photo(colour) -> Image.Image:
    return Image.new("RGB", (300, 400), colour)


def test_each_kind_is_recognised_and_scores_sum_to_one():
    c = GarmentClassifier(FakeEmbedder())
    for colour, group in COLOUR_GROUP.items():
        scores = c.scores(photo(colour))
        assert max(scores, key=scores.get) == group and scores[group] > 0.99
        assert abs(sum(scores.values()) - 1) < 1e-3


def test_endpoint_answers_and_rejects_unreadable_images(monkeypatch):
    monkeypatch.setattr(rec, "_embedder", FakeEmbedder())
    monkeypatch.setattr(rec, "_garment_classifier", None)
    buf = io.BytesIO()
    photo((0, 255, 0)).save(buf, "PNG")  # lossless: the fake reads the exact colour
    with TestClient(rec.app) as client:
        res = client.post("/garment/check", json={"image_base64": base64.b64encode(buf.getvalue()).decode()})
        assert res.status_code == 200 and res.json()["best"] == "lower"
        bad = client.post("/garment/check", json={"image_base64": "x" * 200})
        assert bad.status_code == 422 and bad.json()["error"]["code"] == "INVALID_IMAGE"


def test_endpoint_says_when_the_model_is_not_ready(monkeypatch):
    monkeypatch.setattr(rec, "_embedder", None)
    monkeypatch.setattr(rec, "_model_error", None)
    with TestClient(rec.app) as client:
        res = client.post("/garment/check", json={"image_base64": "x" * 200})
        assert res.status_code == 503


# ── sleeve length (20 Nov 2026: in the try-on caption) ──────────────────────


def sleeved(kind_colour, sleeve_colour) -> Image.Image:
    img = photo(kind_colour)
    img.putpixel((img.width - 1, img.height - 1), sleeve_colour)
    return img


def test_sleeve_length_is_read_when_clear():
    c = GarmentClassifier(FakeEmbedder())
    for colour, sleeve in COLOUR_SLEEVE.items():
        kinds, found, p = c.check(sleeved((255, 0, 0), colour))
        assert found == sleeve and p >= 0.8 and max(kinds, key=kinds.get) == "upper"


def test_unclear_sleeve_is_none():
    kinds, found, p = GarmentClassifier(FakeEmbedder()).check(photo((255, 0, 0)))  # no sleeve signal
    assert found is None and p < 0.8


def test_endpoint_reports_the_sleeve(monkeypatch):
    monkeypatch.setattr(rec, "_require_model", lambda: FakeEmbedder())
    monkeypatch.setattr(rec, "_garment_classifier", None)
    monkeypatch.setattr(rec.settings, "fashionclip_autoload", False)
    buf = io.BytesIO()
    sleeved((0, 0, 255), (250, 0, 250)).save(buf, "PNG")
    with TestClient(rec.app) as client:
        body = client.post("/garment/check", json={"image_base64": base64.b64encode(buf.getvalue()).decode()}).json()
    assert body["best"] == "dress" and body["sleeve"] == "sleeveless" and body["sleeve_probability"] >= 0.8
