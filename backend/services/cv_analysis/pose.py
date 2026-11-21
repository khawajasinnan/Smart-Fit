"""MediaPipe pose estimation + safe image loading for the CV service.

* The 29 MB pose model is loaded ONCE at service start-up (PoseEstimator);
  previously it was re-created on every request.
* MediaPipe's landmarker is not thread-safe, so detection is serialised with
  a lock; callers run it in a worker thread so the event loop never blocks.
* Images are validated before decoding: https only, allow-listed hosts (our
  Supabase storage), no redirects, byte cap, then downscaled (SRDS §4.2
  "Secure File Upload"; prevents SSRF via arbitrary URLs).
"""

from __future__ import annotations

import base64
import binascii
import logging
import threading
from pathlib import Path
from urllib.parse import urlparse

import cv2
import httpx
import mediapipe as mp
import numpy as np

from shared.config import settings
from services.cv_analysis.body_classifier import LandmarkPoint

logger = logging.getLogger("smartfit.cv.pose")

_BaseOptions = mp.tasks.BaseOptions
_PoseLandmarker = mp.tasks.vision.PoseLandmarker
_PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
_VisionRunningMode = mp.tasks.vision.RunningMode

POSE_MODEL_PATH = Path(__file__).resolve().parent / "models" / "pose_landmarker_heavy.task"

# MediaPipe Pose has 33 landmarks, in this order.
LANDMARK_NAMES: list[str] = [
    "nose",
    "left_eye_inner",
    "left_eye",
    "left_eye_outer",
    "right_eye_inner",
    "right_eye",
    "right_eye_outer",
    "left_ear",
    "right_ear",
    "mouth_left",
    "mouth_right",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_pinky",
    "right_pinky",
    "left_index",
    "right_index",
    "left_thumb",
    "right_thumb",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
    "left_heel",
    "right_heel",
    "left_foot_index",
    "right_foot_index",
]


class ImageLoadError(ValueError):
    """User-facing reason why a photo could not be used."""


# ──────────────────────────────────────────────────────────────────────────────
# POSE ESTIMATOR (loaded once)
# ──────────────────────────────────────────────────────────────────────────────


class PoseEstimator:
    def __init__(self, model_path: Path = POSE_MODEL_PATH) -> None:
        if not model_path.exists():
            raise FileNotFoundError(
                f"Pose model not found at {model_path}. Download pose_landmarker_heavy.task from "
                "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/"
                "float16/latest/pose_landmarker_heavy.task"
            )
        options = _PoseLandmarkerOptions(
            base_options=_BaseOptions(model_asset_path=str(model_path)),
            running_mode=_VisionRunningMode.IMAGE,
            num_poses=2,  # a 2nd person means the photo is rejected (multiple people)
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
            output_segmentation_masks=False,
        )
        self._landmarker = _PoseLandmarker.create_from_options(options)
        self._lock = threading.Lock()
        logger.info("Pose model loaded from %s", model_path.name)

    def detect_people(self, img_bgr: np.ndarray) -> list[list[LandmarkPoint]]:
        """Landmarks for each person found (at most 2)."""
        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=img_rgb)
        with self._lock:
            result = self._landmarker.detect(mp_image)

        people: list[list[LandmarkPoint]] = []
        for pose_landmarks in result.pose_landmarks or []:
            points = []
            for lm in pose_landmarks:
                vis = getattr(lm, "visibility", None)
                if vis is None:
                    vis = getattr(lm, "presence", 0.5)
                points.append(LandmarkPoint(x=lm.x, y=lm.y, z=lm.z, visibility=float(vis)))
            people.append(points)
        return people

    def detect(self, img_bgr: np.ndarray) -> tuple[list[LandmarkPoint], float]:
        """First person's 33 landmarks and their average visibility, or ([], 0.0)."""
        people = self.detect_people(img_bgr)
        if not people:
            return [], 0.0
        points = people[0]
        return points, sum(p.visibility for p in points) / len(points)

    def close(self) -> None:
        self._landmarker.close()


# ──────────────────────────────────────────────────────────────────────────────
# SAFE IMAGE LOADING
# ──────────────────────────────────────────────────────────────────────────────


def allowed_image_hosts() -> set[str]:
    hosts = {h.strip().lower() for h in settings.cv_allowed_image_hosts.split(",") if h.strip()}
    if settings.supabase_url:
        supabase_host = urlparse(settings.supabase_url).hostname
        if supabase_host:
            hosts.add(supabase_host.lower())
    return hosts


def decode_image(raw: bytes) -> np.ndarray:
    """Decode bytes to a BGR image and downscale so the long side <= CV_MAX_IMAGE_SIDE."""
    img = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ImageLoadError("That file doesn't look like a photo. Please use a JPG or PNG image.")
    h, w = img.shape[:2]
    longest = max(h, w)
    if longest > settings.cv_max_image_side:
        scale = settings.cv_max_image_side / longest
        img = cv2.resize(img, (max(1, int(w * scale)), max(1, int(h * scale))), interpolation=cv2.INTER_AREA)
    return img


def load_image_from_base64(b64_string: str) -> np.ndarray:
    if "," in b64_string:  # strip "data:image/jpeg;base64," prefix
        b64_string = b64_string.split(",", 1)[1]
    if len(b64_string) * 3 // 4 > settings.cv_max_image_bytes:
        raise ImageLoadError("That photo is too large. Please use one under 8 MB.")
    try:
        raw = base64.b64decode(b64_string)
    except (binascii.Error, ValueError) as exc:
        raise ImageLoadError("The photo couldn't be read. Please try again.") from exc
    return decode_image(raw)


async def load_image_from_url(client: httpx.AsyncClient, url: str) -> np.ndarray:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ImageLoadError("Only secure (https) photo links are supported.")
    if parsed.hostname.lower() not in allowed_image_hosts():
        raise ImageLoadError("That photo link isn't from SmartFit storage. Please upload the photo instead.")

    buf = bytearray()
    try:
        async with client.stream("GET", url, follow_redirects=False, timeout=15.0) as resp:
            if resp.status_code != 200:
                raise ImageLoadError("The photo couldn't be downloaded. Please try again.")
            if not resp.headers.get("content-type", "").lower().startswith("image/"):
                raise ImageLoadError("That link doesn't point to a photo.")
            async for chunk in resp.aiter_bytes():
                buf.extend(chunk)
                if len(buf) > settings.cv_max_image_bytes:
                    raise ImageLoadError("That photo is too large. Please use one under 8 MB.")
    except httpx.HTTPError as exc:
        raise ImageLoadError("The photo couldn't be downloaded. Please try again.") from exc
    return decode_image(bytes(buf))
