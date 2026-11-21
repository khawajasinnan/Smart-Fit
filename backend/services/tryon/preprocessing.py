"""Try-on preprocessing.

1. Dataset normalisation (spec §5.6), used now: turn a source dataset into
   TryOnSample records and write them as a JSON Lines manifest.
   * VITON-HD: masks, agnostic images and DensePose ship with the dataset
     (spec §23.5); the training set is the paired setting (each person with
     their own garment), the same as IDM-VTON's train_xl.py.
   * DressCode and curated scraped pairs: added when available (spec §23.4).

2. Request-time input preparation for user photos (SFR-026/027) is not here:
   framing/validation is imaging.py; the garment mask, OpenPose and DensePose
   run on the GPU in modal_app.py (IDM-VTON's own demo pipeline).
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path

from shared.schemas.tryon import TryOnSample

# IDM-VTON's caption: these tags, in this order (its train_xl.py / inference.py).
CAPTION_TAGS = ("sleeveLength", "neckLine", "item")
DEFAULT_CAPTION = "shirts"


def vitonhd_captions(tagged: dict) -> dict[str, str]:
    """file name -> garment caption from vitonhd_{train,test}_tagged.json."""
    captions = {}
    for entries in tagged.values():
        for elem in entries:
            parts = []
            for tag_name in CAPTION_TAGS:
                for tag in elem["tag_info"]:
                    if tag["tag_name"] == tag_name and tag["tag_category"] is not None:
                        parts.append(tag["tag_category"])
            captions[elem["file_name"]] = " ".join(parts)
    return captions


def vitonhd_samples(root: Path, split: str, captions: dict[str, str]) -> list[TryOnSample]:
    """Paired samples for one split, in pairs-file order; persons whose files
    are missing are skipped (verify_vitonhd.py reports them)."""
    if split not in ("train", "test"):
        raise ValueError(f"unknown VITON-HD split {split!r}")
    samples = []
    for line in (root / f"{split}_pairs.txt").read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        name = parts[0]  # paired: the person's own garment has the same file name
        stem = name.removesuffix(".jpg")
        paths = {
            "person_image_path": f"{split}/image/{name}",
            "cloth_image_path": f"{split}/cloth/{name}",
            "agnostic_mask_path": f"{split}/agnostic-mask/{stem}_mask.png",
            "agnostic_person_path": f"{split}/agnostic-v3.2/{name}",
            "densepose_path": f"{split}/image-densepose/{name}",
        }
        if not all((root / p).is_file() for p in paths.values()):
            continue
        samples.append(TryOnSample(
            **paths,
            category="upper",
            source_dataset="viton-hd",
            sample_id=f"viton-hd:{split}:{stem}",
            garment_caption=captions.get(name) or DEFAULT_CAPTION,
        ))
    return samples


def write_manifest(samples: Iterable[TryOnSample], path: Path) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with path.open("w", encoding="utf-8", newline="\n") as f:
        for sample in samples:
            f.write(sample.model_dump_json() + "\n")
            n += 1
    return n


def read_manifest(path: Path) -> list[TryOnSample]:
    return [TryOnSample.model_validate_json(line)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def load_tagged(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))
