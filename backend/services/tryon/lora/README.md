# IDM-VTON LoRA fine-tuning (spec §8.4, §23.9)

The only training job in SmartFit. Everything in IDM-VTON stays frozen; a LoRA adapter is trained on the try-on UNet's attention, both self-attention (where the garment features are fused) and cross-attention.

The training step is IDM-VTON's own `train_xl.py`:
- **Inputs:** 13 input channels; garment-UNet reference features; IP-Adapter tokens.
- **Loss:** MSE on the noise.
- **Precision:** fp16 with loss scaling; the LoRA weights stay in fp32.
- **Batch:** 1 with gradient accumulation.
- **Placement:** the try-on UNet trains on GPU 0, and the frozen parts sit on GPU 1 (Kaggle **T4 x2**).

| File | Runs on | Purpose |
|---|---|---|
| `../preprocessing.py` + `backend/scripts/build_tryon_manifest.py` | local | VITON-HD → `TryOnSample` manifests (spec §5.6), `datasets/manifests/` |
| `lora_config.py` | Kaggle | hyperparameters (spec §8.4 starting point) and the exact target-module pattern |
| `data.py` | Kaggle | manifest → the tensors `train_xl.py` uses, with its augmentations |
| `idm.py` | Kaggle | weights (safetensors only), component loading, GPU placement, generation |
| `train_lora.py` | Kaggle | training with checkpoints every N steps, `--resume`, `--max-minutes`, `--overfit N` |
| `eval_lora.py` | Kaggle | same samples with the adapter off vs on; SSIM/LPIPS against the ground truth + sheet |
| `build_pack.py`, `make_notebooks.py` → `notebooks/` | local | Kaggle dataset pack and notebooks |

Tests:
- `backend/tests/test_tryon_preprocessing.py` runs in the normal backend venv.
- `backend/tests/test_tryon_lora_train.py` runs the real training code on tiny random copies of IDM-VTON's UNet classes on CPU. It needs the training env and `IDM_VTON_REPO`, and is skipped otherwise.

## Step 1: overfit test (do this first)

It answers two questions before any long run:
1. **Does LoRA training fit on Kaggle's GPUs?** This is the open risk in spec §23.8.
2. **Does the adapter learn?**

It trains 300 steps on 8 VITON-HD *test* samples and then compares base vs LoRA on those same samples.

**Why test samples:** IDM-VTON was trained on the train split, so those images are already memorised. The 8 ids are in the pack's `overfit_ids.txt` and must be left out of later held-out evaluation.

1. **Upload the pack.** On Kaggle, go to **Datasets → New Dataset** and upload `backend/data/lora-overfit-pack.zip` (2.3 MB). Make it **Private**.
2. **Import the notebook.** Go to **Code → Import Notebook** and choose `notebooks/lora_overfit.ipynb`.
3. **Set the session.** Accelerator **GPU T4 x2**, Internet **On**, add the pack as input, and optionally the `HF_TOKEN` secret.
4. **Run All.** It takes about 1 hour.
5. **Bring the results back.** Download `results_lora_overfit.zip` into `backend/` and tell me.

**Pass criteria:**
- **Training finishes** (no out-of-memory error), and peak memory per GPU is logged.
- **The loss trends down.** It is noisy, because each step draws a random noise level.
- **The adapter learns:** on these 8 training samples LoRA has lower LPIPS than the base for most samples, and visibly closer detail.

### Outcome (24 Oct 2026): passed
- **Fits:** training peaked at 7.3 GB on GPU 0 and 9.5 GB on GPU 1 (of 15 GB); 300 steps in 30.5 min, 4.65 s per step. Evaluation peaked at 13.2 GB on GPU 0.
- **Learns:** mean loss fell from 0.0475 (steps 1–50) to about 0.035 (last 100 steps); the loss scale never dropped.
- **Better than the base on all 8 samples:** LPIPS 0.0827 → 0.0684, SSIM 0.885 → 0.889. With the unmerged adapter, generation takes about 3.5 s longer (53.5 s vs 50 s).
- Results: `backend/data/lora-overfit-results/` (gitignored).

## Step 2: full run on VITON-HD

**Run length (decision 27 Oct 2026):** one pass over the 11,647 train pairs, updates of 16 pairs (728 updates), about 15 GPU hours, so two Kaggle sessions. IDM-VTON was already trained on this split, so the gain is expected to be modest; DressCode and the scraped pairs come next.

**Data order across sessions:** the order is a seeded shuffle per pass (`data.PassSampler`), and checkpoints store how many samples were drawn. A resumed session continues the same order, so the pass has no repeats or gaps.

| File | Purpose |
|---|---|
| `build_full_pack.py` → `backend/data/lora-full-pack.zip` | code, train manifest, 48 held-out test pairs (not the overfit 8), `plan.json` |
| `notebooks/lora_full.ipynb` | the same notebook for every session: resumes from the attached previous output, trains up to `session_train_minutes`, evaluates once training is complete |

**Each session:**
1. Accelerator **GPU T4 x2**, Internet **On**.
2. Inputs: the private *SmartFit LoRA full pack*, the private VITON-HD dataset, and from session 2 the previous version's output (**Add Input → Your Work**).
3. **Save Version → Save & Run All (Commit)**.

**Expected:** session 1 stops at about 510 of 728 updates. Session 2 finishes training (about 4.5 h) and then evaluates the 48 held-out pairs (about 90 min). Download `results_lora_full.zip` into `backend/`.

The adapter is saved separately and never merged into the base (spec §8.4). `LORA_WEIGHTS_ENABLED` stays `false` until the held-out evaluation is accepted.

### Outcome (1 Nov 2026): no measurable gain
- **The run itself:** all 728 updates completed over two sessions. The run resumed at step 555 with the data order continuing exactly (11,648 samples seen). Memory peaked at 7.3 / 9.5 GB, at 68.7 s per update.
- **Held-out 48 test pairs:** LPIPS 0.0952 → 0.0950, SSIM 0.862 → 0.861, LoRA better on 29/48 (sign test p = 0.19).
- **Why, and what's next:** IDM-VTON was already trained on VITON-HD, so the adapter is not used. Results: `backend/data/lora-full-results/` (gitignored).

## Step 3: DressCode (tops, bottoms, dresses)

| File | Purpose |
|---|---|
| `../dresscode.py` | inpaint masks (port of IDM-VTON's DressCode recipe) and DensePose rendering |
| `build_dresscode_pack.py` → `backend/data/lora-dresscode-pack.zip` | 2,800 pairs per category plus 16 held-out test pairs each; images, masks, DensePose, manifests and code in one private dataset |
| `notebooks/lora_dresscode.ipynb` | the same resumable flow; per-category evaluation |

**Optional, better captions and DensePose.** Download the IDM-VTON authors' DressCode `image-densepose` folders and `dc_caption.txt` files (link in the IDM-VTON README). Put each one in `datasets/DressCode/DressCode/<category>/`, then rebuild the pack. Without them, DensePose is rendered and captions are the category name.

**Each session:** GPU T4 x2, Internet on; input: the *SmartFit LoRA DressCode pack*, plus from session 2 the previous version's output. Then **Save & Run All (Commit)**. Download `results_lora_dresscode.zip` into `backend/`.
