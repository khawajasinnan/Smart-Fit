"""MediaPipe face detection (BlazeFace short range), loaded once.

Used to find the face box for skin-tone sampling and to reject photos with
no face or several faces (spec §6.2-6.3).
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

logger = logging.getLogger("smartfit.cv.face")

FACE_MODEL_PATH = Path(__file__).resolve().parent / "models" / "blaze_face_short_range.tflite"
MIN_FACE_CONFIDENCE = 0.5


@dataclass(frozen=True)
class FaceBox:
    """Face bounding box in pixels, clipped to the image."""

    x: int
    y: int
    w: int
    h: int
    score: float


class FaceDetector:
    def __init__(self, model_path: Path = FACE_MODEL_PATH) -> None:
        if not model_path.exists():
            raise FileNotFoundError(
                f"Face model not found at {model_path}. Download blaze_face_short_range.tflite from "
                "https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/"
                "float16/latest/blaze_face_short_range.tflite"
            )
        options = mp.tasks.vision.FaceDetectorOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
            running_mode=mp.tasks.vision.RunningMode.IMAGE,
            min_detection_confidence=MIN_FACE_CONFIDENCE,
        )
        self._detector = mp.tasks.vision.FaceDetector.create_from_options(options)
        self._lock = threading.Lock()  # MediaPipe detectors aren't thread-safe
        logger.info("Face model loaded from %s", model_path.name)

    def detect(self, img_bgr: np.ndarray) -> list[FaceBox]:
        """All faces, most confident first."""
        img_h, img_w = img_bgr.shape[:2]
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
        with self._lock:
            result = self._detector.detect(mp_image)
        faces = []
        for d in result.detections:
            b = d.bounding_box
            x, y = max(0, b.origin_x), max(0, b.origin_y)
            w, h = min(img_w - x, b.width), min(img_h - y, b.height)
            if w > 0 and h > 0:
                faces.append(FaceBox(x, y, w, h, float(d.categories[0].score)))
        return sorted(faces, key=lambda f: f.score, reverse=True)

    def close(self) -> None:
        self._detector.close()
