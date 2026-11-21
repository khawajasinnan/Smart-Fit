"""Calibrate the skin analyzer's undertone cut-offs on real faces (21 Nov 2026).

    python scripts/calibrate_undertone.py [N]

Runs the analyzer's own measurement (services/cv_analysis/skin_tone.py:
analyze_skin_detail, white balance from neutral pixels + face skin pixels) over N random
CelebAMask-HQ faces and prints the skin hue angle (CIELAB atan2(b*, a*))
percentiles, overall and per depth bucket. No study gives validated
warm/neutral/cool cut-offs for this angle, so the analyzer uses the population
tertiles: a third of faces each side of the neutral band. Its answer is a
starting point the app confirms with the vein and jewellery questions.
CelebAMask-HQ is non-commercial research data; only numbers come out of here.
"""

from __future__ import annotations

import random
import sys
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from services.cv_analysis.face import FaceDetector  # noqa: E402
from services.cv_analysis.skin_tone import analyze_skin_detail  # noqa: E402

IMAGES = BACKEND.parent / "datasets" / "CelebAMask-HQ" / "CelebAMask-HQ" / "CelebA-HQ-img"


def main(n: int) -> None:
    files = sorted(IMAGES.glob("*.jpg"))
    random.Random(7).shuffle(files)
    faces = FaceDetector()
    hues: list[float] = []
    by_bucket: dict[str, list[float]] = defaultdict(list)
    skipped = 0
    for path in files[:n]:
        img = cv2.imread(str(path))
        found = faces.detect(img) if img is not None else []
        detail = analyze_skin_detail(img, found[0]) if found else None
        if detail is None:
            skipped += 1
            continue
        hues.append(detail["hue_angle"])
        by_bucket[detail["bucket"]].append(detail["hue_angle"])
    pct = (10, 33, 50, 67, 90)
    print(f"{len(hues)} faces measured, {skipped} skipped (no face / no skin pixels)")
    print("all     ", {p: round(float(np.percentile(hues, p)), 1) for p in pct})
    for bucket in ("fair", "light", "medium", "tan", "brown", "deep"):
        v = by_bucket.get(bucket, [])
        if len(v) >= 20:
            print(f"{bucket:8}", {p: round(float(np.percentile(v, p)), 1) for p in pct}, f"n={len(v)}")
        else:
            print(f"{bucket:8} n={len(v)} (too few)")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 1500)
