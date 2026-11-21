"""Build the Kaggle pack for the full LoRA run on VITON-HD (spec §8.4, §23.9).

    python services/tryon/lora/build_full_pack.py OUT_DIR [--passes 1] [--eval-samples 48] [--zip]

Runs locally (backend/.venv-cpu). Small: the LoRA code, the train manifest,
a held-out evaluation manifest and plan.json (the run settings the notebook
passes to train_lora.py). The images come from your private VITON-HD
dataset on Kaggle; the manifests' paths are relative to its root (the folder
with train_pairs.txt).

Run length (decision 27 Oct 2026): one pass over the 11,647 train pairs,
updates of 16 pairs, about 15 GPU hours on Kaggle T4 x2 (two sessions).
The held-out set is drawn from the test split, which neither IDM-VTON nor
this LoRA trains on, leaving out the overfit test's 8 samples.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import sys
from pathlib import Path

LORA = Path(__file__).resolve().parent
BACKEND = LORA.parents[2]
REPO = BACKEND.parent
CODE_FILES = ("data.py", "idm.py", "lora_config.py", "train_lora.py", "eval_lora.py", "requirements-lora.txt")

# Settings for this run (lora_config.py keeps the spec's starting values).
GRAD_ACCUM = 16
SAVE_EVERY = 25  # updates; ~30 min of training, the most a lost session can cost
LOG_EVERY = 5
WARMUP_FRACTION = 0.07
# A Kaggle session ends at 12 h. Stop training here (minutes since the script
# started, model loading included) and leave time for checkpointing and zipping.
SESSION_TRAIN_MINUTES = 640


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--train-manifest", default=str(REPO / "datasets" / "manifests" / "vitonhd_train.jsonl"))
    ap.add_argument("--test-manifest", default=str(REPO / "datasets" / "manifests" / "vitonhd_test.jsonl"))
    ap.add_argument("--overfit-ids", default=str(BACKEND / "data" / "lora-overfit-pack" / "overfit_ids.txt"))
    ap.add_argument("--passes", type=float, default=1.0, help="passes over the train set")
    ap.add_argument("--eval-samples", type=int, default=48)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--zip", action="store_true")
    args = ap.parse_args()

    out = Path(args.out)
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty; choose a new folder.")
    train = read_jsonl(Path(args.train_manifest))
    test = read_jsonl(Path(args.test_manifest))
    overfit = set(Path(args.overfit_ids).read_text(encoding="utf-8").split()) if Path(args.overfit_ids).exists() else set()
    if {r["sample_id"] for r in train} & {r["sample_id"] for r in test}:
        sys.exit("train and test manifests share samples")

    pool = [r for r in test if r["sample_id"] not in overfit]
    heldout = sorted(random.Random(args.seed).sample(pool, args.eval_samples), key=lambda r: r["sample_id"])
    max_steps = math.ceil(len(train) * args.passes / GRAD_ACCUM)
    plan = {
        "train_samples": len(train),
        "passes": args.passes,
        "max_steps": max_steps,
        "grad_accum": GRAD_ACCUM,
        "warmup_steps": max(1, round(max_steps * WARMUP_FRACTION)),
        "save_every": SAVE_EVERY,
        "log_every": LOG_EVERY,
        "augment": "repo",
        "session_train_minutes": SESSION_TRAIN_MINUTES,
        "eval_samples": len(heldout),
        "excluded_from_eval": sorted(overfit),
    }

    (out / "manifests").mkdir(parents=True)
    shutil.copy2(args.train_manifest, out / "manifests" / "vitonhd_train.jsonl")
    (out / "manifests" / "heldout_eval.jsonl").write_text("".join(json.dumps(r) + "\n" for r in heldout),
                                                          encoding="utf-8")
    (out / "plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    (out / "code").mkdir()
    for name in CODE_FILES:
        shutil.copy2(LORA / name, out / "code" / name)
    (out / "README.txt").write_text(
        "SmartFit LoRA full-run pack (code + manifests only; images come from your private VITON-HD dataset). "
        "VITON-HD is non-commercial: keep these datasets private.\n", encoding="utf-8")
    print(json.dumps(plan, indent=2))
    if args.zip:
        archive = shutil.make_archive(str(out), "zip", root_dir=out)
        print(f"zip: {archive} ({Path(archive).stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
