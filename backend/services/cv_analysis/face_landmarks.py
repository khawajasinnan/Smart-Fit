"""MediaPipe Face Landmarker (478-point face mesh), loaded once.

Gives the facial-structure overlay the app draws (face outline, brows, eyes,
nose, lips) and the ratios behind the face-shape estimate (structure.py).
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

logger = logging.getLogger("smartfit.cv.face_landmarks")

FACE_LANDMARKER_PATH = Path(__file__).resolve().parent / "models" / "face_landmarker.task"


class FaceLandmarker:
    def __init__(self, model_path: Path = FACE_LANDMARKER_PATH) -> None:
        if not model_path.exists():
            raise FileNotFoundError(
                f"Face landmarker not found at {model_path}. Run: python scripts/download_cv_models.py --skip-hrnet"
            )
        options = mp.tasks.vision.FaceLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
            running_mode=mp.tasks.vision.RunningMode.IMAGE,
            num_faces=1,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
        )
        self._landmarker = mp.tasks.vision.FaceLandmarker.create_from_options(options)
        self._lock = threading.Lock()  # MediaPipe tasks aren't thread-safe
        logger.info("Face landmarker loaded from %s", model_path.name)

    def detect(self, img_bgr: np.ndarray) -> list[tuple[float, float]]:
        """478 (x, y) points normalised to [0, 1] for the main face, or [] if none."""
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
        with self._lock:
            result = self._landmarker.detect(mp_image)
        if not result.face_landmarks:
            return []
        return [(lm.x, lm.y) for lm in result.face_landmarks[0]]

    def close(self) -> None:
        self._landmarker.close()
