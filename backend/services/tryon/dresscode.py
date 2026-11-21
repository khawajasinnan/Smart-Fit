"""DressCode -> IDM-VTON training inputs (spec §5.2, §23.13).

DressCode ships person/garment photos, an 18-class human parsing map
(label_maps/*_4.png), 18 OpenPose keypoints (keypoints/*_2.json, in 384x512
coordinates) and DensePose part labels (dense/*_5.png). IDM-VTON needs:

* an inpaint mask (white = repaint): `inpaint_mask()` is a port of
  IDM-VTON's own DressCode code (inference_dc.py `get_agnostic`, commit
  0d5f3ec2; CC BY-NC-SA 4.0, yisol/IDM-VTON), so training masks match the
  model's DressCode masks exactly;
* a DensePose image: the authors' pre-computed image-densepose when you
  have it, else `render_densepose()`: the DensePose part labels drawn the
  way VITON-HD's were (detectron2's fine-segmentation colours: OpenCV's
  PARULA colormap at label x 255/24, black background; checked against
  VITON-HD's images).
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

LABELS = {
    "background": 0, "hat": 1, "hair": 2, "sunglasses": 3, "upper_clothes": 4, "skirt": 5, "pants": 6,
    "dress": 7, "belt": 8, "left_shoe": 9, "right_shoe": 10, "head": 11, "left_leg": 12, "right_leg": 13,
    "left_arm": 14, "right_arm": 15, "bag": 16, "scarf": 17,
}
CATEGORIES = ("upper_body", "lower_body", "dresses")
TRYON_SLOT = {"upper_body": "upper", "lower_body": "lower", "dresses": "dress"}
DENSEPOSE_PARTS = 24


def load_keypoints(path: Path) -> np.ndarray:
    """(18, 4) array: x, y (384x512 frame), score, id; missing points are -1."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))["keypoints"]
    return np.array(data, dtype=np.float64).reshape((-1, 4))


def inpaint_mask(parse: np.ndarray, pose: np.ndarray, category: str) -> np.ndarray:
    """uint8 (H, W): 255 where IDM-VTON repaints the garment, 0 where it keeps the photo.

    `parse` is the label map resized (nearest) to the training size."""
    if category not in CATEGORIES:
        raise ValueError(f"unknown DressCode category {category!r}")
    height, width = parse.shape
    lab = LABELS
    parse_shape = (parse > 0).astype(np.float32)
    parse_head = ((parse == 1) | (parse == 2) | (parse == 3) | (parse == 11)).astype(np.float32)
    fixed = sum((parse == lab[k]).astype(np.float32)
                for k in ("hair", "left_shoe", "right_shoe", "hat", "sunglasses", "scarf", "bag"))
    changeable = (parse == lab["background"]).astype(np.float32)
    arms = ((parse == 14) | (parse == 15)).astype(np.float32)

    if category == "dresses":
        mask = ((parse == 7) | (parse == 12) | (parse == 13)).astype(np.float32)
        changeable += np.logical_and(parse, np.logical_not(fixed))
    elif category == "upper_body":
        mask = (parse == 4).astype(np.float32)
        fixed += (parse == lab["skirt"]).astype(np.float32) + (parse == lab["pants"]).astype(np.float32)
        changeable += np.logical_and(parse, np.logical_not(fixed))
    else:  # lower_body
        mask = ((parse == 6) | (parse == 12) | (parse == 13)).astype(np.float32)
        fixed += ((parse == lab["upper_clothes"]) | (parse == 14) | (parse == 15)).astype(np.float32)
        changeable += np.logical_and(parse, np.logical_not(fixed))
    del parse_shape  # computed (unused) in the original too

    scale = height / 512.0
    if category in ("dresses", "upper_body"):
        im_arms = Image.new("L", (width, height))
        draw = ImageDraw.Draw(im_arms)
        pt = {i: tuple(np.multiply(pose[i, :2], scale)) for i in (2, 3, 4, 5, 6, 7)}
        sr, sl, er, el, wr, wl = pt[2], pt[5], pt[3], pt[6], pt[4], pt[7]
        if wr[0] <= 1.0 and wr[1] <= 1.0:
            line = [wl, el, sl, sr] if er[0] <= 1.0 and er[1] <= 1.0 else [wl, el, sl, sr, er]
        elif wl[0] <= 1.0 and wl[1] <= 1.0:
            line = [sl, sr, er, wr] if el[0] <= 1.0 and el[1] <= 1.0 else [el, sl, sr, er, wr]
        else:
            line = [wl, el, sl, sr, er, wr]
        draw.line(line, "white", 30, "curve")
        arms_band = np.float32(im_arms)
        if height > 512:
            arms_band = cv2.dilate(arms_band, np.ones((10, 10), np.uint16), iterations=5)
        elif height > 256:
            arms_band = cv2.dilate(arms_band, np.ones((5, 5), np.uint16), iterations=5)
        hands = np.logical_and(np.logical_not(arms_band), arms)
        mask += arms_band
        fixed += hands

    # keep the neck out of the protected head: below the shoulder line it may change
    head_2 = parse_head.copy()
    if category in ("dresses", "upper_body"):
        xs = (pose[2, 0] * scale, pose[5, 0] * scale)
        ys = (pose[2, 1] * scale, pose[5, 1] * scale)
        a = np.vstack([xs, np.ones(2)]).T
        m, c = np.linalg.lstsq(a, ys, rcond=None)[0]
        for i in range(parse.shape[1]):
            y = i * m + c
            head_2[int(y - 20 * scale):, i] = 0

    fixed = np.logical_or(fixed, np.array(head_2, dtype=np.uint16))
    mask += np.logical_or(mask, np.logical_and(np.array(parse_head, dtype=np.uint16),
                                               np.logical_not(np.array(head_2, dtype=np.uint16))))
    if height > 512:
        mask = cv2.dilate(mask, np.ones((20, 20), np.uint16), iterations=5)
    elif height > 256:
        mask = cv2.dilate(mask, np.ones((10, 10), np.uint16), iterations=5)
    else:
        mask = cv2.dilate(mask, np.ones((5, 5), np.uint16), iterations=5)
    keep = np.logical_or(np.logical_and(changeable, np.logical_not(mask)), fixed)  # IDM's agnostic mask
    return np.where(keep, 0, 255).astype(np.uint8)


def render_densepose(part_labels: np.ndarray) -> np.ndarray:
    """RGB uint8 image from DensePose part labels (0 = background, 1..24 = parts)."""
    labels = np.clip(part_labels.astype(np.int32), 0, DENSEPOSE_PARTS)
    values = (labels * 255.0 / DENSEPOSE_PARTS).astype(np.uint8)
    rgb = cv2.applyColorMap(values, cv2.COLORMAP_PARULA)[..., ::-1]
    rgb[labels == 0] = 0
    return np.ascontiguousarray(rgb)


def sample_files(root: Path, category: str, person: str) -> dict[str, Path]:
    """DressCode source files for one person image name ("000000_0.jpg")."""
    stem = person.rsplit("_", 1)[0]
    base = Path(root) / category
    return {
        "person": base / "images" / person,
        "label_map": base / "label_maps" / f"{stem}_4.png",
        "keypoints": base / "keypoints" / f"{stem}_2.json",
        "dense": base / "dense" / f"{stem}_5.png",
        "idm_densepose": base / "image-densepose" / person,  # only with the IDM-VTON authors' download
    }


def read_captions(root: Path, category: str) -> dict[str, str]:
    """dc_caption.txt from the IDM-VTON authors (garment image name -> caption), if present."""
    path = Path(root) / category / "dc_caption.txt"
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split(" ")
        if len(parts) > 1:
            out[parts[0]] = " ".join(parts[1:])
    return out
