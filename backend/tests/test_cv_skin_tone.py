"""Skin tone: ITA thresholds and sampling (spec §6.2 step 6)."""

import pytest

pytest.importorskip("cv2")

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from services.cv_analysis.face import FaceBox  # noqa: E402
from services.cv_analysis.skin_tone import (  # noqa: E402
    APP_SKIN_LABELS,
    FITZPATRICK,
    SKIN_TONES,
    analyze_skin_tone,
    bucket_from_ita,
    ita_degrees,
)


@pytest.mark.parametrize(
    ("ita", "bucket"),
    [(60, "fair"), (55.1, "fair"), (55, "light"), (45, "light"), (30, "medium"), (20, "tan"), (0, "brown"),
     (-29.9, "brown"), (-30, "deep"), (-50, "deep")],
)
def test_published_ita_thresholds(ita, bucket):
    assert bucket_from_ita(ita) == bucket


def test_ita_formula():
    assert ita_degrees(50, 10) == pytest.approx(0.0)
    assert ita_degrees(70, 20) == pytest.approx(45.0)


def test_every_bucket_maps_to_app_label_and_fitzpatrick():
    assert set(APP_SKIN_LABELS) == set(SKIN_TONES) == set(FITZPATRICK)


def _face_image(bgr: tuple[int, int, int]) -> tuple[np.ndarray, FaceBox]:
    img = np.full((400, 400, 3), 240, dtype=np.uint8)
    img[100:300, 100:300] = bgr
    return img, FaceBox(100, 100, 200, 200, 0.9)


def _lab_bucket(bgr):
    lab = cv2.cvtColor(np.array([[bgr]], dtype=np.float32) / 255.0, cv2.COLOR_BGR2Lab)[0, 0]
    return bucket_from_ita(ita_degrees(float(lab[0]), float(lab[2])))


@pytest.mark.parametrize("bgr", [(180, 205, 240), (110, 150, 200), (60, 90, 140), (30, 50, 80)])
def test_analysis_matches_the_colour_it_sees(bgr):
    img, face = _face_image(bgr)
    result = analyze_skin_tone(img, face)
    assert result is not None
    bucket, tone = result
    assert bucket == _lab_bucket(bgr)
    assert tone.tone_label == APP_SKIN_LABELS[bucket]


def test_lighter_skin_never_lands_darker_than_darker_skin():
    order = []
    for bgr in [(180, 205, 240), (110, 150, 200), (60, 90, 140), (30, 50, 80)]:
        img, face = _face_image(bgr)
        order.append(SKIN_TONES.index(analyze_skin_tone(img, face)[0]))
    assert order == sorted(order)


def test_non_skin_face_region_returns_none():
    img, face = _face_image((255, 0, 0))  # pure blue: no skin pixels
    assert analyze_skin_tone(img, face) is None
