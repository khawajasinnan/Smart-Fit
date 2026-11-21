"""HRNet-W32 body keypoints (COCO 17, top-down 256x192) via OpenCV's DNN module.

HRNet (Sun et al., "Deep High-Resolution Representation Learning for Human
Pose Estimation", CVPR 2019) keeps a high-resolution branch through the whole
network instead of recovering it from a low-resolution one, which makes its
joint positions precise. Weights: OpenMMLab mmpose hrnet_w32_coco_256x192
(Apache-2.0, COCO), exported to ONNX by scripts/download_cv_models.py, so
there is no PyTorch at runtime.

Top-down: HRNet needs a box around one person. The box comes from MediaPipe's
landmarks when we have them (the service already runs MediaPipe and rejects
photos with several people), otherwise the whole photo is used.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger("smartfit.cv.hrnet")

HRNET_MODEL_PATH = Path(__file__).resolve().parent / "models" / "hrnet_w32_coco_256x192.onnx"
INPUT_W, INPUT_H = 192, 256  # fixed at export time
HEATMAP_W, HEATMAP_H = 48, 64  # input / 4
BOX_PADDING = 1.25  # mmpose's top-down default: a little room around the person
MIN_CONFIDENCE = 0.3  # below this a joint is reported as not found
MEAN_RGB = np.array([123.675, 116.28, 103.53], dtype=np.float32)  # ImageNet, as trained
STD_RGB = np.array([58.395, 57.12, 57.375], dtype=np.float32)

# COCO-17 order produced by the model.
KEYPOINT_NAMES: list[str] = [
    "nose", "left_eye", "right_eye", "left_ear", "right_ear",
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_wrist", "right_wrist", "left_hip", "right_hip",
    "left_knee", "right_knee", "left_ankle", "right_ankle",
]
INDEX = {name: i for i, name in enumerate(KEYPOINT_NAMES)}

# Limbs (COCO skeleton) the app draws, as name pairs.
LIMBS: list[tuple[str, str]] = [
    ("left_shoulder", "right_shoulder"), ("left_shoulder", "left_elbow"), ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"), ("right_elbow", "right_wrist"), ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"), ("left_hip", "right_hip"), ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"), ("right_hip", "right_knee"), ("right_knee", "right_ankle"),
    ("nose", "left_eye"), ("nose", "right_eye"), ("left_eye", "left_ear"), ("right_eye", "right_ear"),
]


@dataclass(frozen=True)
class Keypoint:
    """x, y normalised to [0, 1] of the original image; confidence = heatmap peak (~0-1)."""

    x: float
    y: float
    confidence: float


def person_box(
    img_w: int, img_h: int, landmarks: Sequence | None = None, min_visibility: float = 0.3
) -> tuple[float, float, float, float]:
    """(x0, y0, x1, y1) in pixels: around MediaPipe's visible landmarks, else the whole photo."""
    pts = [(p.x * img_w, p.y * img_h) for p in (landmarks or []) if getattr(p, "visibility", 1.0) >= min_visibility]
    if len(pts) < 4:
        return 0.0, 0.0, float(img_w), float(img_h)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    # MediaPipe's top landmark is the eyes/ears: add room for the top of the head.
    y0 -= 0.12 * (y1 - y0)
    return max(0.0, x0), max(0.0, y0), min(float(img_w), x1), min(float(img_h), y1)


def box_to_center_scale(box: tuple[float, float, float, float]) -> tuple[np.ndarray, np.ndarray]:
    """mmpose's box -> (centre, size) with the network's 3:4 aspect and padding."""
    x0, y0, x1, y1 = box
    w, h = max(x1 - x0, 1.0), max(y1 - y0, 1.0)
    aspect = INPUT_W / INPUT_H
    if w > aspect * h:
        h = w / aspect
    else:
        w = h * aspect
    return np.array([(x0 + x1) / 2, (y0 + y1) / 2], np.float32), np.array([w, h], np.float32) * BOX_PADDING


def crop_transform(center: np.ndarray, size: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """2x3 affine matrix: image pixels -> an out_w x out_h crop of the box."""
    sx, sy = out_w / size[0], out_h / size[1]
    return np.array([[sx, 0, out_w / 2 - center[0] * sx], [0, sy, out_h / 2 - center[1] * sy]], np.float32)


def decode_heatmaps(
    heatmaps: np.ndarray, center: np.ndarray, size: np.ndarray, img_w: int, img_h: int
) -> list[Keypoint | None]:
    """heatmaps: (17, 64, 48). Peak + the classic quarter-pixel shift towards the
    higher neighbour, mapped back to the photo. None below MIN_CONFIDENCE."""
    points: list[Keypoint | None] = []
    for hm in heatmaps:
        _, peak, _, (px, py) = cv2.minMaxLoc(hm)
        x, y = float(px), float(py)
        if 1 < px < HEATMAP_W - 1:
            x += 0.25 * np.sign(hm[py, px + 1] - hm[py, px - 1])
        if 1 < py < HEATMAP_H - 1:
            y += 0.25 * np.sign(hm[py + 1, px] - hm[py - 1, px])
        # heatmap -> box -> image (pixel centres)
        ix = center[0] + (x / HEATMAP_W - 0.5) * size[0]
        iy = center[1] + (y / HEATMAP_H - 0.5) * size[1]
        if peak < MIN_CONFIDENCE or not (0 <= ix < img_w and 0 <= iy < img_h):
            points.append(None)
            continue
        points.append(Keypoint(x=ix / img_w, y=iy / img_h, confidence=float(peak)))
    return points


class HRNetEstimator:
    def __init__(self, model_path: Path = HRNET_MODEL_PATH) -> None:
        if not model_path.exists():
            raise FileNotFoundError(f"HRNet model not found at {model_path}. Run: python scripts/download_cv_models.py")
        self._net = cv2.dnn.readNetFromONNX(str(model_path))
        self._lock = threading.Lock()  # a cv2.dnn Net isn't thread-safe
        logger.info("HRNet model loaded from %s", model_path.name)

    def detect(self, img_bgr: np.ndarray, landmarks: Sequence | None = None) -> list[Keypoint | None]:
        """17 COCO keypoints of the person (None where not found)."""
        img_h, img_w = img_bgr.shape[:2]
        center, size = box_to_center_scale(person_box(img_w, img_h, landmarks))
        matrix = crop_transform(center, size, INPUT_W, INPUT_H)
        crop = cv2.warpAffine(img_bgr, matrix, (INPUT_W, INPUT_H), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0))
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB).astype(np.float32)
        blob = ((rgb - MEAN_RGB) / STD_RGB).transpose(2, 0, 1)[np.newaxis]
        with self._lock:
            self._net.setInput(blob)
            heatmaps = self._net.forward("heatmaps")[0]
        return decode_heatmaps(heatmaps, center, size, img_w, img_h)

    def close(self) -> None:
        self._net = None
