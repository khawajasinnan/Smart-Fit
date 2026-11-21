"""Normalise VITON-HD into TryOnSample manifests (spec §5.6).

    python scripts/build_tryon_manifest.py [--viton DATASET_DIR] [--out OUT_DIR] [--tags-dir DIR]

Writes OUT_DIR/vitonhd_train.jsonl and vitonhd_test.jsonl (default
datasets/manifests/, gitignored), paired setting, paths relative to the
VITON-HD root. Garment captions come from IDM-VTON's
vitonhd_{train,test}_tagged.json at the pinned commit (downloaded unless
--tags-dir has them).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.tryon.preprocessing import (  # noqa: E402
    DEFAULT_CAPTION,
    load_tagged,
    vitonhd_captions,
    vitonhd_samples,
    write_manifest,
)

REPO = Path(__file__).resolve().parents[2]
IDM_COMMIT = "0d5f3ec2d737487a9bb24e4100936ad254780383"
TAGS_URL = "https://raw.githubusercontent.com/yisol/IDM-VTON/{commit}/vitonhd_{split}_tagged.json"


def tags_file(split: str, tags_dir: Path) -> Path:
    path = tags_dir / f"vitonhd_{split}_tagged.json"
    if not path.exists():
        res = httpx.get(TAGS_URL.format(commit=IDM_COMMIT, split=split), timeout=120, follow_redirects=False)
        res.raise_for_status()
        tags_dir.mkdir(parents=True, exist_ok=True)
        path.write_bytes(res.content)
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--viton", default=str(REPO / "datasets" / "viton-hd"))
    ap.add_argument("--out", default=str(REPO / "datasets" / "manifests"))
    ap.add_argument("--tags-dir", help="folder with vitonhd_*_tagged.json (default: OUT/tags, downloaded)")
    args = ap.parse_args()

    root, out = Path(args.viton), Path(args.out)
    tags_dir = Path(args.tags_dir) if args.tags_dir else out / "tags"
    for split in ("train", "test"):
        captions = vitonhd_captions(load_tagged(tags_file(split, tags_dir)))
        samples = vitonhd_samples(root, split, captions)
        n = write_manifest(samples, out / f"vitonhd_{split}.jsonl")
        fallback = sum(1 for s in samples if s.garment_caption == DEFAULT_CAPTION)
        print(f"{split}: {n} samples -> {out / f'vitonhd_{split}.jsonl'} "
              f"({fallback} without a tagged caption use '{DEFAULT_CAPTION}')")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
