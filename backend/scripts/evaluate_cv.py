"""Run the real CV pipeline over a folder of photos and write a review report.

Spec §6.4: validate on 15-20 varied photos (body types, poses, lighting,
partial body, several people) before the service counts as done.

    python scripts/evaluate_cv.py PHOTOS_DIR OUT_DIR [--labels labels.csv]

PHOTOS_DIR  .jpg/.jpeg/.png files.
labels.csv  optional; columns: file,height_cm,gender,chest_cm,waist_cm,hip_cm,
            expected_body_type,expected_skin_tone,expected_error
            (any column may be empty; height defaults to 165).
OUT_DIR     gets report.csv and one annotated image per photo (landmarks,
            face box, predictions) for checking by eye.

Uses the same strict pipeline as POST /analyze (full body + face required).
"""

from __future__ import annotations

import argparse
import csv
import sys
import time
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.cv_analysis.analysis import AnalysisError, run_analysis  # noqa: E402
from services.cv_analysis.body_classifier import to_spec_size  # noqa: E402
from services.cv_analysis.face import FaceDetector  # noqa: E402
from services.cv_analysis.pose import PoseEstimator, decode_image  # noqa: E402

COLUMNS = [
    "file", "status", "error_code", "body_type", "body_type_source", "confidence", "skin_tone",
    "size", "shoulder_cm", "hip_cm", "torso_cm", "ms", "expected_body_type", "expected_skin_tone",
    "expected_error", "match",
]


def _float(value: str | None) -> float | None:
    return float(value) if value not in (None, "") else None


def load_labels(path: Path | None) -> dict[str, dict[str, str]]:
    if not path:
        return {}
    with path.open(newline="", encoding="utf-8") as fh:
        return {row["file"]: row for row in csv.DictReader(fh)}


def annotate(img, result, text: str):
    out = img.copy()
    if result is not None:
        h, w = out.shape[:2]
        for lm in result.landmarks:
            if lm.visibility >= 0.5:
                cv2.circle(out, (int(lm.x * w), int(lm.y * h)), 4, (255, 0, 200), -1)
        if result.face:
            f = result.face
            cv2.rectangle(out, (f.x, f.y), (f.x + f.w, f.y + f.h), (0, 220, 0), 2)
    for i, line in enumerate(text.split("\n")):
        cv2.putText(out, line, (10, 30 + 28 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 4)
        cv2.putText(out, line, (10, 30 + 28 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("photos", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--labels", type=Path)
    args = ap.parse_args()

    files = sorted(p for p in args.photos.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"})
    if not files:
        print(f"No photos in {args.photos}")
        return 1
    labels = load_labels(args.labels)
    args.out.mkdir(parents=True, exist_ok=True)
    pose, faces = PoseEstimator(), FaceDetector()
    rows = []
    try:
        for f in files:
            lab = labels.get(f.name, {})
            img = decode_image(f.read_bytes())
            started = time.perf_counter()
            row = {c: "" for c in COLUMNS} | {"file": f.name}
            row |= {k: lab.get(k, "") for k in ("expected_body_type", "expected_skin_tone", "expected_error")}
            result = None
            try:
                result = run_analysis(
                    img, pose, faces,
                    height_cm=_float(lab.get("height_cm")) or 165.0,
                    gender=lab.get("gender") or None,
                    chest_cm=_float(lab.get("chest_cm")),
                    waist_cm=_float(lab.get("waist_cm")),
                    hip_cm=_float(lab.get("hip_cm")),
                    require_full_body=True,
                    require_face=True,
                )
                m = result.measurements or {}
                row |= {
                    "status": "ok",
                    "body_type": result.body_type,
                    "body_type_source": result.body_type_source,
                    "confidence": result.body_type_confidence,
                    "skin_tone": result.skin_bucket,
                    "size": to_spec_size(result.size_label),
                    **{k: m.get(k, "") for k in ("shoulder_cm", "hip_cm", "torso_cm")},
                }
                text = f"{result.body_type} ({result.body_type_source})\nskin {result.skin_bucket}  size {row['size']}"
            except AnalysisError as exc:
                row |= {"status": "error", "error_code": exc.code}
                text = exc.code
            row["ms"] = round((time.perf_counter() - started) * 1000)
            checks = [
                (row["expected_body_type"], row["body_type"]),
                (row["expected_skin_tone"], row["skin_tone"]),
                (row["expected_error"], row["error_code"]),
            ]
            labelled = [(e, a) for e, a in checks if e]
            row["match"] = "" if not labelled else str(all(e == a for e, a in labelled))
            cv2.imwrite(str(args.out / f"{f.stem}_review.jpg"), annotate(img, result, text))
            rows.append(row)
            print(f"{f.name:30} {row['status']:5} {row['error_code'] or row['body_type']:18} "
                  f"{row['skin_tone']:7} {row['size']:3} {row['ms']} ms  {row['match']}")
    finally:
        pose.close()
        faces.close()

    with (args.out / "report.csv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    labelled = [r for r in rows if r["match"]]
    ok = sum(r["match"] == "True" for r in labelled)
    print(f"\n{len(rows)} photos, {sum(r['status'] == 'ok' for r in rows)} analysed. "
          f"Labelled checks: {ok}/{len(labelled)} match. Report: {args.out / 'report.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
