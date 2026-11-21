"""2D hairstyle preview (SFR-030): align a catalog hairstyle to the user's face
and blend it in. Plain image processing (OpenCV), no generative model (spec §11).

  1. Align: an affine transform maps the hairstyle's three anchors (eye
     centres + chin, measured on the photo it was cut from) onto the same
     points on the user's face (face_mesh.anchors).
  2. Light: the hair's brightness is scaled by the ratio of the user's skin
     brightness to the source person's, so the hair isn't lit differently
     from the face.
  3. Own hair: the user's hair that the new style doesn't cover (MediaPipe
     hair segmenter) is painted over from its surroundings. Styles that would
     leave too much of it are skipped by the ranking (coverage()).
  4. Blend: alpha-composite with the hairstyle's soft edge.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

ANCHOR_KEYS = ("left_eye", "right_eye", "chin")
LIGHT_RATIO_RANGE = (0.7, 1.35)
HAIR_THRESHOLD = 0.5  # the user's hair mask above this counts as hair
EYE_COVER_MAX = 0.35  # average alpha over an eye above this = the style sits on the face
MAX_UNCOVERED = 0.30  # more of the own hair left showing looks wrong (visual check, 14 Nov 2026)


@dataclass
class HairAsset:
    """One catalog hairstyle: RGBA cut-out + where the source face was."""

    rgba: np.ndarray  # (h, w, 4) uint8
    anchors: dict[str, list[float]]  # in the cut-out's pixels
    skin_luma: float | None


def transform(asset_anchors: dict[str, list[float]], user_anchors: dict[str, list[float]]) -> np.ndarray:
    src = np.float32([asset_anchors[k] for k in ANCHOR_KEYS])
    dst = np.float32([user_anchors[k] for k in ANCHOR_KEYS])
    return cv2.getAffineTransform(src, dst)


def warp(asset: HairAsset, user_anchors: dict[str, list[float]], size: tuple[int, int]) -> np.ndarray:
    """The hairstyle placed on a transparent (h, w, 4) float32 canvas of the user's photo size (w, h)."""
    matrix = transform(asset.anchors, user_anchors)
    return cv2.warpAffine(asset.rgba.astype(np.float32), matrix, size, flags=cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))


def coverage(user_hair: np.ndarray, new_alpha: np.ndarray) -> float:
    """Share of the user's own hair that the new style leaves uncovered (0 = all covered)."""
    own = user_hair >= HAIR_THRESHOLD
    total = int(own.sum())
    if total == 0:
        return 0.0
    uncovered = own & (new_alpha < 0.5)
    return float(uncovered.sum()) / total


def covers_eyes(user_anchors: dict[str, list[float]], new_alpha: np.ndarray) -> bool:
    """True when the warped hair would sit over an eye. Bangs may cover the
    forehead, never the eyes: a cut-out that does is misaligned for this face
    (its source head was a different shape), so the style is left out."""
    h, w = new_alpha.shape[:2]
    left, right = user_anchors["left_eye"], user_anchors["right_eye"]
    span = max(abs(left[0] - right[0]), 1.0)
    radius = max(1, int(span * 0.12))
    for x, y in (left, right):
        x0, y0 = int(max(0, x - radius)), int(max(0, y - radius))
        patch = new_alpha[y0:min(h, int(y) + radius), x0:min(w, int(x) + radius)]
        if patch.size and float(patch.mean()) > EYE_COVER_MAX:
            return True
    return False


def match_light(rgb: np.ndarray, source_skin: float | None, user_skin: float | None) -> np.ndarray:
    if not source_skin or not user_skin:
        return rgb
    ratio = float(np.clip(user_skin / source_skin, *LIGHT_RATIO_RANGE))
    return np.clip(rgb * ratio, 0, 255)


def paint_over_own_hair(img_bgr: np.ndarray, user_hair: np.ndarray, new_alpha: np.ndarray) -> np.ndarray:
    """Fill the user's hair that stays visible from the surrounding background/skin."""
    leftover = ((user_hair >= HAIR_THRESHOLD) & (new_alpha < 0.9)).astype(np.uint8) * 255
    if not leftover.any():
        return img_bgr
    leftover = cv2.dilate(leftover, np.ones((5, 5), np.uint8), iterations=2)
    radius = max(5, int(0.01 * max(img_bgr.shape[:2])))
    return cv2.inpaint(img_bgr, leftover, radius, cv2.INPAINT_TELEA)


def render(
    img_bgr: np.ndarray,
    user_anchors: dict[str, list[float]],
    asset: HairAsset,
    user_hair: np.ndarray | None = None,
    user_skin: float | None = None,
) -> np.ndarray:
    """The user's photo wearing the hairstyle (BGR uint8, same size)."""
    h, w = img_bgr.shape[:2]
    placed = warp(asset, user_anchors, (w, h))
    alpha = placed[..., 3:4] / 255.0
    hair_bgr = match_light(placed[..., :3], asset.skin_luma, user_skin)
    base = img_bgr if user_hair is None else paint_over_own_hair(img_bgr, user_hair, alpha[..., 0])
    out = alpha * hair_bgr + (1.0 - alpha) * base.astype(np.float32)
    return np.clip(out, 0, 255).astype(np.uint8)


def head_crop(img_shape: tuple[int, ...], user_anchors: dict[str, list[float]], hair_alpha: np.ndarray | None) -> tuple[int, int, int, int]:
    """(x0, y0, x1, y1): the head and hair, portrait 3:4, for the preview image."""
    h, w = img_shape[:2]
    (lx, ly), (rx, ry), (cx, cy) = (user_anchors[k] for k in ANCHOR_KEYS)
    eye_dist = max(abs(rx - lx), 1.0)
    mid_x = (lx + rx) / 2
    x0, x1 = mid_x - 2.6 * eye_dist, mid_x + 2.6 * eye_dist
    y0, y1 = min(ly, ry) - 2.6 * eye_dist, cy + 1.6 * eye_dist
    if hair_alpha is not None:
        ys, xs = np.nonzero(hair_alpha > 0.3)
        if len(xs):
            x0, x1 = min(x0, xs.min()), max(x1, xs.max())
            y0, y1 = min(y0, ys.min()), max(y1, ys.max())
    # portrait 3:4 around that box
    bw, bh = x1 - x0, y1 - y0
    if bw / bh > 0.75:
        grow = bw / 0.75 - bh
        y0, y1 = y0 - grow / 2, y1 + grow / 2
    else:
        grow = bh * 0.75 - bw
        x0, x1 = x0 - grow / 2, x1 + grow / 2
    return int(max(0, x0)), int(max(0, y0)), int(min(w, x1)), int(min(h, y1))
