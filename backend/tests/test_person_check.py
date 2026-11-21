"""Try-on photo check (HRNet keypoints -> usable or a precise reason).

Real-photo check (14 Nov 2026, services/cv_analysis/person_check.py header):
177/180 DressCode people accepted, 119/120 clothes-only photos refused,
rotated / two-person / tiny photos refused. These tests pin each rule.
"""

import base64

import pytest

pytest.importorskip("cv2")
pytest.importorskip("mediapipe")

import cv2  # noqa: E402
import numpy as np  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from services.cv_analysis import main  # noqa: E402
from services.cv_analysis.body_classifier import LandmarkPoint  # noqa: E402
from services.cv_analysis.hrnet import INDEX, Keypoint  # noqa: E402
from services.cv_analysis.person_check import check_person  # noqa: E402

STANDING = {  # a person standing straight, filling the photo (x, y)
    "nose": (0.50, 0.10), "left_eye": (0.52, 0.09), "right_eye": (0.48, 0.09),
    "left_shoulder": (0.60, 0.22), "right_shoulder": (0.40, 0.22),
    "left_elbow": (0.63, 0.36), "right_elbow": (0.37, 0.36),
    "left_hip": (0.56, 0.50), "right_hip": (0.44, 0.50),
    "left_knee": (0.56, 0.70), "right_knee": (0.44, 0.70),
    "left_ankle": (0.56, 0.90), "right_ankle": (0.44, 0.90),
}


def kps(drop=(), conf=0.85, override=None):
    points = {**STANDING, **(override or {})}
    out: list[Keypoint | None] = [None] * 17
    for name, (x, y) in points.items():
        if name not in drop:
            out[INDEX[name]] = Keypoint(x, y, conf)
    return out


def check(keypoints, people=1, category="upper", angle="front"):
    return check_person(keypoints, people, category, angle, 768, 1024)


def test_a_good_full_body_photo_passes_for_every_garment():
    for category in ("upper", "lower", "dress"):
        assert check(kps(), category=category).ok


def test_more_than_one_person():
    assert check(kps(), people=2).code == "MULTIPLE_PEOPLE"


def test_no_body():
    assert check(kps(drop=("left_hip", "right_hip"))).code == "NO_PERSON"
    assert check([None] * 17).code == "NO_PERSON"


def test_clothes_alone_are_not_a_person():
    # MediaPipe found nobody and HRNet is only fairly sure: a garment's shape
    assert check(kps(conf=0.7), people=0).code == "NO_PERSON"
    # ... but a very confident HRNet result is still accepted (MediaPipe can miss)
    assert check(kps(conf=0.9), people=0).ok
    # with a person found, a low-confidence skeleton is still refused
    assert check(kps(conf=0.5), people=1).code == "NO_PERSON"


def test_front_needs_both_sides_but_a_side_view_does_not():
    side = kps(drop=("left_shoulder", "left_hip"))
    assert check(side, angle="front").code == "NO_PERSON"
    assert check(side, angle="right").ok


def test_lying_down_or_upside_down():
    lying = kps(override={"left_shoulder": (0.2, 0.52), "right_shoulder": (0.2, 0.48),
                          "left_hip": (0.6, 0.52), "right_hip": (0.6, 0.48)})
    assert check(lying).code == "POSE_NOT_UPRIGHT"
    upside = kps(override={"left_shoulder": (0.6, 0.6), "right_shoulder": (0.4, 0.6),
                           "left_hip": (0.56, 0.3), "right_hip": (0.44, 0.3)})
    assert check(upside).code == "POSE_NOT_UPRIGHT"


def test_too_far_away():
    tiny = kps(override={"left_shoulder": (0.52, 0.45), "right_shoulder": (0.48, 0.45),
                         "left_hip": (0.51, 0.55), "right_hip": (0.49, 0.55)})
    assert check(tiny).code == "PERSON_TOO_SMALL"


def test_front_photo_needs_the_head_back_photo_does_not():
    headless = kps(drop=("nose", "left_eye", "right_eye"))
    assert check(headless).code == "BODY_CUT_OFF"
    assert check(headless, angle="back").ok


def test_trousers_need_ankles_a_dress_needs_knees_or_ankles():
    no_ankles = kps(drop=("left_ankle", "right_ankle"))
    assert check(no_ankles, category="lower").code == "BODY_CUT_OFF"
    assert check(no_ankles, category="dress").ok
    assert check(no_ankles, category="upper").ok
    long_dress = kps(drop=("left_knee", "right_knee"))  # knees hidden under a long kameez
    assert check(long_dress, category="dress").ok
    thighs_up = kps(drop=("left_knee", "right_knee", "left_ankle", "right_ankle"))
    assert check(thighs_up, category="dress").code == "BODY_CUT_OFF"
    assert check(thighs_up, category="upper").ok


# ── POST /pose/check wiring ─────────────────────────────────────────────────


class FakePose:
    def __init__(self, people):
        self.people = people

    def detect_people(self, _img):
        return self.people

    def close(self):
        pass


class FakeHRNet:
    def __init__(self, keypoints):
        self.keypoints = keypoints
        self.boxes = []

    def detect(self, _img, landmarks=None):
        self.boxes.append(landmarks)
        return self.keypoints

    def close(self):
        pass


def _jpeg_b64() -> str:
    ok, buf = cv2.imencode(".jpg", np.full((1024, 768, 3), 180, np.uint8))
    assert ok
    return base64.b64encode(buf.tobytes()).decode()


@pytest.fixture
def client(monkeypatch):
    def no_model(*_args, **_kwargs):
        raise RuntimeError("tests use stand-in models")

    # The real models aren't loaded at start-up (slow); each test sets stand-ins.
    for name in ("PoseEstimator", "FaceDetector", "FaceLandmarker", "HRNetEstimator"):
        monkeypatch.setattr(main, name, no_model)
    with TestClient(main.app) as c:
        yield c


def test_endpoint_returns_the_verdict_and_keypoints(client, monkeypatch):
    person = [LandmarkPoint(0.5, 0.5, 0, 0.9)] * 33
    hrnet = FakeHRNet(kps(drop=("left_ankle", "right_ankle")))
    monkeypatch.setattr(main, "_pose", FakePose([person]))
    monkeypatch.setattr(main, "_hrnet", hrnet)
    res = client.post("/pose/check", json={"image_base64": _jpeg_b64(), "category": "lower", "angle": "front"})
    body = res.json()
    assert res.status_code == 200
    assert body["ok"] is False and body["code"] == "BODY_CUT_OFF" and body["people"] == 1
    assert {k["name"] for k in body["keypoints"]} == set(STANDING) - {"left_ankle", "right_ankle"}
    assert hrnet.boxes == [person]  # HRNet is boxed on MediaPipe's person


def test_endpoint_without_models_is_503(client, monkeypatch):
    monkeypatch.setattr(main, "_hrnet", None)
    res = client.post("/pose/check", json={"image_base64": _jpeg_b64()})
    assert res.status_code == 503


def test_endpoint_rejects_a_broken_image(client, monkeypatch):
    monkeypatch.setattr(main, "_pose", FakePose([]))
    monkeypatch.setattr(main, "_hrnet", FakeHRNet([None] * 17))
    res = client.post("/pose/check", json={"image_base64": base64.b64encode(b"not an image").decode()})
    assert res.status_code == 422 and res.json()["error"]["code"] == "INVALID_IMAGE"
