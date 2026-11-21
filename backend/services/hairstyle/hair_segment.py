"""MediaPipe Hair Segmenter (Apache-2.0): where the user's own hair is.

Used by the overlay to find the user's hair that the new hairstyle doesn't
cover (it is painted over, or the style is left out when too much would
stay visible) and to match the new hair's brightness to the photo.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

logger = logging.getLogger("smartfit.hairstyle.hair")

HAIR_SEGMENTER_PATH = Path(__file__).resolve().parent / "models" / "hair_segmenter.tflite"


class HairSegmenter:
    def __init__(self, model_path: Path = HAIR_SEGMENTER_PATH) -> None:
        if not model_path.exists():
            raise FileNotFoundError(f"{model_path.name} not found. Run: python scripts/download_hairstyle_models.py")
        options = mp.tasks.vision.ImageSegmenterOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
            running_mode=mp.tasks.vision.RunningMode.IMAGE,
            output_confidence_masks=True,
            output_category_mask=False,
        )
        self._segmenter = mp.tasks.vision.ImageSegmenter.create_from_options(options)
        self._lock = threading.Lock()
        logger.info("Hair segmenter loaded from %s", model_path.name)

    def hair_mask(self, img_bgr: np.ndarray) -> np.ndarray:
        """Float32 (H, W) in [0, 1]: how likely each pixel is hair."""
        # The model expects RGBA input (it was exported for the web/GPU path).
        rgba = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGBA)
        image = mp.Image(image_format=mp.ImageFormat.SRGBA, data=rgba)
        with self._lock:
            result = self._segmenter.segment(image)
        masks = result.confidence_masks
        hair = masks[-1].numpy_view() if masks else np.zeros(img_bgr.shape[:2], np.float32)
        hair = np.asarray(hair, dtype=np.float32).reshape(img_bgr.shape[:2])
        return np.clip(hair, 0.0, 1.0)

    def close(self) -> None:
        self._segmenter.close()
