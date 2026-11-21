"""Build the hairstyle catalog from CelebAMask-HQ (spec §11.2, decision 14 Nov 2026).

  python scripts/build_hairstyle_catalog.py --dataset "D:/datasets/CelebAMask-HQ"   # from backend/, in .venv-cpu

CelebAMask-HQ (Lee et al., CVPR 2020): 30,000 CelebA-HQ faces (1024x1024)
with hand-drawn masks for 19 face parts, including hair, plus CelebA's 40
attributes (Male, Bangs, Wavy_Hair, Black_Hair, Wearing_Hat, ...).
Non-commercial research use only: the cut-outs are written to
services/hairstyle/catalog/ (gitignored), never committed or shipped.

Expected layout (the official download, unzipped):
    CelebA-HQ-img/<i>.jpg
    CelebAMask-HQ-mask-anno/<i // 2000>/<i:05d>_hair.png   (512x512)
    CelebAMask-HQ-attribute-anno.txt

For each candidate face:
  1. skip hats, bald heads, turned or tilted faces (MediaPipe face mesh) and
     hair cut off at the top or the sides of the photo;
  2. measure the style: length, bangs, waves, height on top, width at the sides;
  3. cut the hair out as an RGBA PNG (the mask, softened at the edge; long hair
     that runs off the bottom of the photo fades out) with the eye and chin
     anchors overlay.py aligns to;
then keep a varied set: the best example of each (gender, length, bangs,
waves, colour) combination, up to --per-gender styles per gender.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from services.hairstyle.face_mesh import CHEEK_L, CHEEK_R, anchors, face_turn, skin_luma  # noqa: E402

CATALOG_DIR = BACKEND / "services" / "hairstyle" / "catalog"
MAX_TURN = 0.10
MAX_ROLL_DEG = 6.0
MIN_HAIR_FRACTION = 0.03  # of the photo
EDGE = 4  # px at the photo border that count as "touching it"
MAX_EDGE_TOUCH = 0.02  # hair on more than this share of the top/left/right border = cut off
MIN_MAIN_COMPONENT = 0.85  # the largest hair blob holds at least this share (clean mask)
FADE_FRACTION = 0.10  # long hair running off the bottom fades out over this share of the height
COLOURS = ("Black_Hair", "Brown_Hair", "Blond_Hair", "Gray_Hair")


@dataclass
class Candidate:
    index: int
    gender: str
    length: str
    bangs: bool
    wavy: bool
    colour: str
    top_volume: float
    side_width: float
    quality: float


def read_attributes(path: Path) -> tuple[list[str], dict[int, dict[str, bool]]]:
    lines = path.read_text(encoding="utf-8").split("\n")
    names = lines[1].split()
    table = {}
    for line in lines[2:]:
        parts = line.split()
        if len(parts) != len(names) + 1:
            continue
        index = int(parts[0].split(".")[0])
        table[index] = {n: v == "1" for n, v in zip(names, parts[1:])}
    return names, table


def hair_mask(dataset: Path, index: int, size: int) -> np.ndarray | None:
    path = dataset / "CelebAMask-HQ-mask-anno" / str(index // 2000) / f"{index:05d}_hair.png"
    mask = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if mask is None:
        return None
    return cv2.resize(mask, (size, size), interpolation=cv2.INTER_LINEAR) > 127


def mask_is_usable(mask: np.ndarray) -> tuple[bool, bool]:
    """(usable, runs off the bottom). Cut off at the top or sides, too small or
    in pieces = unusable."""
    h, w = mask.shape
    if mask.mean() < MIN_HAIR_FRACTION:
        return False, False
    if mask[:EDGE].mean() > MAX_EDGE_TOUCH or mask[:, :EDGE].mean() > MAX_EDGE_TOUCH \
            or mask[:, -EDGE:].mean() > MAX_EDGE_TOUCH:
        return False, False
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if count < 2 or stats[1:, cv2.CC_STAT_AREA].max() / mask.sum() < MIN_MAIN_COMPONENT:
        return False, False
    return True, bool(mask[-EDGE:].mean() > MAX_EDGE_TOUCH)


def measure(mask: np.ndarray, a: dict[str, list[float]], face_w: float, off_bottom: bool) -> dict[str, float | str]:
    """Length class, height on top and width at the cheeks, relative to the face."""
    face_len = math.dist(a["forehead"], a["chin"]) or 1.0
    ys, xs = np.nonzero(mask)
    lowest = ys.max()
    below_chin = (lowest - a["chin"][1]) / face_len
    length = "long" if off_bottom or below_chin > 1.0 else "medium" if below_chin > 0.15 else "short"
    top_volume = max(0.0, (a["forehead"][1] - ys.min()) / face_len)
    eye_y = int((a["left_eye"][1] + a["right_eye"][1]) / 2)
    row = np.nonzero(mask[max(0, eye_y - 3):eye_y + 4].any(axis=0))[0]
    side_width = (row.max() - row.min()) / face_w if len(row) else 1.0
    return {"length": length, "top_volume": round(float(top_volume), 3), "side_width": round(float(side_width), 3)}


def cutout(img_bgr: np.ndarray, mask: np.ndarray, off_bottom: bool, a: dict[str, list[float]]):
    """RGBA hair cut-out cropped to the hair, and the anchors moved into it."""
    h, w = mask.shape
    m = cv2.erode(mask.astype(np.uint8) * 255, np.ones((3, 3), np.uint8), iterations=1)  # no background halo
    alpha = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 1.2)
    if off_bottom:
        fade = np.ones(h, np.float32)
        n = int(FADE_FRACTION * h)
        fade[h - n:] = np.linspace(1.0, 0.0, n)
        alpha *= fade[:, None]
    ys, xs = np.nonzero(alpha > 4)
    pad = 6
    x0, y0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
    x1, y1 = min(w, xs.max() + pad + 1), min(h, ys.max() + pad + 1)
    rgba = np.dstack([img_bgr, np.clip(alpha, 0, 255).astype(np.uint8)])[y0:y1, x0:x1]
    moved = {k: [round(v[0] - x0, 2), round(v[1] - y0, 2)] for k, v in a.items()}
    return rgba, moved


def style_name(gender: str, length: str, wavy: bool, bangs: bool) -> str:
    texture = "wavy" if wavy else ("textured" if gender == "male" else "straight")
    if gender == "male":
        base = {"short": f"Short {texture} cut", "medium": f"Medium-length {texture} style",
                "long": f"Long {texture} hair"}[length]
        return base + (" with a fringe" if bangs else "")
    base = {"short": f"Short {texture} cut", "medium": f"Shoulder-length {texture} hair",
            "long": f"Long {texture} hair"}[length]
    return base + (" with bangs" if bangs else "")


def select(candidates: list[Candidate], per_gender: int) -> list[Candidate]:
    """Best example of each look, then fill up to per_gender with the next best."""
    chosen: list[Candidate] = []
    for gender in ("female", "male"):
        groups: dict[tuple, list[Candidate]] = defaultdict(list)
        for c in candidates:
            if c.gender == gender:
                groups[(c.length, c.bangs, c.wavy, c.colour)].append(c)
        for g in groups.values():
            g.sort(key=lambda c: c.quality, reverse=True)
        picked: list[Candidate] = []
        rank = 0
        while len(picked) < per_gender and any(len(g) > rank for g in groups.values()):
            layer = sorted((g[rank] for g in groups.values() if len(g) > rank), key=lambda c: c.quality, reverse=True)
            picked.extend(layer[: per_gender - len(picked)])
            rank += 1
        chosen.extend(picked)
    return chosen


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", type=Path, required=True, help="the unzipped CelebAMask-HQ folder")
    parser.add_argument("--per-gender", type=int, default=40, help="styles per gender (default 40)")
    parser.add_argument("--scan", type=int, default=6000, help="faces to examine (random sample, default 6000)")
    parser.add_argument("--out", type=Path, default=CATALOG_DIR)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    images = args.dataset / "CelebA-HQ-img"
    attr_file = args.dataset / "CelebAMask-HQ-attribute-anno.txt"
    for needed in (images, attr_file, args.dataset / "CelebAMask-HQ-mask-anno"):
        if not needed.exists():
            sys.exit(f"Not found: {needed}. Point --dataset at the unzipped CelebAMask-HQ folder.")
    _, attrs = read_attributes(attr_file)

    from services.cv_analysis.face_landmarks import FaceLandmarker

    mesh = FaceLandmarker()
    pool = [i for i, a in attrs.items() if not a.get("Wearing_Hat") and not a.get("Bald")]
    random.Random(args.seed).shuffle(pool)
    candidates: list[Candidate] = []
    skipped: dict[str, int] = defaultdict(int)
    for n, index in enumerate(pool[: args.scan], 1):
        img = cv2.imread(str(images / f"{index}.jpg"))
        if img is None:
            skipped["no image"] += 1
            continue
        size = img.shape[0]
        mask = hair_mask(args.dataset, index, size)
        if mask is None:
            skipped["no hair mask"] += 1
            continue
        usable, off_bottom = mask_is_usable(mask)
        if not usable:
            skipped["hair cut off / unclear"] += 1
            continue
        points = mesh.detect(img)
        a = anchors(points, size, size)
        if a is None:
            skipped["no face mesh"] += 1
            continue
        turn = face_turn(points)
        (lx, ly), (rx, ry) = sorted((a["left_eye"], a["right_eye"]))
        roll = abs(math.degrees(math.atan2(ry - ly, rx - lx)))
        if turn > MAX_TURN or roll > MAX_ROLL_DEG:
            skipped["face turned or tilted"] += 1
            continue
        face_w = abs(points[CHEEK_L][0] - points[CHEEK_R][0]) * size
        m = measure(mask, a, face_w, off_bottom)
        at = attrs[index]
        colour = next((c.split("_")[0].lower() for c in COLOURS if at.get(c)), "dark")
        quality = 1.0 - turn / MAX_TURN * 0.5 - roll / MAX_ROLL_DEG * 0.3 - (0.2 if off_bottom else 0.0)
        candidates.append(Candidate(index, "male" if at.get("Male") else "female", str(m["length"]),
                                    bool(at.get("Bangs")), bool(at.get("Wavy_Hair")), colour,
                                    float(m["top_volume"]), float(m["side_width"]), quality))
        if n % 500 == 0:
            print(f"  examined {n}, usable {len(candidates)}")

    chosen = select(candidates, args.per_gender)
    args.out.mkdir(parents=True, exist_ok=True)
    for old in args.out.glob("*.png"):
        old.unlink()
    index_out = []
    for c in chosen:
        img = cv2.imread(str(images / f"{c.index}.jpg"))
        size = img.shape[0]
        mask = hair_mask(args.dataset, c.index, size)
        _, off_bottom = mask_is_usable(mask)
        points = mesh.detect(img)
        a = anchors(points, size, size)
        rgba, moved = cutout(img, mask, off_bottom, a)
        style_id = f"{c.gender}-{c.length}-{'wavy' if c.wavy else 'straight'}{'-bangs' if c.bangs else ''}-{c.index}"
        cv2.imwrite(str(args.out / f"{style_id}.png"), rgba)
        index_out.append({
            "id": style_id,
            "name": style_name(c.gender, c.length, c.wavy, c.bangs),
            "colour": c.colour,
            "file": f"{style_id}.png",
            "anchors": moved,
            "skin_luma": skin_luma(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), points),
            "features": {"gender": c.gender, "length": c.length, "bangs": c.bangs, "wavy": c.wavy,
                         "top_volume": c.top_volume, "side_width": c.side_width},
            "source": f"CelebAMask-HQ #{c.index}",
        })
    mesh.close()
    (args.out / "index.json").write_text(json.dumps(index_out, indent=1), encoding="utf-8")
    by_gender = defaultdict(int)
    for item in index_out:
        by_gender[item["features"]["gender"]] += 1
    print(f"examined {min(args.scan, len(pool))} faces, usable {len(candidates)}; skipped: {dict(skipped)}")
    print(f"catalog: {len(index_out)} styles ({dict(by_gender)}) -> {args.out}")


if __name__ == "__main__":
    main()
