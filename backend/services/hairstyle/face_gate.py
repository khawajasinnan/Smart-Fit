"""Live face check for the hairstyle camera (SFR-029): is the face inside the
guide circle, straight, sharp and well lit?

The app shows a circle on the camera preview and sends a frame about twice a
second; the photo is taken automatically once a frame passes. Two detectors:

  * MediaPipe Face Detector (BlazeFace): fast; finds the face and counts faces.
  * dlib: its HOG frontal-face detector must find the same face (it only
    fires on faces that look straight at the camera), and its 5-point
    landmark model gives the eye line (head tilt) and the nose position
    (head turned left/right).

Then blur is measured around the eyes (variance of the Laplacian on the eye
strip, scaled to 256 px: eyes and lashes have strong edges in any sharp photo,
whatever the skin looks like; the whole face isn't used because smooth skin
reads as "blurry") and the light on the face (too dark, too bright, or a
bright light behind the person).

Calibration (14 Nov 2026, VITON-HD faces scaled to selfie size): eye-strip
sharpness of sharp photos 25-78 (two soft studio shots 8-9), Gaussian blur
sigma 1: 3-17, 15 px motion blur: 4-13 -> threshold 15. Head tilt: dlib and
the MediaPipe face mesh agree within ~2 degrees.

All positions are normalised: the circle centre (cx, cy) as fractions of the
frame width/height and its radius r as a fraction of the frame width, exactly
as the app draws it over the (uncropped) preview.
"""

from __future__ import annotations

import logging
import math
import threading
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger("smartfit.hairstyle.face_gate")

MODELS_DIR = Path(__file__).resolve().parent / "models"
DLIB_5_POINT_PATH = MODELS_DIR / "shape_predictor_5_face_landmarks.dat"

# ── thresholds (calibration in tests/test_face_gate.py and the module notes) ──
MAX_CENTRE_OFFSET = 0.25  # face centre to circle centre, as a fraction of the radius
FACE_FILL = (0.42, 0.80)  # face-box width / circle diameter: smaller = too far, larger = too close
MIN_FACE_PX = 110  # without a circle (an uploaded photo): smallest usable face width
MAX_TILT_DEG = 12.0  # eye line vs horizontal
MAX_TURN = 0.22  # nose offset from the eye midpoint / eye distance
MIN_SHARPNESS = 15.0  # variance of the Laplacian on the eye strip, 256 px wide
BRIGHTNESS = (70.0, 215.0)  # mean luma of the face
BACKLIGHT_RATIO = 0.62  # face luma / background luma below this (with a bright background) = backlit
SECOND_FACE_SCORE = 0.6  # a second face this confident = someone else in the picture

MESSAGES = {
    "NO_FACE": "Put your face inside the circle.",
    "MULTIPLE_FACES": "Only one person, please.",
    "OFF_CENTER": "Move so your face is in the middle of the circle.",
    "TOO_FAR": "Come a little closer.",
    "TOO_CLOSE": "Move back a little.",
    "FACE_TOO_SMALL": "Your face is too small in this photo. Use a closer photo of your face.",
    "HEAD_TILTED": "Keep your head straight.",
    "FACE_TURNED": "Look straight at the camera.",
    "TOO_DARK": "It's too dark. Face a window or a lamp.",
    "TOO_BRIGHT": "Too much light on your face. Move out of direct sunlight.",
    "BACKLIT": "There's bright light behind you. Turn so the light is in front of you.",
    "BLURRY": "Hold still, the picture is blurry.",
}


@dataclass(frozen=True)
class Circle:
    cx: float
    cy: float
    r: float


@dataclass(frozen=True)
class GateResult:
    ready: bool
    code: str | None
    message: str
    face_box: tuple[float, float, float, float] | None = None  # x, y, w, h normalised
    sharpness: float | None = None
    brightness: float | None = None


def _fail(code: str, box=None, **extra) -> GateResult:
    return GateResult(False, code, MESSAGES[code], box, **extra)


def placement(face: tuple[float, float, float, float], img_w: int, img_h: int, circle: Circle | None) -> str | None:
    """Face box (pixels x, y, w, h) vs the guide circle -> a problem code or None."""
    x, y, w, h = face
    if circle is None:
        return "FACE_TOO_SMALL" if w < MIN_FACE_PX else None
    r_px = circle.r * img_w
    dx, dy = x + w / 2 - circle.cx * img_w, y + h / 2 - circle.cy * img_h
    if math.hypot(dx, dy) > MAX_CENTRE_OFFSET * r_px:
        return "OFF_CENTER"
    fill = w / (2 * r_px)
    if fill < FACE_FILL[0]:
        return "TOO_FAR"
    if fill > FACE_FILL[1]:
        return "TOO_CLOSE"
    return None


def head_pose(points: list[tuple[float, float]]) -> str | None:
    """dlib 5-point landmarks (two corners of each eye, then the bottom of the
    nose) -> HEAD_TILTED / FACE_TURNED / None."""
    if len(points) != 5:
        return "FACE_TURNED"
    eye_a = ((points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2)
    eye_b = ((points[2][0] + points[3][0]) / 2, (points[2][1] + points[3][1]) / 2)
    left, right = sorted((eye_a, eye_b))
    eye_dist = math.hypot(right[0] - left[0], right[1] - left[1])
    if eye_dist <= 0:
        return "FACE_TURNED"
    tilt = math.degrees(math.atan2(right[1] - left[1], right[0] - left[0]))
    if abs(tilt) > MAX_TILT_DEG:
        return "HEAD_TILTED"
    # the nose's sideways offset from the eye midpoint, measured along the eye line
    mid = ((left[0] + right[0]) / 2, (left[1] + right[1]) / 2)
    ux, uy = (right[0] - left[0]) / eye_dist, (right[1] - left[1]) / eye_dist
    offset = ((points[4][0] - mid[0]) * ux + (points[4][1] - mid[1]) * uy) / eye_dist
    return "FACE_TURNED" if abs(offset) > MAX_TURN else None


def eye_strip(points: list[tuple[float, float]]) -> tuple[int, int, int, int]:
    """(x0, y0, x1, y1) around both eyes from the dlib 5 points."""
    e1 = ((points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2)
    e2 = ((points[2][0] + points[3][0]) / 2, (points[2][1] + points[3][1]) / 2)
    d = math.hypot(e1[0] - e2[0], e1[1] - e2[1])
    cx, cy = (e1[0] + e2[0]) / 2, (e1[1] + e2[1]) / 2
    return int(cx - 0.9 * d), int(cy - 0.35 * d), int(cx + 0.9 * d), int(cy + 0.35 * d)


def sharpness_of(luma: np.ndarray, box: tuple[int, int, int, int]) -> float:
    x0, y0, x1, y1 = box
    h, w = luma.shape[:2]
    crop = luma[max(0, y0):min(h, y1), max(0, x0):min(w, x1)]
    if crop.size == 0 or crop.shape[1] < 2:
        return 0.0
    scale = 256 / crop.shape[1]
    crop = cv2.resize(crop, (256, max(1, round(crop.shape[0] * scale))),
                      interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC)
    return float(cv2.Laplacian(crop, cv2.CV_64F).var())


def light_and_focus(
    img_bgr: np.ndarray, face: tuple[int, int, int, int], eyes: tuple[int, int, int, int]
) -> tuple[str | None, float, float]:
    """(problem code or None, eye sharpness, face brightness)."""
    x, y, w, h = face
    img_h, img_w = img_bgr.shape[:2]
    luma = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    crop = luma[max(0, y):min(img_h, y + h), max(0, x):min(img_w, x + w)]
    if crop.size == 0:
        return "NO_FACE", 0.0, 0.0
    brightness = float(crop.mean())
    background = float(luma.mean())
    sharpness = sharpness_of(luma, eyes)
    if brightness < BRIGHTNESS[0]:
        return "TOO_DARK", sharpness, brightness
    if brightness > BRIGHTNESS[1]:
        return "TOO_BRIGHT", sharpness, brightness
    if background > 150 and brightness < BACKLIGHT_RATIO * background:
        return "BACKLIT", sharpness, brightness
    if sharpness < MIN_SHARPNESS:
        return "BLURRY", sharpness, brightness
    return None, sharpness, brightness


class FaceGate:
    """MediaPipe + dlib, loaded once; detect() is thread-safe."""

    def __init__(self, face_detector, dlib_model: Path = DLIB_5_POINT_PATH) -> None:
        import dlib  # dlib-bin wheel; imported here so the service starts without it in tests

        if not dlib_model.exists():
            raise FileNotFoundError(f"{dlib_model.name} not found. Run: python scripts/download_hairstyle_models.py")
        self._faces = face_detector
        self._hog = dlib.get_frontal_face_detector()
        self._landmarks = dlib.shape_predictor(str(dlib_model))
        self._dlib = dlib
        self._lock = threading.Lock()
        logger.info("Face gate ready (MediaPipe + dlib HOG + %s)", dlib_model.name)

    def _dlib_points(self, img_bgr: np.ndarray, face: tuple[int, int, int, int]) -> list[tuple[float, float]] | None:
        """dlib on a crop around MediaPipe's face, scaled so the face is ~160 px:
        the HOG detector must agree there is a frontal face; then 5 landmarks."""
        x, y, w, h = face
        img_h, img_w = img_bgr.shape[:2]
        pad = 0.6 * max(w, h)
        x0, y0 = int(max(0, x - pad)), int(max(0, y - pad))
        x1, y1 = int(min(img_w, x + w + pad)), int(min(img_h, y + h + pad))
        crop = cv2.cvtColor(img_bgr[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY)
        if crop.size == 0:
            return None
        scale = 160 / max(w, 1)
        crop = cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR)
        with self._lock:
            found = self._hog(crop, 0)
            if not found:
                return None
            best = max(found, key=lambda r: r.width() * r.height())
            shape = self._landmarks(crop, best)
        return [(x0 + shape.part(i).x / scale, y0 + shape.part(i).y / scale) for i in range(shape.num_parts)]

    def check(self, img_bgr: np.ndarray, circle: Circle | None) -> GateResult:
        img_h, img_w = img_bgr.shape[:2]
        faces = self._faces.detect(img_bgr)
        if not faces:
            return _fail("NO_FACE")
        if len(faces) > 1 and faces[1].score >= SECOND_FACE_SCORE:
            return _fail("MULTIPLE_FACES")
        f = faces[0]
        box = (f.x / img_w, f.y / img_h, f.w / img_w, f.h / img_h)
        problem = placement((f.x, f.y, f.w, f.h), img_w, img_h, circle)
        if problem:
            return _fail(problem, box)
        points = self._dlib_points(img_bgr, (f.x, f.y, f.w, f.h))
        problem = head_pose(points) if points is not None else "FACE_TURNED"
        if problem:
            return _fail(problem, box)
        problem, sharpness, brightness = light_and_focus(img_bgr, (f.x, f.y, f.w, f.h), eye_strip(points))
        extra = {"sharpness": round(sharpness, 1), "brightness": round(brightness, 1)}
        if problem:
            return _fail(problem, box, **extra)
        return GateResult(True, None, "Perfect, hold still!", box, **extra)
