"""Dataset normalisation to TryOnSample manifests (spec §5.6)."""

import json

import pytest
from pydantic import ValidationError

from services.tryon.preprocessing import (
    read_manifest,
    vitonhd_captions,
    vitonhd_samples,
    write_manifest,
)
from shared.schemas.tryon import TryOnSample


def _viton(tmp_path, names, missing=()):
    for split_dir in ("image", "cloth", "agnostic-mask", "agnostic-v3.2", "image-densepose"):
        (tmp_path / "train" / split_dir).mkdir(parents=True)
    for name in names:
        stem = name.removesuffix(".jpg")
        files = [f"image/{name}", f"cloth/{name}", f"agnostic-mask/{stem}_mask.png",
                 f"agnostic-v3.2/{name}", f"image-densepose/{name}"]
        for rel in files:
            if rel not in missing:
                (tmp_path / "train" / rel).write_bytes(b"x")
    # official pair files are unpaired; the training set uses each person's own garment
    (tmp_path / "train_pairs.txt").write_text("".join(f"{n} other_{n}\n" for n in names) + "\n")
    return tmp_path


def test_captions_follow_idm_vton_tag_order():
    tags = {"data": [{"file_name": "a.jpg", "tag_info": [
        {"tag_name": "item", "tag_category": "T-shirts"},
        {"tag_name": "neckLine", "tag_category": "Round Neck"},
        {"tag_name": "sleeveLength", "tag_category": "Short Sleeve"},
        {"tag_name": "colors", "tag_category": "Navy"},
    ]}, {"file_name": "b.jpg", "tag_info": [{"tag_name": "neckLine", "tag_category": None}]}]}
    assert vitonhd_captions(tags) == {"a.jpg": "Short Sleeve Round Neck T-shirts", "b.jpg": ""}


def test_vitonhd_samples_are_paired_relative_and_skip_incomplete(tmp_path):
    root = _viton(tmp_path, ["00001_00.jpg", "00002_00.jpg"], missing={"image-densepose/00002_00.jpg"})
    samples = vitonhd_samples(root, "train", {"00001_00.jpg": "Long Sleeve Blouses"})
    assert len(samples) == 1
    s = samples[0]
    assert s.person_image_path == "train/image/00001_00.jpg"
    assert s.cloth_image_path == "train/cloth/00001_00.jpg"  # own garment, not other_*
    assert s.agnostic_mask_path == "train/agnostic-mask/00001_00_mask.png"
    assert (s.category, s.source_dataset, s.sample_id) == ("upper", "viton-hd", "viton-hd:train:00001_00")
    assert s.garment_caption == "Long Sleeve Blouses"


def test_missing_caption_falls_back_like_idm_vton(tmp_path):
    root = _viton(tmp_path, ["00003_00.jpg"])
    assert vitonhd_samples(root, "train", {})[0].garment_caption == "shirts"


def test_manifest_roundtrip_and_schema(tmp_path):
    root = _viton(tmp_path, ["00001_00.jpg"])
    samples = vitonhd_samples(root, "train", {})
    path = tmp_path / "m" / "train.jsonl"
    assert write_manifest(samples, path) == 1
    assert read_manifest(path) == samples
    record = json.loads(path.read_text().splitlines()[0])
    with pytest.raises(ValidationError):
        TryOnSample(**(record | {"source_dataset": "somewhere-else"}))
    with pytest.raises(ValueError):
        vitonhd_samples(root, "val", {})
