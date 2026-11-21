"""CatVTON baseline runner (spec §8.1). Runs on Kaggle (or any CUDA box).

    python run_catvton.py --repo /kaggle/working/CatVTON --out /kaggle/working/results/catvton

Mirrors the repo's own inference (model/pipeline.py CatVTONPipeline, PIL
inputs, mask white = area to repaint). Defaults follow the repo: 50 steps,
guidance 2.5, 1024x768, "mix" attention checkpoint (trained at 1024).
fp16 (spec §23.3): T4/P100 have no bf16.

Base model: RunwayML deleted runwayml/stable-diffusion-inpainting (the
repo's default); the same weights are published at
stable-diffusion-v1-5/stable-diffusion-inpainting.

Weights are fetched file by file into --weights-dir and only safetensors are
loaded: that repo's full-precision UNet exists only as a pickle .bin, but
its fp16 .safetensors holds the same weights in the precision we run. Only
the one attention checkpoint used is fetched, not the whole CatVTON repo
(DensePose, SCHP, FLUX LoRA).
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import (  # noqa: E402
    JobTimer,
    environment,
    find_pack,
    load_manifest,
    paired_metrics,
    summarise,
    write_results,
)

ATTN_FOLDERS = {"mix": "mix-48k-1024", "vitonhd": "vitonhd-16k-512", "dresscode": "dresscode-16k-512"}


def local_base(repo_id: str, root: Path) -> Path:
    """Scheduler + UNet of the inpainting base (all CatVTON loads from it), UNet as safetensors."""
    from huggingface_hub import hf_hub_download

    for name in ("scheduler/scheduler_config.json", "unet/config.json"):
        hf_hub_download(repo_id, name, local_dir=root)
    weights = root / "unet" / "diffusion_pytorch_model.safetensors"
    if not weights.exists():
        hf_hub_download(repo_id, "unet/diffusion_pytorch_model.fp16.safetensors", local_dir=root)
        (root / "unet" / "diffusion_pytorch_model.fp16.safetensors").rename(weights)
    return root


def local_attn(repo_id: str, version: str, root: Path) -> Path:
    """Only the attention checkpoint for `version`, laid out as CatVTON expects."""
    from huggingface_hub import hf_hub_download

    hf_hub_download(repo_id, f"{ATTN_FOLDERS[version]}/attention/model.safetensors", local_dir=root)
    return root


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", help="data pack folder (default: auto-detect under /kaggle/input)")
    ap.add_argument("--repo", required=True, help="CatVTON git checkout")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default="stable-diffusion-v1-5/stable-diffusion-inpainting")
    ap.add_argument("--attn-ckpt", default="zhengchong/CatVTON")
    ap.add_argument("--checkpoint", default="mix", choices=list(ATTN_FOLDERS))
    ap.add_argument("--weights-dir", default=str(Path(tempfile.gettempdir()) / "smartfit-weights"))
    ap.add_argument("--precision", default="fp16", choices=["fp16", "fp32"])
    ap.add_argument("--steps", type=int, default=50)
    ap.add_argument("--guidance", type=float, default=2.5)
    ap.add_argument("--height", type=int)
    ap.add_argument("--width", type=int)
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--limit", type=int, help="run only the first N jobs (smoke test)")
    args = ap.parse_args()

    import torch
    from PIL import Image

    sys.path.insert(0, str(Path(args.repo).resolve()))
    from model.pipeline import CatVTONPipeline

    pack = find_pack(args.pack)
    manifest = load_manifest(pack)
    height = args.height or manifest["height"]
    width = args.width or manifest["width"]
    jobs = manifest["jobs"][: args.limit] if args.limit else manifest["jobs"]
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    dtype = {"fp16": torch.float16, "fp32": torch.float32}[args.precision]

    weights = Path(args.weights_dir)
    base_dir = local_base(args.base, weights / args.base.replace("/", "--"))
    attn_dir = local_attn(args.attn_ckpt, args.checkpoint, weights / args.attn_ckpt.replace("/", "--"))
    with JobTimer(torch) as load:
        pipeline = CatVTONPipeline(
            base_ckpt=str(base_dir),
            attn_ckpt=str(attn_dir),
            attn_ckpt_version=args.checkpoint,
            weight_dtype=dtype,
            device=args.device,
            skip_safety_check=True,
        )
    print(f"CatVTON loaded in {load.seconds}s, peak {load.peak_reserved_gb} GB")

    results = []
    for n, job in enumerate(jobs, 1):
        row = {"id": job["id"], "group": job["group"]}
        try:
            person = Image.open(pack / job["person"]).convert("RGB")
            garment = Image.open(pack / job["garment"]).convert("RGB")
            mask = Image.open(pack / job["mask"]).convert("L")
            generator = torch.Generator(device=args.device).manual_seed(manifest["seed"])
            with JobTimer(torch) as t:
                image = pipeline(
                    person, garment, mask,
                    num_inference_steps=args.steps,
                    guidance_scale=args.guidance,
                    height=height,
                    width=width,
                    generator=generator,
                )[0]
            image.save(out / "images" / f"{job['id']}.png")
            row |= {"status": "ok", "seconds": t.seconds, "peak_alloc_gb": t.peak_alloc_gb,
                    "peak_reserved_gb": t.peak_reserved_gb, "image": f"images/{job['id']}.png"}
        except torch.cuda.OutOfMemoryError:
            row |= {"status": "oom"}
            torch.cuda.empty_cache()
        except Exception as exc:  # keep going; the report shows which job failed and why
            row |= {"status": "error", "error": f"{type(exc).__name__}: {exc}"}
            traceback.print_exc()
        results.append(row)
        print(f"[{n}/{len(jobs)}] {job['id']}: {row['status']} {row.get('seconds', '')}s")

    metrics = paired_metrics(pack, out, jobs, results, args.device)
    write_results(out, {
        "model": "catvton",
        "license": "CC BY-NC-SA 4.0 (non-commercial)",
        "settings": {"base": args.base, "unet_weights": "fp16 safetensors", "attn_ckpt": args.attn_ckpt,
                     "checkpoint": args.checkpoint,
                     "precision": args.precision, "steps": args.steps, "guidance": args.guidance,
                     "height": height, "width": width, "seed": manifest["seed"]},
        "environment": environment(torch, ["diffusers", "transformers", "accelerate", "huggingface-hub", "numpy"]),
        "load_seconds": load.seconds,
        "load_peak_reserved_gb": load.peak_reserved_gb,
        "summary": summarise(results),
        "metrics": metrics,
        "jobs": results,
    })
    return 0 if all(r["status"] == "ok" for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
