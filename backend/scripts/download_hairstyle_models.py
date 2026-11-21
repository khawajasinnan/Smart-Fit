"""Download the hairstyle service's models into services/hairstyle/models/.

  python scripts/download_hairstyle_models.py      # from backend/, in .venv-cpu

1. dlib 5-point face landmarks (shape_predictor_5_face_landmarks.dat, 9 MB):
   Davis King's model, trained on dlib's own 5-point dataset and released
   into the public domain (CC0). Used with dlib's built-in HOG face detector
   by the camera's face check (face_gate.py).
2. MediaPipe Hair Segmenter (hair_segmenter.tflite, Apache-2.0, 0.8 MB):
   where the user's own hair is (overlay.py).

Both are checksum-pinned. The face landmarker / face detector the service
also uses come from services/cv_analysis/models (scripts/download_cv_models.py).
"""

from __future__ import annotations

import bz2
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from download_cv_models import download, sha256  # noqa: E402

MODELS_DIR = Path(__file__).resolve().parents[1] / "services" / "hairstyle" / "models"

DLIB_URL = "https://github.com/davisking/dlib-models/raw/master/shape_predictor_5_face_landmarks.dat.bz2"
DLIB_BZ2_SHA256 = "6e787bbebf5c9efdb793f6cd1f023230c4413306605f24f299f12869f95aa472"
HAIR_URL = "https://storage.googleapis.com/mediapipe-models/image_segmenter/hair_segmenter/float32/1/hair_segmenter.tflite"
HAIR_SHA256 = "2628cf3ce5f695f604cbea2841e00befcaa3624bf80caf3664bef2656d59bf84"


def main() -> None:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    download(HAIR_URL, MODELS_DIR / "hair_segmenter.tflite", HAIR_SHA256)
    dat = MODELS_DIR / "shape_predictor_5_face_landmarks.dat"
    if dat.exists():
        print(f"ok        {dat.name} (already unpacked)")
        return
    packed = MODELS_DIR / "shape_predictor_5_face_landmarks.dat.bz2"
    download(DLIB_URL, packed, DLIB_BZ2_SHA256)
    dat.write_bytes(bz2.decompress(packed.read_bytes()))
    packed.unlink()
    print(f"ok        {dat.name} ({dat.stat().st_size / 1e6:.1f} MB, sha256 {sha256(dat)[:12]}...)")


if __name__ == "__main__":
    main()
