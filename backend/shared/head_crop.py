"""The head of the person in a full-body photo, from HRNet's COCO keypoints
(nose, eyes, ears, shoulders), as a square box. Used by the try-on's
"menswear on men, womenswear on women" check (and its evaluation) so the
face classifier sees the same crop in both."""

from __future__ import annotations

import math

from PIL import Image

HEAD_POINTS = ("nose", "left_eye", "right_eye", "left_ear", "right_ear")
MIN_CONFIDENCE = 0.3
MIN_SIDE_PX = 40  # smaller than this the face can't be judged


def head_box(keypoints: list[dict], width: int, height: int) -> tuple[int, int, int, int] | None:
    """(left, top, right, bottom) in pixels, or None when the head isn't clearly
    visible (fewer than 3 confident head points, or too small)."""
    pts = {k["name"]: (k["x"] * width, k["y"] * height) for k in keypoints
           if k.get("name") in HEAD_POINTS + ("left_shoulder", "right_shoulder")
           and float(k.get("confidence", 0)) >= MIN_CONFIDENCE}
    head = [pts[n] for n in HEAD_POINTS if n in pts]
    if len(head) < 3:
        return None
    cx = sum(p[0] for p in head) / len(head)
    cy = sum(p[1] for p in head) / len(head)

    def dist(a, b):
        return math.dist(pts[a], pts[b]) if a in pts and b in pts else 0.0

    size = max(2.2 * dist("left_ear", "right_ear"), 3.6 * dist("left_eye", "right_eye"),
               0.55 * dist("left_shoulder", "right_shoulder"))
    if size < MIN_SIDE_PX:
        return None
    cy -= 0.12 * size  # the keypoints sit low on the head (no forehead / hair points)
    half = size / 2
    left, top = max(0, int(cx - half)), max(0, int(cy - half))
    right, bottom = min(width, int(cx + half)), min(height, int(cy + half))
    if right - left < MIN_SIDE_PX or bottom - top < MIN_SIDE_PX:
        return None
    return left, top, right, bottom


def crop_head(img: Image.Image, keypoints: list[dict]) -> Image.Image | None:
    box = head_box(keypoints, img.width, img.height)
    return img.crop(box) if box else None
