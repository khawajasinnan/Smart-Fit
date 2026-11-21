"""Build the Kaggle pack for the LoRA overfit test (spec §8.4).

    python services/tryon/lora/build_pack.py OUT_DIR [--samples 8] [--zip]

Runs locally (backend/.venv-cpu). Copies N VITON-HD **test** samples (all
their files, same relative paths), a manifest for them and the LoRA code
into OUT_DIR, for upload as one private Kaggle dataset.

Why test samples: IDM-VTON was trained on the VITON-HD train split, so it
has effectively memorised those images already and an overfit test on them
would show little. The chosen ids exclude the baseline comparison's persons
and are written to overfit_ids.txt so held-out evaluation can exclude them.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import sys
from pathlib import Path

LORA = Path(__file__).resolve().parent
BACKEND = LORA.parents[2]
REPO = BACKEND.parent
CODE_FILES = ("data.py", "idm.py", "lora_config.py", "train_lora.py", "eval_lora.py", "requirements-lora.txt")
PATH_FIELDS = ("person_image_path", "cloth_image_path", "agnostic_mask_path", "agnostic_person_path", "densepose_path")


def baseline_persons(pack: Path) -> set[str]:
    manifest = pack / "manifest.json"
    if not manifest.exists():
        return set()
    jobs = json.loads(manifest.read_text(encoding="utf-8"))["jobs"]
    return {Path(j["person"]).stem for j in jobs}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--viton", default=str(REPO / "datasets" / "viton-hd"))
    ap.add_argument("--manifest", default=str(REPO / "datasets" / "manifests" / "vitonhd_test.jsonl"))
    ap.add_argument("--baseline-pack", default=str(BACKEND / "data" / "tryon-baseline-pack"))
    ap.add_argument("--samples", type=int, default=8)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--zip", action="store_true")
    args = ap.parse_args()

    out, root = Path(args.out), Path(args.viton)
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty; choose a new folder.")
    records = [json.loads(line) for line in Path(args.manifest).read_text(encoding="utf-8").splitlines() if line]
    taken = baseline_persons(Path(args.baseline_pack))
    pool = [r for r in records if r["sample_id"].rsplit(":", 1)[1] not in taken]
    chosen = sorted(random.Random(args.seed).sample(pool, args.samples), key=lambda r: r["sample_id"])

    for r in chosen:
        for field in PATH_FIELDS:
            dest = out / "data" / r[field]
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / r[field], dest)
    # a pairs file marks the data root (train_lora.py's auto-detection looks for it)
    names = [Path(r["person_image_path"]).name for r in chosen]
    (out / "data" / "train_pairs.txt").write_text("".join(f"{n} {n}\n" for n in names), encoding="utf-8")
    (out / "manifests").mkdir()
    (out / "manifests" / "overfit.jsonl").write_text("".join(json.dumps(r) + "\n" for r in chosen), encoding="utf-8")
    (out / "overfit_ids.txt").write_text("".join(r["sample_id"] + "\n" for r in chosen), encoding="utf-8")
    (out / "code").mkdir()
    for name in CODE_FILES:
        shutil.copy2(LORA / name, out / "code" / name)
    (out / "README.txt").write_text(
        "SmartFit LoRA overfit pack. Private research data: VITON-HD is non-commercial; do not make this "
        "dataset public.\n", encoding="utf-8")
    print(f"{len(chosen)} samples (excluding {len(taken)} baseline persons): "
          + ", ".join(r["sample_id"] for r in chosen))
    if args.zip:
        archive = shutil.make_archive(str(out), "zip", root_dir=out)
        print(f"zip: {archive} ({Path(archive).stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
