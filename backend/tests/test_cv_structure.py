"""Detailed scan: face shape, shoulders, MediaPipe/HRNet agreement, the
HRNet top-down crop and heatmap decoding, and the /analyze/app "detailed" wiring.

Real-model check (14 Nov 2026): on VITON-HD photos HRNet's joints lie a
median 4.2 % of shoulder width from MediaPipe's (p90 8.7 %); these tests pin
the geometry and the contract with stand-in models.
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
from services.cv_analysis.hrnet import (  # noqa: E402
    HEATMAP_H,
    HEATMAP_W,
    INPUT_H,
    INPUT_W,
    Keypoint,
    box_to_center_scale,
    crop_transform,
    decode_heatmaps,
    person_box,
)
from services.cv_analysis.structure import (  # noqa: E402
    classify_face_shape,
    face_structure,
    model_agreement,
    shoulder_analysis,
)

# ── Face shape ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("length", "forehead", "jaw", "shape"),
    [
        (1.40, 0.86, 0.79, "Oblong"),
        (1.20, 0.86, 0.85, "Square"),
        (1.12, 0.86, 0.82, "Square"),
        (1.12, 0.86, 0.78, "Round"),
        (1.22, 0.90, 0.76, "Heart"),
        (1.22, 0.82, 0.76, "Diamond"),
        (1.22, 0.86, 0.79, "Oval"),
    ],
)
def test_classify_face_shape(length, forehead, jaw, shape):
    assert classify_face_shape(length, forehead, jaw) == shape


def _mesh(nose_x: float = 0.5) -> list[tuple[float, float]]:
    pts = [(0.5, 0.3)] * 478
    pts[234], pts[454] = (0.40, 0.30), (0.60, 0.30)  # cheekbones: 0.20 wide
    pts[10], pts[152] = (0.50, 0.18), (0.50, 0.42)  # length 0.24 -> 1.2
    pts[54], pts[284] = (0.415, 0.22), (0.585, 0.22)  # forehead 0.17 -> 0.85
    pts[172], pts[397] = (0.42, 0.38), (0.58, 0.38)  # jaw 0.16 -> 0.8
    pts[1] = (nose_x, 0.30)
    return pts


def test_face_structure_ratios_and_overlay():
    face = face_structure(_mesh(), 1000, 1000)
    assert face is not None
    assert (face.length_to_cheek, face.forehead_to_cheek, face.jaw_to_cheek) == (1.2, 0.85, 0.8)
    assert face.face_shape == "Oval"
    assert len(face.points) == 468
    assert face.contours["cheekbone_width"] == [[0.4, 0.3], [0.6, 0.3]]
    assert face.contours["face_oval"][0] == face.contours["face_oval"][-1]  # closed outline


def test_turned_head_gives_no_face_shape():
    face = face_structure(_mesh(nose_x=0.42), 1000, 1000)
    assert face is not None and face.face_shape is None
    assert "straight on" in face.note


def test_no_face_mesh():
    assert face_structure([], 100, 100) is None


# ── Shoulders & agreement ───────────────────────────────────────────────────


def _pose(left_y: float = 0.25, right_y: float = 0.25, vis: float = 0.9) -> list[LandmarkPoint]:
    pts = [LandmarkPoint(0.5, 0.5, 0.0, 0.9) for _ in range(33)]
    pts[0] = LandmarkPoint(0.5, 0.10, 0, 0.9)
    pts[11] = LandmarkPoint(0.60, left_y, 0, vis)  # person's left = image right
    pts[12] = LandmarkPoint(0.40, right_y, 0, vis)
    pts[23], pts[24] = LandmarkPoint(0.56, 0.55, 0, 0.9), LandmarkPoint(0.44, 0.55, 0, 0.9)
    return pts


def _hrnet_from(lms: list[LandmarkPoint], dx: float = 0.0) -> list[Keypoint | None]:
    kps: list[Keypoint | None] = [None] * 17
    for mp_i, hr_i in {0: 0, 11: 5, 12: 6, 23: 11, 24: 12}.items():
        kps[hr_i] = Keypoint(lms[mp_i].x + dx, lms[mp_i].y, 0.8)
    return kps


@pytest.mark.parametrize(
    ("left_y", "right_y", "level"),
    [(0.25, 0.25, "Level"), (0.20, 0.25, "Left shoulder higher"), (0.25, 0.20, "Right shoulder higher")],
)
def test_shoulder_level(left_y, right_y, level):
    lms = _pose(left_y, right_y)
    result = shoulder_analysis(lms, _hrnet_from(lms), 1000, 1000, "rectangle")
    assert result is not None
    assert result.level == level
    assert result.sources == ["MediaPipe", "HRNet"]
    assert result.build == "Balanced with hips"


def test_shoulders_fall_back_to_hrnet_when_mediapipe_is_unsure():
    lms = _pose(vis=0.2)
    result = shoulder_analysis(lms, _hrnet_from(_pose()), 1000, 1000)
    assert result is not None and result.sources == ["HRNet"]
    assert shoulder_analysis(lms, [], 1000, 1000) is None


def test_model_agreement():
    lms = _pose()
    same = model_agreement(lms, _hrnet_from(lms), 1000, 1000)
    assert same is not None and same.mean_offset_pct == 0.0 and same.agreement == "Strong"
    shifted = model_agreement(lms, _hrnet_from(lms, dx=0.1), 1000, 1000)  # half a shoulder width
    assert shifted is not None and shifted.mean_offset_pct == 50.0 and shifted.agreement == "Weak"
    assert model_agreement(lms, [], 1000, 1000) is None


# ── HRNet top-down crop + decoding ──────────────────────────────────────────


def test_person_box_from_landmarks_or_whole_photo():
    assert person_box(500, 1000, None) == (0.0, 0.0, 500.0, 1000.0)
    box = person_box(1000, 1000, _pose())
    assert box[0] == pytest.approx(400) and box[2] == pytest.approx(600)  # shoulder-to-shoulder span
    assert box[1] < 100  # room added above the nose for the top of the head


def test_box_gets_the_network_aspect_and_padding():
    center, size = box_to_center_scale((100, 0, 200, 400))  # tall and thin
    assert tuple(center) == (150, 200)
    assert size[1] == pytest.approx(400 * 1.25)
    assert size[0] / size[1] == pytest.approx(INPUT_W / INPUT_H)


def test_heatmap_peak_maps_back_to_the_original_image():
    img_w, img_h = 500, 1000
    center, size = box_to_center_scale((100, 100, 400, 900))
    # a joint at (250, 300) in the photo -> its place in the crop -> heatmap cell
    matrix = crop_transform(center, size, HEATMAP_W, HEATMAP_H)
    gx, gy = matrix @ np.array([250, 300, 1.0])
    heat = np.zeros((17, HEATMAP_H, HEATMAP_W), np.float32)
    heat[0, round(gy), round(gx)] = 1.0
    heat[0] = cv2.GaussianBlur(heat[0], (0, 0), 1)
    heat[0] /= heat[0].max()
    points = decode_heatmaps(heat, center, size, img_w, img_h)
    cell = float(size[0]) / HEATMAP_W  # one heatmap cell in photo pixels
    assert points[0] is not None
    assert points[0].x * img_w == pytest.approx(250, abs=cell)
    assert points[0].y * img_h == pytest.approx(300, abs=cell)
    assert all(p is None for p in points[1:])  # empty maps: below threshold


# ── /analyze/app wiring ─────────────────────────────────────────────────────

FACE = FaceBox(x=160, y=40, w=80, h=80, score=0.95)


class FakePose:
    def __init__(self, people):
        self.people = people

    def detect_people(self, _img):
        return self.people

    def detect(self, _img):
        return (self.people[0], 0.9) if self.people else ([], 0.0)

    def close(self):
        pass


class Fixed:
    """Stand-in for the face detector / face mesh / HRNet: returns a fixed value."""

    def __init__(self, value):
        self.value = value

    def detect(self, _img, *_args):
        return self.value

    def close(self):
        pass


def _photo_b64() -> str:
    # square, so the normalised fake mesh keeps its proportions in pixels
    img = np.full((800, 800, 3), 200, dtype=np.uint8)
    img[40:120, 160:240] = (120, 160, 210)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return base64.b64encode(buf.tobytes()).decode()


@pytest.fixture
def client(monkeypatch):
    with TestClient(main.app) as c:
        lms = _pose(0.20, 0.25)
        monkeypatch.setattr(main, "_pose", FakePose([lms]))
        monkeypatch.setattr(main, "_faces", Fixed([FACE]))
        monkeypatch.setattr(main, "_face_mesh", Fixed(_mesh()))
        monkeypatch.setattr(main, "_hrnet", Fixed(_hrnet_from(lms)))
        yield c


def test_plain_scan_has_no_extras(client):
    body = client.post("/analyze/app", json={"image_base64": _photo_b64()}).json()
    assert body["body_shape"]
    assert body["face"] is None and body["shoulders"] is None and body["hrnet_keypoints"] == []
    assert body["models_used"] == []


def test_detailed_scan_runs_face_mesh_and_hrnet(client):
    body = client.post("/analyze/app", json={"image_base64": _photo_b64(), "detailed": True}).json()
    assert body["models_used"] == ["MediaPipe Pose", "MediaPipe Face Detector", "MediaPipe Face Mesh", "HRNet-W32 (COCO-17)"]
    assert body["face"]["face_shape"] == "Oval"
    assert body["shoulders"]["level"] == "Left shoulder higher"
    assert body["model_agreement"]["agreement"] == "Strong"
    assert {k["name"] for k in body["hrnet_keypoints"]} == {"nose", "right_shoulder", "left_shoulder", "right_hip", "left_hip"}
    assert body["processing_time_ms"] is not None


def test_detailed_scan_still_measures_shoulders_without_hips(client, monkeypatch):
    lms = _pose()
    lms[23] = LandmarkPoint(0.56, 0.55, 0, 0.1)
    lms[24] = LandmarkPoint(0.44, 0.55, 0, 0.1)  # hips out of frame (a selfie)
    monkeypatch.setattr(main, "_pose", FakePose([lms]))
    monkeypatch.setattr(main, "_hrnet", Fixed(_hrnet_from(lms)))
    body = client.post("/analyze/app", json={"image_base64": _photo_b64(), "detailed": True}).json()
    assert body["error"] and body["body_shape"] is None
    assert body["shoulders"]["level"] == "Level"
    assert body["face"] is not None


def test_detailed_scan_skips_extras_for_several_people(client, monkeypatch):
    monkeypatch.setattr(main, "_pose", FakePose([_pose(), _pose()]))
    body = client.post("/analyze/app", json={"image_base64": _photo_b64(), "detailed": True}).json()
    assert "More than one person" in body["error"]
    assert body["face"] is None and body["shoulders"] is None


def test_detailed_scan_without_optional_models(client, monkeypatch):
    monkeypatch.setattr(main, "_face_mesh", None)
    monkeypatch.setattr(main, "_hrnet", None)
    body = client.post("/analyze/app", json={"image_base64": _photo_b64(), "detailed": True}).json()
    assert body["models_used"] == ["MediaPipe Pose", "MediaPipe Face Detector"]
    assert body["face"] is None
    assert body["shoulders"]["sources"] == ["MediaPipe"]
    assert body["model_agreement"] is None
