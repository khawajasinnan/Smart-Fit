"""Generate the Kaggle LoRA notebooks (spec §8.4).

    python make_notebooks.py   -> notebooks/lora_overfit.ipynb, lora_full.ipynb, lora_dresscode.ipynb

The overfit test answers two questions before any long run: does IDM-VTON
LoRA training fit on Kaggle's T4 x2 (spec §23.8 open risk), and does the
adapter actually learn (it must reproduce its 8 training samples better than
the base model)?
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
IDM_REPO = "https://github.com/yisol/IDM-VTON.git"
IDM_COMMIT = "0d5f3ec2d737487a9bb24e4100936ad254780383"
OUT = "/kaggle/working/lora_overfit"


def md(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": text.strip().splitlines(keepends=True)}


def code(text: str) -> dict:
    return {"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
            "source": text.strip().splitlines(keepends=True)}


def overfit_notebook() -> dict:
    cells = [
        md("""
# SmartFit LoRA overfit test: IDM-VTON (spec §8.4)

Trains a LoRA adapter on **8 samples** for 300 steps, then generates those 8 samples with the adapter off
(the pretrained IDM-VTON) and on. It answers two questions before any long training run:

1. **Does LoRA training fit** on Kaggle's GPUs? (Peak memory per GPU is logged.)
2. **Does the adapter learn?** On its own 8 training samples the LoRA output must be clearly closer to the
   ground truth (lower LPIPS) than the base model's.

**Before you click Run All** (right-hand panel → Session options):
1. **Accelerator:** **GPU T4 x2** (needed: the try-on UNet trains on one T4, the frozen parts sit on the other).
2. **Internet:** On (code, packages, ~28 GB of model weights on first run).
3. **Input → Add Input:** your private *SmartFit LoRA overfit pack* dataset.
4. Optional **Add-ons → Secrets:** `HF_TOKEN` (Hugging Face read token).

Expected run time: about 1 hour (≈10 min downloads and conversion, ≈20–30 min training, ≈15 min evaluation).
Safe to re-run in the same session: the checkout, the env and the weights in `/tmp` are reused.
"""),
        code("""
import glob, json, os

hits = sorted(glob.glob("/kaggle/input/**/code/train_lora.py", recursive=True))
assert hits, "LoRA pack not found: add the SmartFit LoRA overfit pack dataset as an input."
PACK = os.path.dirname(os.path.dirname(hits[0]))
DATA, MANIFEST = f"{PACK}/data", f"{PACK}/manifests/overfit.jsonl"
print("pack:", PACK)
print(open(f"{PACK}/overfit_ids.txt").read())
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"
try:
    from kaggle_secrets import UserSecretsClient
    os.environ["HF_TOKEN"] = UserSecretsClient().get_secret("HF_TOKEN")
    print("HF_TOKEN loaded from Kaggle secrets")
except Exception:
    print("No HF_TOKEN secret: anonymous downloads (fine for this public model)")
!nvidia-smi --query-gpu=name,memory.total --format=csv
"""),
        md("## 1. Code at a fixed commit and an isolated environment"),
        code(f"""
![ -d /tmp/IDM-VTON ] || git clone -q {IDM_REPO} /tmp/IDM-VTON
!git -C /tmp/IDM-VTON checkout -q {IDM_COMMIT} && git -C /tmp/IDM-VTON log -1 --format="%H %cd"
!pip install -q uv==0.5.11
![ -x /tmp/env/bin/python ] || uv venv -q --python 3.11 /tmp/env
!uv pip install -q --python /tmp/env/bin/python torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu121
!uv pip install -q --python /tmp/env/bin/python -r {{PACK}}/code/requirements-lora.txt
!/tmp/env/bin/python -c "import torch, peft; print(torch.__version__, 'peft', peft.__version__, [torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())])"
"""),
        md("## 2. Train: 300 steps on the 8 samples\nA line every 5 steps with the loss and the peak memory per GPU."),
        code(f"""
!/tmp/env/bin/python {{PACK}}/code/train_lora.py --repo /tmp/IDM-VTON --manifest {{MANIFEST}} --data-root {{DATA}} --out {OUT} --overfit 8
"""),
        code(f"""
import matplotlib.pyplot as plt

rows = [json.loads(l) for l in open("{OUT}/metrics.jsonl")]
run = json.load(open("{OUT}/run.json"))
print(json.dumps({{k: run.get(k) for k in ("status", "final_step", "minutes", "peak_reserved_gb_by_gpu",
                                          "trainable_parameters")}}, indent=2))
print("seconds per step (median):", sorted(r["sec_per_step"] for r in rows)[len(rows) // 2])
plt.figure(figsize=(7, 3))
plt.plot([r["step"] for r in rows], [r["loss"] for r in rows])
plt.xlabel("step"); plt.ylabel("loss (mean of 5 steps)"); plt.title("LoRA overfit loss"); plt.grid(alpha=.3)
plt.show()
"""),
        md("## 3. Base vs LoRA on the same 8 samples\nSame seed and inputs; only the adapter is switched off/on."),
        code(f"""
!/tmp/env/bin/python {{PACK}}/code/eval_lora.py --repo /tmp/IDM-VTON --manifest {{MANIFEST}} --data-root {{DATA}} --adapter {OUT}/adapter --out {OUT}/eval
"""),
        code(f"""
from IPython.display import Image as Show, display

ev = json.load(open("{OUT}/eval/results.json"))
print(json.dumps(ev["summary"], indent=2))
display(Show(filename="{OUT}/eval/sheet.jpg", width=900))
"""),
        md("## 4. Download\nDownload `results_lora_overfit.zip` from the **Output** panel and add it to the repo's `backend/` folder "
           "as before. It includes the adapter, metrics, run summary and the evaluation images (checkpoints are left out)."),
        code("""
!cd /kaggle/working && rm -f results_lora_overfit.zip && zip -qr results_lora_overfit.zip lora_overfit -x "lora_overfit/checkpoints/*" && ls -la /kaggle/working
"""),
    ]
    return {
        "cells": cells,
        "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                     "language_info": {"name": "python"}},
        "nbformat": 4,
        "nbformat_minor": 4,
    }


FULL_OUT = "/kaggle/working/lora_full"


def full_notebook() -> dict:
    cells = [
        md("""
# SmartFit LoRA full run: IDM-VTON on VITON-HD (spec §8.4, §23.9)

One pass over the 11,647 VITON-HD train pairs (updates of 16), about **15 GPU hours**: more than one Kaggle
session (12 h max). The same notebook runs every session: it continues from the newest checkpoint of the
previous session and, once training is complete, evaluates base vs LoRA on 48 held-out test pairs.

**Every session** (right-hand panel):
1. **Accelerator:** **GPU T4 x2**. **Internet:** On.
2. **Input → Add Input:** your private *SmartFit LoRA full pack* and your private *VITON-HD* dataset.
3. **Session 2 onwards, also:** Input → Add Input → **Your Work** → this notebook → its latest version's
   output (that is where the checkpoints are).
4. **Save Version → Save & Run All (Commit)**, so it keeps running with the browser closed.

Each session stops training at about 10 h 40 min, saves a checkpoint and zips the progress; nothing is lost.
"""),
        code("""
import glob, json, os, shutil, time

SESSION_START = time.time()
hits = [h for h in sorted(glob.glob("/kaggle/input/**/plan.json", recursive=True))
        if os.path.exists(os.path.join(os.path.dirname(h), "code", "train_lora.py"))]
assert hits, "Full-run pack not found: add the SmartFit LoRA full pack dataset as an input."
PACK = os.path.dirname(hits[0])
PLAN = json.load(open(f"{PACK}/plan.json"))
print("pack:", PACK)
print(json.dumps(PLAN, indent=2))

# VITON-HD root: the folder with train_pairs.txt whose train/image holds the full set
# (the 8-sample overfit pack also has a train_pairs.txt; it is ignored here).
def n_train_images(root):
    folder = os.path.join(root, "train", "image")
    return len(os.listdir(folder)) if os.path.isdir(folder) else 0

roots = sorted({os.path.dirname(p) for p in glob.glob("/kaggle/input/**/train_pairs.txt", recursive=True)},
               key=n_train_images, reverse=True)
assert roots and n_train_images(roots[0]) >= PLAN["train_samples"], (
    f"VITON-HD not found: add your private VITON-HD dataset (need {PLAN['train_samples']} train images; "
    f"found {[(r, n_train_images(r)) for r in roots]})")
VITON = roots[0]
records = [json.loads(l) for l in open(f"{PACK}/manifests/vitonhd_train.jsonl")]
fields = ("person_image_path", "cloth_image_path", "agnostic_mask_path", "densepose_path")
missing = [r[f] for r in records[:: max(1, len(records) // 300)] for f in fields
           if not os.path.exists(os.path.join(VITON, r[f]))]
assert not missing, f"VITON-HD files missing under {VITON}, e.g. {missing[:3]}"
print(f"VITON-HD: {VITON} ({n_train_images(VITON)} train images; manifest spot-check OK)")

# Continue from the previous session's output, if attached.
OUT = "%(out)s"
os.makedirs(f"{OUT}/checkpoints", exist_ok=True)
step_of = lambda state: int(os.path.basename(os.path.dirname(state)).split("-")[1])
mine = glob.glob(f"{OUT}/checkpoints/step-*/state.pt")
prev = glob.glob("/kaggle/input/**/lora_full/checkpoints/step-*/state.pt", recursive=True)
if prev and (not mine or step_of(max(prev, key=step_of)) > step_of(max(mine, key=step_of))):
    newest = max(prev, key=step_of)
    src = os.path.dirname(newest)
    shutil.copytree(src, f"{OUT}/checkpoints/{os.path.basename(src)}", dirs_exist_ok=True)
    prev_out = os.path.dirname(os.path.dirname(src))
    if os.path.exists(f"{prev_out}/metrics.jsonl"):
        shutil.copy(f"{prev_out}/metrics.jsonl", f"{OUT}/metrics.jsonl")
    print(f"Continuing from step {step_of(newest)} of {PLAN['max_steps']} ({src})")
elif mine:
    print(f"Continuing from step {step_of(max(mine, key=step_of))} (this session's own checkpoint)")
else:
    print(f"Starting a new run: {PLAN['max_steps']} updates")

os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"
try:
    from kaggle_secrets import UserSecretsClient
    os.environ["HF_TOKEN"] = UserSecretsClient().get_secret("HF_TOKEN")
except Exception:
    pass
!nvidia-smi --query-gpu=name,memory.total --format=csv
""" % {"out": FULL_OUT}),
        md("## 1. Code at a fixed commit and an isolated environment"),
        code(f"""
![ -d /tmp/IDM-VTON ] || git clone -q {IDM_REPO} /tmp/IDM-VTON
!git -C /tmp/IDM-VTON checkout -q {IDM_COMMIT} && git -C /tmp/IDM-VTON log -1 --format="%H %cd"
!pip install -q uv==0.5.11
![ -x /tmp/env/bin/python ] || uv venv -q --python 3.11 /tmp/env
!uv pip install -q --python /tmp/env/bin/python torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu121
!uv pip install -q --python /tmp/env/bin/python -r {{PACK}}/code/requirements-lora.txt
!/tmp/env/bin/python -c "import torch, peft; print(torch.__version__, 'peft', peft.__version__, [torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())])"
"""),
        md("## 2. Train (continues automatically; stops at the session's time budget with a checkpoint)\n"
           "A line every 5 updates: loss, samples seen, seconds per update, peak memory per GPU."),
        code("""
TRAIN_ARGS = " ".join([
    f"--repo /tmp/IDM-VTON --manifest {PACK}/manifests/vitonhd_train.jsonl --data-root {VITON} --out {OUT}",
    "--resume auto", f"--max-minutes {PLAN['session_train_minutes']}",
    f"--max-steps {PLAN['max_steps']} --grad-accum {PLAN['grad_accum']} --warmup-steps {PLAN['warmup_steps']}",
    f"--save-every {PLAN['save_every']} --log-every {PLAN['log_every']} --augment {PLAN['augment']} --num-workers 2",
])
!/tmp/env/bin/python {PACK}/code/train_lora.py {TRAIN_ARGS}
"""),
        code("""
import matplotlib.pyplot as plt

run = json.load(open(f"{OUT}/run.json"))
rows = [json.loads(l) for l in open(f"{OUT}/metrics.jsonl")]
FINISHED = run.get("status") == "completed"
print(json.dumps({k: run.get(k) for k in ("status", "final_step", "minutes", "peak_reserved_gb_by_gpu")}, indent=2))
print(f"progress: {run.get('final_step')} / {PLAN['max_steps']} updates")
if rows:
    print("seconds per update (median, this session):", sorted(r["sec_per_step"] for r in rows)[len(rows) // 2])
    plt.figure(figsize=(8, 3))
    plt.plot([r["step"] for r in rows], [r["loss"] for r in rows])
    plt.xlabel("update"); plt.ylabel("loss (mean of 5 updates)"); plt.title("LoRA full run"); plt.grid(alpha=.3)
    plt.show()
if not FINISHED:
    print("Not finished yet: run another session with this version's output attached as input.")
"""),
        md("## 3. Held-out evaluation (only when training is complete)\n"
           "48 VITON-HD test pairs (never trained on), base vs LoRA with the same seed and inputs. About 90 min."),
        code("""
hours_left = 12 - (time.time() - SESSION_START) / 3600
if not FINISHED:
    print("Skipped: training is not complete yet.")
elif hours_left < 1.75:
    print(f"Skipped: only {hours_left:.1f} h left in this session. Run once more with this output attached; "
          "training is done, so the next session goes straight to evaluation.")
else:
    !/tmp/env/bin/python {PACK}/code/eval_lora.py --repo /tmp/IDM-VTON --manifest {PACK}/manifests/heldout_eval.jsonl --data-root {VITON} --adapter {OUT}/adapter --out {OUT}/eval
"""),
        code("""
from IPython.display import Image as Show, display

if os.path.exists(f"{OUT}/eval/results.json"):
    ev = json.load(open(f"{OUT}/eval/results.json"))
    print(json.dumps(ev["summary"], indent=2))
    display(Show(filename=f"{OUT}/eval/sheet.jpg", width=900))
"""),
        md("## 4. Download\n`results_lora_full.zip` (adapter, metrics, run summary, evaluation; no checkpoints). "
           "The checkpoints stay in this version's output for the next session. When the run is finished and "
           "evaluated, download the zip into the repo's `backend/` folder."),
        code("""
!cd /kaggle/working && rm -f results_lora_full.zip && zip -qr results_lora_full.zip lora_full -x "lora_full/checkpoints/*" && ls -la /kaggle/working /kaggle/working/lora_full
"""),
    ]
    return {
        "cells": cells,
        "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                     "language_info": {"name": "python"}},
        "nbformat": 4,
        "nbformat_minor": 4,
    }


DC_OUT = "/kaggle/working/lora_dresscode"


def dresscode_notebook() -> dict:
    cells = [
        md("""
# SmartFit LoRA on DressCode: IDM-VTON (spec §8.4, §23.13)

A seeded DressCode subset, 2,800 pairs each of **tops**, **bottoms** (trousers, skirts) and **dresses**: garment
types IDM-VTON wasn't trained on (its VITON-HD training is tops only; our VITON-HD run gave no held-out gain).
One pass, updates of 16 (525 updates, about 10 h). The same notebook runs every session: it continues from
the previous session's newest checkpoint and, once training is complete, compares base vs LoRA on 48
held-out DressCode test pairs (16 per category).

**Every session** (right-hand panel):
1. **Accelerator:** **GPU T4 x2**. **Internet:** On.
2. **Input → Add Input:** your private *SmartFit LoRA DressCode pack* (code, manifests and images in one).
3. **Session 2 onwards, also:** Input → Add Input → **Your Work** → this notebook → its latest version's output.
4. **Save Version → Save & Run All (Commit)**.

Expected: session 1 trains (~10 h, stops with a checkpoint if the time budget is reached); the evaluation
(~1.5 h) runs in the session after training completes.
"""),
        code("""
import glob, json, os, shutil, time

SESSION_START = time.time()
hits = [h for h in sorted(glob.glob("/kaggle/input/**/data/dresscode_pack.json", recursive=True))]
assert hits, "DressCode pack not found: add the SmartFit LoRA DressCode pack dataset as an input."
DATA = os.path.dirname(hits[0])
PACK = os.path.dirname(DATA)
PLAN = json.load(open(f"{PACK}/plan.json"))
print("pack:", PACK)
print(json.dumps(PLAN, indent=2))
records = [json.loads(l) for l in open(f"{PACK}/manifests/dresscode_train.jsonl")]
fields = ("person_image_path", "cloth_image_path", "agnostic_mask_path", "densepose_path")
missing = [r[f] for r in records for f in fields if not os.path.exists(os.path.join(DATA, r[f]))]
assert not missing, f"{len(missing)} files missing from the pack, e.g. {missing[:3]}"
print(f"all {len(records)} training samples present")

OUT = "%(out)s"
os.makedirs(f"{OUT}/checkpoints", exist_ok=True)
step_of = lambda state: int(os.path.basename(os.path.dirname(state)).split("-")[1])
mine = glob.glob(f"{OUT}/checkpoints/step-*/state.pt")
prev = glob.glob("/kaggle/input/**/lora_dresscode/checkpoints/step-*/state.pt", recursive=True)
if prev and (not mine or step_of(max(prev, key=step_of)) > step_of(max(mine, key=step_of))):
    newest = max(prev, key=step_of)
    src = os.path.dirname(newest)
    shutil.copytree(src, f"{OUT}/checkpoints/{os.path.basename(src)}", dirs_exist_ok=True)
    prev_out = os.path.dirname(os.path.dirname(src))
    for name in ("metrics.jsonl", "run.json"):
        if os.path.exists(f"{prev_out}/{name}"):
            shutil.copy(f"{prev_out}/{name}", f"{OUT}/{name}")
    if os.path.isdir(f"{prev_out}/adapter"):
        shutil.copytree(f"{prev_out}/adapter", f"{OUT}/adapter", dirs_exist_ok=True)
    print(f"Continuing from step {step_of(newest)} of {PLAN['max_steps']} ({src})")
elif mine:
    print(f"Continuing from step {step_of(max(mine, key=step_of))} (this session's own checkpoint)")
else:
    print(f"Starting a new run: {PLAN['max_steps']} updates")

os.environ["PYTORCH_CUDA_ALLOC_CONF"] = "expandable_segments:True"
try:
    from kaggle_secrets import UserSecretsClient
    os.environ["HF_TOKEN"] = UserSecretsClient().get_secret("HF_TOKEN")
except Exception:
    pass
!nvidia-smi --query-gpu=name,memory.total --format=csv
""" % {"out": DC_OUT}),
        md("## 1. Code at a fixed commit and an isolated environment"),
        code(f"""
![ -d /tmp/IDM-VTON ] || git clone -q {IDM_REPO} /tmp/IDM-VTON
!git -C /tmp/IDM-VTON checkout -q {IDM_COMMIT} && git -C /tmp/IDM-VTON log -1 --format="%H %cd"
!pip install -q uv==0.5.11
![ -x /tmp/env/bin/python ] || uv venv -q --python 3.11 /tmp/env
!uv pip install -q --python /tmp/env/bin/python torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu121
!uv pip install -q --python /tmp/env/bin/python -r {{PACK}}/code/requirements-lora.txt
!/tmp/env/bin/python -c "import torch, peft; print(torch.__version__, 'peft', peft.__version__, [torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())])"
"""),
        md("## 2. Train (continues automatically; stops at the session's time budget with a checkpoint)"),
        code("""
done_before = os.path.exists(f"{OUT}/run.json") and json.load(open(f"{OUT}/run.json")).get("status") == "completed"
if done_before and os.path.isdir(f"{OUT}/adapter"):
    print("Training already completed in an earlier session: going straight to evaluation.")
else:
    TRAIN_ARGS = " ".join([
        f"--repo /tmp/IDM-VTON --manifest {PACK}/manifests/dresscode_train.jsonl --data-root {DATA} --out {OUT}",
        "--resume auto", f"--max-minutes {PLAN['session_train_minutes']}",
        f"--max-steps {PLAN['max_steps']} --grad-accum {PLAN['grad_accum']} --warmup-steps {PLAN['warmup_steps']}",
        f"--save-every {PLAN['save_every']} --log-every {PLAN['log_every']} --augment {PLAN['augment']} --num-workers 2",
    ])
    !/tmp/env/bin/python {PACK}/code/train_lora.py {TRAIN_ARGS}
"""),
        code("""
import matplotlib.pyplot as plt

run = json.load(open(f"{OUT}/run.json"))
rows = [json.loads(l) for l in open(f"{OUT}/metrics.jsonl")] if os.path.exists(f"{OUT}/metrics.jsonl") else []
FINISHED = run.get("status") == "completed"
print(json.dumps({k: run.get(k) for k in ("status", "final_step", "minutes", "peak_reserved_gb_by_gpu")}, indent=2))
print(f"progress: {run.get('final_step')} / {PLAN['max_steps']} updates")
if rows:
    plt.figure(figsize=(8, 3))
    plt.plot([r["step"] for r in rows], [r["loss"] for r in rows])
    plt.xlabel("update"); plt.ylabel("loss (mean of 5 updates)"); plt.title("LoRA on DressCode"); plt.grid(alpha=.3)
    plt.show()
if not FINISHED:
    print("Not finished yet: run another session with this version's output attached as input.")
"""),
        md("## 3. Held-out evaluation (only when training is complete)\n"
           "48 DressCode test pairs (16 tops, 16 bottoms, 16 dresses), base vs LoRA, same seed and inputs."),
        code("""
hours_left = 12 - (time.time() - SESSION_START) / 3600
if not FINISHED:
    print("Skipped: training is not complete yet.")
elif hours_left < 1.75:
    print(f"Skipped: only {hours_left:.1f} h left. Run once more with this output attached: training is done, "
          "so the next session goes straight to evaluation.")
else:
    !/tmp/env/bin/python {PACK}/code/eval_lora.py --repo /tmp/IDM-VTON --manifest {PACK}/manifests/heldout_eval.jsonl --data-root {DATA} --adapter {OUT}/adapter --out {OUT}/eval
"""),
        code("""
import statistics
from IPython.display import Image as Show, display

if os.path.exists(f"{OUT}/eval/results.json"):
    ev = json.load(open(f"{OUT}/eval/results.json"))
    print(json.dumps(ev["summary"], indent=2))
    for cat in ("upper_body", "lower_body", "dresses"):
        rows = [r for r in ev["samples"] if r["sample_id"].split(":")[1] == cat]
        if rows:
            base = statistics.mean(r["base_lpips"] for r in rows); lora = statistics.mean(r["lora_lpips"] for r in rows)
            better = sum(r["lora_lpips"] < r["base_lpips"] for r in rows)
            print(f"{cat:11s} LPIPS base {base:.4f} -> LoRA {lora:.4f}  (LoRA better on {better}/{len(rows)})")
    display(Show(filename=f"{OUT}/eval/sheet.jpg", width=900))
"""),
        md("## 4. Download\n`results_lora_dresscode.zip` (adapter, metrics, run summary, evaluation; no checkpoints). "
           "When the run is finished and evaluated, download it into the repo's `backend/` folder."),
        code("""
!cd /kaggle/working && rm -f results_lora_dresscode.zip && zip -qr results_lora_dresscode.zip lora_dresscode -x "lora_dresscode/checkpoints/*" && ls -la /kaggle/working /kaggle/working/lora_dresscode
"""),
    ]
    return {
        "cells": cells,
        "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                     "language_info": {"name": "python"}},
        "nbformat": 4,
        "nbformat_minor": 4,
    }


def main() -> None:
    folder = HERE / "notebooks"
    folder.mkdir(exist_ok=True)
    for name, notebook in (("lora_overfit.ipynb", overfit_notebook()), ("lora_full.ipynb", full_notebook()),
                           ("lora_dresscode.ipynb", dresscode_notebook())):
        path = folder / name
        path.write_text(json.dumps(notebook, indent=1) + "\n", encoding="utf-8")
        print("wrote", path)


if __name__ == "__main__":
    main()
