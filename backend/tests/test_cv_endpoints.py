"""CV service endpoints (FastAPI TestClient) with stand-in pose/face models.

Real-model behaviour is checked separately on real photos
(scripts/evaluate_cv.py); these tests pin down the wiring and every
structured error the client can receive.
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
from services.cv_analysis.face import FaceBox  # noqa: E402

W, H = 400, 800
FACE = FaceBox(x=160, y=40, w=80, h=80, score=0.95)


def _person(ankles_visible: bool = True) -> list[LandmarkPoint]:
    pts = [LandmarkPoint(0.5, 0.5, 0.0, 0.9) for _ in range(33)]
    pts[0] = LandmarkPoint(0.5, 0.10, 0, 0.9)
    pts[11], pts[12] = LandmarkPoint(0.40, 0.25, 0, 0.9), LandmarkPoint(0.60, 0.25, 0, 0.9)
    pts[23], pts[24] = LandmarkPoint(0.44, 0.55, 0, 0.9), LandmarkPoint(0.56, 0.55, 0, 0.9)
    ankle_vis = 0.9 if ankles_visible else 0.1
    pts[27], pts[28] = LandmarkPoint(0.48, 0.95, 0, ankle_vis), LandmarkPoint(0.52, 0.95, 0, ankle_vis)
    return pts


class FakePose:
    def __init__(self, people):
        self.people = people

    def detect_people(self, _img):
        return self.people

    def close(self):
        pass


class FakeFaces:
    def __init__(self, faces):
        self.faces = faces

    def detect(self, _img):
        return self.faces

    def close(self):
        pass


def _photo(brightness: int = 200, size: tuple[int, int] = (W, H)) -> bytes:
    w, h = size
    img = np.full((h, w, 3), brightness, dtype=np.uint8)
    # Light-medium skin patch where the fake face is (BGR).
    img[FACE.y : FACE.y + FACE.h, FACE.x : FACE.x + FACE.w] = (120, 160, 210)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


@pytest.fixture
def client(monkeypatch):
    with TestClient(main.app) as c:  # real lifespan, then swap in fakes
        monkeypatch.setattr(main, "_pose", FakePose([_person()]))
        monkeypatch.setattr(main, "_faces", FakeFaces([FACE]))
        yield c


def _analyze(client, photo=None, **form):
    data = {"height_cm": "165", **form}
    return client.post("/analyze", files={"image": ("me.jpg", photo or _photo(), "image/jpeg")}, data=data)


def _code(res):
    return res.json()["error"]["code"]


def test_spec_contract_success_with_measurements(client):
    res = _analyze(client, chest_cm="92", waist_cm="68", hip_cm="94", gender="female")
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["body_type"] == "hourglass"
    assert body["body_type_source"] == "measurements"
    assert set(body["measurements"]) == {"shoulder_cm", "hip_cm", "torso_cm"}
    assert all(v > 0 for v in body["measurements"].values())
    assert body["skin_tone"] in {"fair", "light", "medium", "tan", "brown", "deep"}
    assert body["estimated_size"] in {"S", "M", "L", "XL"}
    assert isinstance(body["processing_time_ms"], int)


def test_spec_photo_only_uses_pose(client):
    body = _analyze(client).json()
    assert body["body_type_source"] == "pose"
    assert body["body_type"] in {"triangle", "rectangle", "inverted_triangle"}


@pytest.mark.parametrize(
    ("people", "faces", "code"),
    [
        ([], [FACE], "NO_PERSON_DETECTED"),
        ([_person(), _person()], [FACE], "MULTIPLE_PEOPLE"),
        ([_person(ankles_visible=False)], [FACE], "PARTIAL_BODY"),
        ([_person()], [], "NO_FACE_DETECTED"),
    ],
)
def test_spec_structured_errors(client, monkeypatch, people, faces, code):
    monkeypatch.setattr(main, "_pose", FakePose(people))
    monkeypatch.setattr(main, "_faces", FakeFaces(faces))
    res = _analyze(client)
    assert res.status_code == 422
    assert _code(res) == code
    assert res.json()["error"]["message"]


def test_spec_photo_quality_errors(client):
    assert _code(_analyze(client, _photo(size=(200, 200)))) == "IMAGE_TOO_SMALL"
    assert _code(_analyze(client, _photo(brightness=10))) == "POOR_LIGHTING"
    assert _code(_analyze(client, b"not an image")) == "INVALID_IMAGE"


def test_spec_requires_height(client):
    res = client.post("/analyze", files={"image": ("me.jpg", _photo(), "image/jpeg")})
    assert res.status_code == 422 and _code(res) == "VALIDATION_ERROR"


def test_app_endpoint_keeps_its_labels(client):
    b64 = base64.b64encode(_photo()).decode()
    body = client.post(
        "/analyze/app",
        json={"image_base64": b64, "gender": "female", "height_cm": 165, "chest_cm": 92, "waist_cm": 68, "hip_cm": 94},
    ).json()
    assert body["success"] is True and body["error"] is None
    assert body["body_shape"] == "Hourglass"
    assert body["skin_tone"]["tone_label"] in {"Fair", "Light", "Medium", "Olive", "Brown", "Dark"}
    assert body["estimated_gender"] == "uncertain"
    assert len(body["pose_landmarks"]) == 33


def test_app_endpoint_is_lenient(client, monkeypatch):
    # Partial body and no face: the app still gets a body type and a size.
    monkeypatch.setattr(main, "_pose", FakePose([_person(ankles_visible=False)]))
    monkeypatch.setattr(main, "_faces", FakeFaces([]))
    b64 = base64.b64encode(_photo()).decode()
    body = client.post("/analyze/app", json={"image_base64": b64, "height_cm": 165}).json()
    assert body["success"] is True and body["error"] is None
    assert body["body_shape"] in {"Pear", "Rectangle", "Inverted Triangle"}
    assert body["skin_tone"] is None

    monkeypatch.setattr(main, "_pose", FakePose([]))
    body = client.post("/analyze/app", json={"image_base64": b64, "chest_cm": 95, "gender": "male"}).json()
    assert body["success"] is True and "couldn't find a person" in body["error"]
    assert body["estimated_size"] == "M"
