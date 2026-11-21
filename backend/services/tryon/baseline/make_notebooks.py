"""Generate the two Kaggle baseline notebooks (spec §8.1).

    python make_notebooks.py        -> notebooks/catvton_baseline.ipynb, notebooks/idmvton_baseline.ipynb

One notebook per model because their pinned diffusers/transformers versions
conflict. Each notebook builds its own isolated Python 3.11 env (uv) in /tmp,
so Kaggle's preinstalled packages are neither used nor changed, clones the
repo at a fixed commit and runs the runner from the data pack's code/ folder.
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

MODELS = {
    "catvton": {
        "title": "CatVTON",
        "repo": "https://github.com/Zheng-Chong/CatVTON.git",
        "commit": "999bdbe81e6008a3f5749af7c1e0b0fa3d21b48e",
        "checkout": "/tmp/CatVTON",
        "runner": "run_catvton.py",
        "extra_args": "",
        "weights": "about 4 GB (SD-1.5 inpainting UNet, VAE, CatVTON attention weights)",
        "time": "about 75 minutes (36 images x ~113 s on a T4, measured)",
        "accelerator": "GPU T4 x2 or GPU P100. Only one GPU is used.",
    },
    "idmvton": {
        "title": "IDM-VTON",
        "repo": "https://github.com/yisol/IDM-VTON.git",
        "commit": "0d5f3ec2d737487a9bb24e4100936ad254780383",
        "checkout": "/tmp/IDM-VTON",
        "runner": "run_idmvton.py",
        "extra_args": " --placement auto",
        "weights": "about 28 GB (two SDXL-size UNets, text and image encoders)",
        "time": "roughly 1-1.5 hours (about 10 min of downloads and conversion, then the 36 images)",
        "accelerator": "**GPU T4 x2** (needed: the weights are ~14 GB, so the garment UNet runs on the second T4; on a single GPU it falls back to much slower CPU offload).",
    },
}


def md(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": text.strip().splitlines(keepends=True)}


def code(text: str) -> dict:
    return {"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
            "source": text.strip().splitlines(keepends=True)}


def notebook(key: str, m: dict) -> dict:
    out = f"/kaggle/working/results/{key}"
    cells = [
        md(f"""
# SmartFit try-on baseline: {m['title']} (spec §8.1)

Runs the pretrained {m['title']} model, **no training**, on the SmartFit data pack, and records
time per image, peak GPU memory and paired SSIM/LPIPS. Run the other model's notebook too, then compare
both with `compare.py`.

**Before you click Run All** (right-hand panel → Session options):
1. **Accelerator:** {m['accelerator']}
2. **Internet:** On. It downloads the code, the Python packages and {m['weights']}.
3. **Input → Add Input:** your *private* SmartFit try-on pack dataset.
4. Optional: **Add-ons → Secrets:** `HF_TOKEN` (a Hugging Face *read* token). The models are public,
   so this only avoids anonymous rate limits.

Expected run time: {m['time']}.
"""),
        code("""
import glob, json, os

hits = sorted(glob.glob("/kaggle/input/**/manifest.json", recursive=True))
assert hits, "No manifest.json found: add the SmartFit try-on pack dataset as an input."
PACK = os.path.dirname(hits[0])
manifest = json.load(open(f"{PACK}/manifest.json"))
print("pack:", PACK, "|", len(manifest["jobs"]), "jobs")
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"
try:
    from kaggle_secrets import UserSecretsClient
    os.environ["HF_TOKEN"] = UserSecretsClient().get_secret("HF_TOKEN")
    print("HF_TOKEN loaded from Kaggle secrets")
except Exception:
    print("No HF_TOKEN secret: anonymous downloads (fine for these public models)")
!nvidia-smi --query-gpu=name,memory.total --format=csv
"""),
        md("## 1. Code at a fixed commit and an isolated environment"),
        md("Safe to re-run in the same session: the checkout, the env and downloaded weights in `/tmp` are reused."),
        code(f"""
![ -d {m['checkout']} ] || git clone -q {m['repo']} {m['checkout']}
!git -C {m['checkout']} checkout -q {m['commit']} && git -C {m['checkout']} log -1 --format="%H %cd"
!pip install -q uv==0.5.11
![ -x /tmp/env/bin/python ] || uv venv -q --python 3.11 /tmp/env
!uv pip install -q --python /tmp/env/bin/python torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu121
!uv pip install -q --python /tmp/env/bin/python -r {{PACK}}/code/requirements-{key}.txt
!/tmp/env/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
"""),
        md("## 2. Run every job in the pack\nOne line per job: `ok`, `oom` or `error`. A failed job does not stop the run."),
        code(f"""
!/tmp/env/bin/python {{PACK}}/code/{m['runner']} --pack {{PACK}} --repo {m['checkout']} --out {out}{m['extra_args']}
"""),
        md("## 3. Summary and a few results"),
        code(f"""
from IPython.display import Image as Show, display

r = json.load(open("{out}/results.json"))
print(json.dumps({{k: r[k] for k in ("settings", "summary", "metrics", "environment")}}, indent=2))
for row in [j for j in r["jobs"] if j["status"] == "ok"][:4]:
    print(row["id"], row.get("seconds"), "s", "ssim", row.get("ssim"), "lpips", row.get("lpips"))
    display(Show(filename="{out}/" + row["image"], width=288))
"""),
        md(f"""
## 4. Download

Zips the results. Download `results_{key}.zip` from the **Output** panel (or after *Save Version*), unzip it next
to your local pack folder and run `compare.py` (see `backend/services/tryon/baseline/README.md`).
"""),
        code(f"""
!cd /kaggle/working && rm -f results_{key}.zip && zip -qr results_{key}.zip results/{key} && ls -la /kaggle/working
"""),
    ]
    return {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }


def main() -> None:
    folder = HERE / "notebooks"
    folder.mkdir(exist_ok=True)
    for key, m in MODELS.items():
        path = folder / f"{key}_baseline.ipynb"
        path.write_text(json.dumps(notebook(key, m), indent=1) + "\n", encoding="utf-8")
        print("wrote", path)


if __name__ == "__main__":
    main()
