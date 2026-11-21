"""Build the Kaggle pack for LoRA training on DressCode (spec §8.4, §23.13).

    python services/tryon/lora/build_dresscode_pack.py OUT_DIR [--per-category 2800] [--eval-per-category 16] [--zip]

Runs locally (backend/.venv-cpu). One self-contained private dataset: the
LoRA code, manifests, plan.json and the images it needs (person, garment,
inpaint mask, DensePose) for a seeded subset of each category:
upper_body (tops), lower_body (trousers, skirts) and dresses. Only the
files training reads are included (no uv maps, skeletons, keypoints).

Decision 8 Nov 2026: VITON-HD alone gave no held-out gain (IDM-VTON was
trained on it), so this run uses DressCode, whose lower-body and dress
garments IDM-VTON hasn't learned. A subset first (~10 h on Kaggle T4 x2);
the held-out set is DressCode's paired test split.

Masks: IDM-VTON's own DressCode recipe (services/tryon/dresscode.py).
DensePose and captions: the IDM-VTON authors' pre-computed image-densepose
and dc_caption.txt when they are in the DressCode folders, otherwise
rendered DensePose and a plain category caption (recorded in plan.json).
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

LORA = Path(__file__).resolve().parent
BACKEND = LORA.parents[2]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))

from services.tryon.dresscode import (  # noqa: E402
    CATEGORIES,
    TRYON_SLOT,
    inpaint_mask,
    load_keypoints,
    read_captions,
    render_densepose,
    sample_files,
)

CODE_FILES = ("data.py", "idm.py", "lora_config.py", "train_lora.py", "eval_lora.py", "requirements-lora.txt")
WIDTH, HEIGHT = 768, 1024  # IDM-VTON's training size
FALLBACK_CAPTION = {"upper_body": "top", "lower_body": "bottoms", "dresses": "dress"}
GRAD_ACCUM = 16
SAVE_EVERY = 25
LOG_EVERY = 5
WARMUP_FRACTION = 0.07
SESSION_TRAIN_MINUTES = 640


def convert(job: tuple[str, str, str, str, str]) -> dict:
    """Write one sample's files under OUT/data/<category>/; return its manifest record."""
    root, out, category, person, cloth = job
    root, data = Path(root), Path(out) / "data" / category
    f = sample_files(root, category, person)
    stem = person.rsplit("_", 1)[0]
    rel = {
        "person_image_path": f"{category}/images/{person}",
        "cloth_image_path": f"{category}/images/{cloth}",
        "agnostic_mask_path": f"{category}/agnostic-mask/{stem}_mask.png",
        "densepose_path": f"{category}/image-densepose/{person}",
    }
    for key in ("person_image_path", "cloth_image_path"):
        dest = data.parent / rel[key]
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / rel[key], dest)

    parse = np.array(Image.open(f["label_map"]).resize((WIDTH, HEIGHT), Image.NEAREST))
    mask = inpaint_mask(parse, load_keypoints(f["keypoints"]), category)
    dest = data.parent / rel["agnostic_mask_path"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask).save(dest)

    dest = data.parent / rel["densepose_path"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    if f["idm_densepose"].exists():
        shutil.copy2(f["idm_densepose"], dest)
        densepose_source = "idm-vton authors"
    else:
        labels = np.array(Image.open(f["dense"]).resize((WIDTH, HEIGHT), Image.NEAREST))
        Image.fromarray(render_densepose(labels)).save(dest, quality=95)
        densepose_source = "rendered"
    return rel | {"densepose_source": densepose_source}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--root", default=str(REPO / "datasets" / "DressCode" / "DressCode"))
    ap.add_argument("--per-category", type=int, default=2800)
    ap.add_argument("--eval-per-category", type=int, default=16)
    ap.add_argument("--seed", type=int, default=13)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--zip", action="store_true")
    args = ap.parse_args()

    out, root = Path(args.out), Path(args.root)
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty; choose a new folder.")
    rng = random.Random(args.seed)
    plan_items: dict[str, list[dict]] = {"train": [], "heldout": []}
    jobs, meta = [], []
    captions_found = {}
    for category in CATEGORIES:
        captions = read_captions(root, category)
        captions_found[category] = len(captions)
        for split, pairs_file, n in (("train", "train_pairs.txt", args.per_category),
                                     ("heldout", "test_pairs_paired.txt", args.eval_per_category)):
            pairs = [line.split() for line in (root / category / pairs_file).read_text().splitlines() if line.strip()]
            chosen = sorted(rng.sample(pairs, min(n, len(pairs))))
            for person, cloth in chosen:
                stem = person.rsplit("_", 1)[0]
                jobs.append((str(root), str(out), category, person, cloth))
                meta.append((split, {
                    "category": TRYON_SLOT[category],
                    "source_dataset": "dresscode",
                    "sample_id": f"dresscode:{category}:{'train' if split == 'train' else 'test'}:{stem}",
                    "garment_caption": captions.get(cloth) or FALLBACK_CAPTION[category],
                }))

    print(f"converting {len(jobs)} samples with {args.workers} workers...", flush=True)
    sources: dict[str, int] = {}
    with ProcessPoolExecutor(args.workers) as pool:
        for i, ((split, record), rel) in enumerate(zip(meta, pool.map(convert, jobs, chunksize=32)), 1):
            source = rel.pop("densepose_source")
            sources[source] = sources.get(source, 0) + 1
            plan_items[split].append(rel | record)
            if i % 1000 == 0:
                print(f"  {i}/{len(jobs)}", flush=True)

    train, heldout = plan_items["train"], plan_items["heldout"]
    rng.shuffle(train)
    (out / "data" / "dresscode_pack.json").write_text(json.dumps({"samples": len(jobs)}), encoding="utf-8")
    (out / "manifests").mkdir(parents=True, exist_ok=True)
    for name, items in (("dresscode_train.jsonl", train), ("heldout_eval.jsonl", heldout)):
        (out / "manifests" / name).write_text("".join(json.dumps(r) + "\n" for r in items), encoding="utf-8")
    max_steps = math.ceil(len(train) / GRAD_ACCUM)
    plan = {
        "dataset": "dresscode",
        "train_samples": len(train),
        "train_by_category": {c: sum(r["sample_id"].split(":")[1] == c for r in train) for c in CATEGORIES},
        "passes": 1.0,
        "max_steps": max_steps,
        "grad_accum": GRAD_ACCUM,
        "warmup_steps": max(1, round(max_steps * WARMUP_FRACTION)),
        "save_every": SAVE_EVERY,
        "log_every": LOG_EVERY,
        "augment": "repo",
        "session_train_minutes": SESSION_TRAIN_MINUTES,
        "eval_samples": len(heldout),
        "captions": "idm-vton authors (dc_caption.txt)" if all(captions_found.values())
        else f"category name only (dc_caption.txt found for {captions_found})",
        "densepose": sources,
    }
    (out / "plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    (out / "code").mkdir()
    for name in CODE_FILES:
        shutil.copy2(LORA / name, out / "code" / name)
    (out / "README.txt").write_text(
        "SmartFit LoRA DressCode pack. DressCode is licensed for non-commercial research: keep this dataset "
        "private.\n", encoding="utf-8")
    print(json.dumps(plan, indent=2))
    if args.zip:
        archive = shutil.make_archive(str(out), "zip", root_dir=out)
        print(f"zip: {archive} ({Path(archive).stat().st_size / 1e9:.2f} GB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
