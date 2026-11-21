"""Measure the try-on gender checks on REAL photos (never used for training).

    python scripts/eval_gender_checks.py --men   "../datasets/eval-phots/SmartFit Men-..."
                                         --women "../datasets/eval-phots/Smartfit Women-..."
                                         [--viton "../datasets/viton-hd test split"]

--men / --women take a folder (searched recursively) or a .zip, and can be
repeated, so new photo batches are just another argument.

* person: full-body photos -> the CV service's own person check (MediaPipe +
  HRNet, in-process) -> head crop (shared/head_crop.py, as in the try-on) ->
  face model. Reports how often the head is found, how often the model is sure,
  and how often a sure answer is right.
* garment: the VITON-HD garment photos (all women's tops) -> garment model.

Photos are read from the local datasets folder only; nothing is saved.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))


IMAGE_EXTS = (".heic", ".heif", ".jpg", ".jpeg", ".png", ".webp")


def _open(data: bytes) -> Image.Image:
    from PIL import ImageOps

    img = ImageOps.exif_transpose(Image.open(io.BytesIO(data)))  # phone photos are often stored sideways
    img = img.convert("RGB")
    img.thumbnail((1200, 1600))
    return img


def load_photos(path: Path) -> list[tuple[str, Image.Image]]:
    """(name, photo) for every photo in a folder (searched recursively) or a .zip: HEIC, JPG, PNG, WEBP."""
    import pillow_heif

    pillow_heif.register_heif_opener()
    out = []
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as z:
            for name in sorted(z.namelist()):
                if name.lower().endswith(IMAGE_EXTS):
                    out.append((name, _open(z.read(name))))
    else:
        for f in sorted(path.rglob("*")):
            if f.is_file() and f.suffix.lower() in IMAGE_EXTS:
                out.append((str(f.relative_to(path)), _open(f.read_bytes())))
    return out


def load_viton(folder: Path) -> tuple[list[tuple[str, Image.Image]], list[Image.Image]]:
    """VITON-HD test split: model photos (00000_00.jpg) and garment photos (*_cloth.jpg)."""
    people, clothes = [], []
    for f in sorted(folder.glob("*.jpg")):
        target = clothes if f.stem.endswith("_cloth") else people if "_" in f.stem and f.stem.count("_") == 1 else None
        if target is not None:
            img = Image.open(f).convert("RGB")
            target.append((f.name, img) if target is people else img)
    return people, clothes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--men", type=Path, action="append", default=[], help="folder or .zip of men's photos (repeatable)")
    ap.add_argument("--women", type=Path, action="append", default=[], help="folder or .zip of women's photos (repeatable)")
    ap.add_argument("--viton", type=Path, help="VITON-HD test split folder (women + women's garments)")
    a = ap.parse_args()

    from services.cv_analysis.hrnet import HRNetEstimator
    from services.cv_analysis.main import person_check
    from services.cv_analysis.pose import PoseEstimator
    from services.recommendation.embeddings import FashionClip
    from services.recommendation.gender_check import GenderChecker
    from shared.head_crop import crop_head
    from shared.schemas.cv import PersonCheckRequest

    pose, hrnet = PoseEstimator(), HRNetEstimator()
    checker = GenderChecker(FashionClip())

    def judge_people(images: list[tuple[str, Image.Image]], truth: str) -> dict:
        """The try-on's own rule: face model on the head crop, whole photo as a second opinion."""
        found = sure = right = 0
        disagree = []
        for name, img in images:
            bgr = np.asarray(img)[:, :, ::-1].copy()
            res = person_check(bgr, PersonCheckRequest.model_construct(image_base64="", category="upper", angle="front"),
                               pose, hrnet)
            head = crop_head(img, [k.model_dump() for k in res.keypoints])
            if head is None:
                continue
            found += 1
            v = checker.check_person(head, img)
            if v.label is not None:
                sure += 1
                right += v.label == truth
                if v.label != truth:
                    disagree.append(name)
        n = len(images)
        return {"photos": n, "head_found": found, "sure": sure, "right_when_sure": right,
                "precision": round(right / sure, 4) if sure else None, "sure_share": round(sure / n, 4) if n else None,
                # sure answers that contradict the folder: a model mistake OR a photo in the wrong
                # folder (19 Nov 2026: 5 photos of men were in the women's folder). Look at them.
                "check_these_photos": disagree}

    report = {}
    if a.men:
        report["men_photos"] = judge_people([i for p in a.men for i in load_photos(p)], "man")
    if a.women:
        report["women_photos"] = judge_people([i for p in a.women for i in load_photos(p)], "woman")
    if a.viton:
        people, clothes = load_viton(a.viton)
        report["viton_women"] = judge_people(people, "woman")
        g = [checker.check(c, "garment").label for c in clothes]
        report["viton_women_garments"] = {"photos": len(g), "said_women": g.count("women"),
                                          "said_men": g.count("men"), "not_sure": g.count(None)}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
