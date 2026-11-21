"""The user's own hair: length and texture (spec §23.27), for suggestions the
user can actually wear.

* Length: the catalog's own rule (scripts/build_hairstyle_catalog.py), so
  "short / medium / long" means the same for the user and for every style:
  how far the hair reaches below the chin, in face lengths.
* Texture (straight / wavy): a Random Forest on strand-direction features —
  structure-tensor coherence and local orientation spread at three smoothing
  scales and two zooms, plus edge/detail statistics — inside the hair mask,
  with the photo scaled so the eyes are a fixed distance apart. Trained on
  CelebAMask-HQ's human Wavy_Hair / Straight_Hair labels
  (scripts/train_hair_texture.py). It is right about 7 times in 10 overall,
  so it only *suggests* a texture when it is confident (CONFIDENT); the app
  shows it as a choice the user can change, and asks when it isn't sure.
  (A single coherence threshold was tried first: 55.5% held-out, not used.)
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger("smartfit.hairstyle.profile")

HAIR_THRESHOLD = 0.5
EDGE_ROWS = 4
MIN_HAIR_PIXELS = 300  # at the normalised scale; less = not enough hair to judge texture
ZOOMS = (64.0, 128.0)  # eye distance in pixels after scaling
SIGMAS = (1.5, 3.0, 6.0)
CONFIDENT = 0.70  # P(wavy) >= this -> wavy, <= 1 - this -> straight, else unknown
TEXTURE_MODEL = Path(__file__).resolve().parent / "models" / "hair_texture.joblib"


@dataclass
class HairProfile:
    length: str | None  # "short" | "medium" | "long"; None = no hair found
    wavy: bool | None  # None = not sure (the app asks)
    wavy_probability: float | None

    def describe(self) -> str:
        if self.length is None:
            return "We couldn't see much hair in the photo."
        texture = "" if self.wavy is None else (" wavy" if self.wavy else " straight")
        return f"Your hair looks {self.length}{texture}."


def hair_length(mask: np.ndarray, anchors: dict[str, list[float]]) -> str | None:
    """The catalog's rule: below the chin by > 1 face length (or off the photo) = long, > 0.15 = medium."""
    if int(mask.sum()) < 50:
        return None
    face_len = math.dist(anchors["forehead"], anchors["chin"]) or 1.0
    ys = np.nonzero(mask)[0]
    off_bottom = bool(mask[-EDGE_ROWS:].mean() > 0.02)
    below_chin = (ys.max() - anchors["chin"][1]) / face_len
    return "long" if off_bottom or below_chin > 1.0 else "medium" if below_chin > 0.15 else "short"


def texture_features(gray: np.ndarray, mask: np.ndarray, eye_distance: float) -> list[float] | None:
    """Strand-direction and detail statistics inside the hair, or None with too little hair."""
    out: list[float] = []
    for zoom in ZOOMS:
        scale = zoom / max(eye_distance, 1.0)
        g = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA).astype(np.float32)
        m = cv2.resize(mask.astype(np.uint8), (g.shape[1], g.shape[0]), interpolation=cv2.INTER_NEAREST)
        m = cv2.erode(m, np.ones((5, 5), np.uint8)).astype(bool)  # away from the hair's outline
        if int(m.sum()) < MIN_HAIR_PIXELS:
            return None
        gx = cv2.Sobel(g, cv2.CV_32F, 1, 0)
        gy = cv2.Sobel(g, cv2.CV_32F, 0, 1)
        for sigma in SIGMAS:
            jxx = cv2.GaussianBlur(gx * gx, (0, 0), sigma)
            jyy = cv2.GaussianBlur(gy * gy, (0, 0), sigma)
            jxy = cv2.GaussianBlur(gx * gy, (0, 0), sigma)
            coh = np.sqrt((jxx - jyy) ** 2 + 4 * jxy ** 2) / (jxx + jyy + 1e-6)
            angle = 0.5 * np.arctan2(2 * jxy, jxx - jyy)
            # how consistent the strand direction is in a 9x9 neighbourhood
            spread = np.sqrt(cv2.blur(np.cos(2 * angle), (9, 9)) ** 2 + cv2.blur(np.sin(2 * angle), (9, 9)) ** 2)
            v, r = coh[m], spread[m]
            out += [float(np.median(v)), float(np.percentile(v, 25)), float(np.percentile(v, 75)),
                    float(np.median(r)), float(np.percentile(r, 25))]
        mag = np.sqrt(gx * gx + gy * gy)[m]
        lap = np.abs(cv2.Laplacian(g, cv2.CV_32F))[m]
        intensity = g[m]
        out += [float(np.median(mag) / (np.median(intensity) + 1)),
                float(np.percentile(mag, 90) / (np.median(mag) + 1e-3)),
                float(np.median(lap) / (np.median(mag) + 1e-3)),
                float(intensity.std() / (intensity.mean() + 1))]
    return out


_texture_model: list = []


def _model():
    if not _texture_model:
        model = None
        if TEXTURE_MODEL.exists():
            try:
                import joblib

                model = joblib.load(TEXTURE_MODEL)
            except Exception:  # noqa: BLE001 — without it the app just asks the user
                logger.exception("hair texture model couldn't be loaded")
        _texture_model.append(model)
    return _texture_model[0]


def wavy_probability(gray: np.ndarray, mask: np.ndarray, eye_distance: float) -> float | None:
    model = _model()
    if model is None:
        return None
    feats = texture_features(gray, mask, eye_distance)
    if feats is None:
        return None
    return float(model.predict_proba(np.asarray([feats]))[0, 1])


def profile(img_bgr: np.ndarray, hair_prob: np.ndarray, anchors: dict[str, list[float]]) -> HairProfile:
    mask = hair_prob >= HAIR_THRESHOLD
    length = hair_length(mask, anchors)
    if length is None:
        return HairProfile(None, None, None)
    eye_distance = math.dist(anchors["left_eye"], anchors["right_eye"])
    p = wavy_probability(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY), mask, eye_distance)
    if p is None:
        return HairProfile(length, None, None)
    wavy = True if p >= CONFIDENT else False if p <= 1 - CONFIDENT else None
    return HairProfile(length, wavy, round(p, 3))
