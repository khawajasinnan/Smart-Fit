"""Train the straight / wavy hair classifier of services/hairstyle/hair_profile.py
(spec §23.27) on CelebAMask-HQ's human labels.

    python scripts/train_hair_texture.py --dataset ../datasets/CelebAMask-HQ/CelebAMask-HQ [--n 1500]

Faces labelled Wavy_Hair (not Straight_Hair) vs Straight_Hair (not Wavy_Hair),
no hats; features inside the dataset's hand-drawn hair mask. Reports held-out
balanced accuracy overall and on the confident predictions the app uses, then
saves services/hairstyle/models/hair_texture.joblib (non-commercial training
data: the file stays out of git, like the rest of that folder).
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.build_hairstyle_catalog import hair_mask, read_attributes  # noqa: E402
from services.hairstyle.face_mesh import anchors  # noqa: E402
from services.hairstyle.hair_profile import CONFIDENT, TEXTURE_MODEL, texture_features  # noqa: E402


def collect(dataset: Path, n: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    from services.cv_analysis.face_landmarks import FaceLandmarker

    _, attrs = read_attributes(dataset / "CelebAMask-HQ-attribute-anno.txt")
    rng = random.Random(seed)
    pools = {
        1: [i for i, a in attrs.items() if a.get("Wavy_Hair") and not a.get("Straight_Hair") and not a.get("Wearing_Hat")],
        0: [i for i, a in attrs.items() if a.get("Straight_Hair") and not a.get("Wavy_Hair") and not a.get("Wearing_Hat")],
    }
    mesh = FaceLandmarker()
    X, y = [], []
    for label, pool in pools.items():
        rng.shuffle(pool)
        got = 0
        for index in pool:
            if got >= n:
                break
            img = cv2.imread(str(dataset / "CelebA-HQ-img" / f"{index}.jpg"))
            mask = hair_mask(dataset, index, img.shape[0]) if img is not None else None
            a = anchors(mesh.detect(img), img.shape[1], img.shape[0]) if mask is not None else None
            if a is None:
                continue
            f = texture_features(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), mask,
                                 math.dist(a["left_eye"], a["right_eye"]))
            if f is not None:
                X.append(f)
                y.append(label)
                got += 1
    return np.asarray(X), np.asarray(y)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--n", type=int, default=1500, help="faces per class")
    ap.add_argument("--seed", type=int, default=3)
    args = ap.parse_args()
    import joblib
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import balanced_accuracy_score
    from sklearn.model_selection import train_test_split

    X, y = collect(args.dataset, args.n, args.seed)
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.25, stratify=y, random_state=args.seed)

    def forest():
        return RandomForestClassifier(n_estimators=400, min_samples_leaf=3, n_jobs=-1, random_state=args.seed)

    model = forest().fit(Xtr, ytr)
    p = model.predict_proba(Xte)[:, 1]
    sure = (p >= CONFIDENT) | (p <= 1 - CONFIDENT)
    report = {
        "faces": int(len(y)),
        "held_out_balanced_accuracy": round(float(balanced_accuracy_score(yte, p >= 0.5)), 3),
        "confident_share": round(float(sure.mean()), 3),
        "confident_balanced_accuracy": round(float(balanced_accuracy_score(yte[sure], p[sure] >= 0.5)), 3)
        if sure.any() and len(set(yte[sure])) == 2 else None,
    }
    print(json.dumps(report))
    final = forest().fit(X, y)  # all labelled faces for the shipped model
    TEXTURE_MODEL.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(final, TEXTURE_MODEL, compress=3)
    TEXTURE_MODEL.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"saved {TEXTURE_MODEL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
