# Try-on baseline: CatVTON vs IDM-VTON (spec §8.1)

> **Outcome (24 Oct 2026): IDM-VTON was chosen.** See `docs/evaluation/tryon_model_selection.md` and spec §23.8. This folder is now the archived, reproducible evaluation. The CatVTON runner stays here only so the comparison can be rerun; it is not an integration path.

Both pretrained models run on the **same** jobs on a Kaggle GPU with **no training**. The comparison
covers (a) visual quality, especially on Pakistani-style garments, (b) seconds per image and (c) peak
VRAM. The winner goes in `.env` as `TRYON_MODEL_NAME`. The other model's code is then archived, and
step 5 (LoRA) uses only the winner.

Licences: both models are CC BY-NC-SA 4.0 (non-commercial; fine for the FYP, never imply commercial
use). VITON-HD and the Roboflow export are non-commercial too, and retailer photos belong to the
retailer, so **the Kaggle dataset must stay private**.

| File | Runs on | Purpose |
|---|---|---|
| `build_pack.py` | local (`backend/.venv-cpu`) | builds the data pack: images + `manifest.json` + `code/` |
| `run_catvton.py`, `run_idmvton.py` | Kaggle GPU | one model over every job → `results/<model>/` |
| `common.py` | Kaggle | pack lookup, timing, peak VRAM, SSIM/LPIPS, `results.json` |
| `compare.py` | local | side-by-side sheets + comparison table |
| `requirements-*.txt` | Kaggle | exact package pins per model (they conflict, so each model gets its own env) |
| `make_notebooks.py` → `notebooks/*.ipynb` | — | the two Kaggle notebooks |

## What is in the pack (36 jobs per model)

| Group | Jobs | What it tests |
|---|---|---|
| `vitonhd_paired` | 10 | seeded VITON-HD **test** persons in their own garment; ground truth gives SSIM/LPIPS |
| `vitonhd_unpaired` | 10 | the same persons with the official `test_pairs.txt` garment (the real use case) |
| `outfitters` | 16 | 4 real Outfitters flat-lays × 4 persons (catalog → try-on path) |
| `roboflow` | optional | Pakistani garments you pick by hand (kameez / shirt), test only (spec §23.4) |

Persons, masks and DensePose all come from VITON-HD (spec §23.5), so the only difference between the
two models is the model itself. Captions for IDM-VTON's text prompts come from its own
`vitonhd_test_tagged.json` (pinned commit) for VITON garments and from the product name for the others.

## Step by step

### 1. Build the pack (done; rerun only to change it)

```
cd backend
CATALOG_STORE=snapshot .venv-cpu/Scripts/python services/tryon/baseline/build_pack.py data/tryon-baseline-pack --zip
```

The output is `backend/data/tryon-baseline-pack/` and `backend/data/tryon-baseline-pack.zip` (gitignored). The output folder must be new or empty.

**Optional, recommended for criterion (a): add Pakistani garments.**

1. Export crops:
   ```
   .venv-cpu/Scripts/python services/tryon/baseline/build_pack.py x --roboflow-candidates ../datasets/pakistani-roboflow/candidates
   ```
   This writes 366 crops (339 kameez, 27 shirt).
2. Copy 6–8 clean, front-facing, uncluttered ones into a new folder, e.g. `datasets/pakistani-roboflow/picks/`. Keep the file names: the part before `__` is the caption.
3. Rebuild into a new folder with `--roboflow-picks ../datasets/pakistani-roboflow/picks --zip`.

### 2. Upload the pack to Kaggle (once)

1. kaggle.com → **Datasets → New Dataset**.
2. Drag in `tryon-baseline-pack.zip`.
3. Title: `smartfit-tryon-pack`. Visibility: **Private**.
4. Click **Create**.

Kaggle unzips it. The notebooks find `manifest.json` wherever it lands under `/kaggle/input`.

### 3. Run each notebook (once per model)

1. kaggle.com → **Code → New Notebook → File → Import Notebook**, and upload `notebooks/catvton_baseline.ipynb`.
2. In the right panel, set:
   - **Accelerator:** GPU T4 x2 (required for IDM-VTON; CatVTON also runs on a P100);
   - **Internet:** On;
   - **Add Input:** your `smartfit-tryon-pack`;
   - optional secret `HF_TOKEN` (Hugging Face read token).
3. Click **Run All**:
   - CatVTON downloads about 4 GB of weights and takes about 75 min (measured: ~113 s per image on a T4);
   - IDM-VTON downloads about 28 GB, converts its UNet once (about 10 min together), then generates; expect roughly 1–1.5 h.
4. When it finishes, download `results_catvton.zip` from the Output panel.
5. Repeat for `notebooks/idmvton_baseline.ipynb` → `results_idmvton.zip`.

Use one notebook per model and keep the pinned versions: CatVTON needs diffusers 0.29.2, IDM-VTON needs 0.25.0. Each notebook builds its own Python 3.11 env in `/tmp`, so Kaggle's preinstalled packages are not used.

### 4. Compare (local)

Unzip both results into one folder, e.g. `backend/data/tryon-baseline-results/`, then:

```
.venv-cpu/Scripts/python services/tryon/baseline/compare.py --pack data/tryon-baseline-pack \
    --results data/tryon-baseline-results/results/catvton data/tryon-baseline-results/results/idmvton \
    --out data/tryon-baseline-results/comparison
```

This writes `comparison.md` (table) and `sheet_<group>.jpg` (person | garment | CatVTON | IDM-VTON | ground truth). Send me both, and we decide together.

## Reading the results

- **Visual quality decides first**, especially on the `outfitters` and `roboflow` sheets. Check:
  - prints and logos stay readable;
  - stripes stay straight;
  - sleeves have the right length;
  - arms, hands and face are untouched;
  - nothing from the old garment shows through.
- SSIM ↑ / LPIPS ↓ use only 10 paired samples: indicative, not a benchmark. The full test-set evaluation is step 5 (§8.5).
- Time per image is the median after the first (warm-up) job. Peak VRAM is `torch.cuda.max_memory_reserved`. `load_seconds` includes first-time weight downloads, so don't compare it between models.
- IDM-VTON's weights alone take ~14 GB of VRAM in fp16 (measured: they load onto one T4 but every image then runs out of memory). `--placement auto` therefore puts the garment UNet on the second T4 (`two_gpu`); with one GPU it uses `one_gpu`, and any job that still runs out of memory switches the run to model CPU offload and is retried. Each job records its placement, and peak VRAM is summed over both GPUs (`peak_reserved_gb_by_gpu` has the split). The write-up must state this: in production IDM-VTON needs ~14 GB+ of VRAM (or two GPUs), CatVTON ~4.3 GB.
- fp16 everywhere: T4/P100 have no bf16 (spec §23.3). CatVTON's "<8 GB at 1024×768" claim is for bf16; our numbers are fp16 and are the ones that count.

## Known deviations from the repos' defaults

- CatVTON's default base `runwayml/stable-diffusion-inpainting` was deleted from Hugging Face. The identical weights are at `stable-diffusion-v1-5/stable-diffusion-inpainting`.
- IDM-VTON's demo builds DensePose and the mask from the photo. Here both come from VITON-HD (the same inputs its own `inference.py` uses for VITON-HD).
- **No pickle weights are loaded as code.**
  - CatVTON: the inpainting base's full-precision UNet exists only as a pickle `.bin`, so the runner fetches its `fp16.safetensors` (the same weights in the precision we run). It also fetches only the one attention checkpoint used, not the whole CatVTON repo.
  - IDM-VTON: the try-on UNet is published only as a 12 GB `.bin`. It is read once with `torch.load(weights_only=True)` (tensor data only; Hugging Face's pickle scan of that file lists only `FloatStorage`, `_rebuild_tensor_v2`, `OrderedDict`), saved as fp16 safetensors in `/tmp/smartfit-weights`, and the `.bin` is deleted. Peak disk use is about 12 + 6 + 16 GB, so IDM-VTON's `load_seconds` includes this one-off download and conversion.
- `torch` is 2.5.1 (cu121) for both, not the repos' 2.1.2 / 2.0.1, so one wheel set works on Kaggle's current drivers. `huggingface_hub` is pinned below 0.26 because both diffusers versions import `cached_download`.
