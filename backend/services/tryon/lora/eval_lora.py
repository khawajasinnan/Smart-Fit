"""Base vs LoRA try-on on manifest samples (spec §8.5).

    python eval_lora.py --repo /tmp/IDM-VTON --manifest vitonhd_test.jsonl --adapter RUN/adapter --out EVAL [--limit 50]

Runs on Kaggle (GPU T4 x2). Each sample is generated twice with the same
seed and inputs, once with the LoRA adapter disabled (the pretrained
IDM-VTON) and once enabled, and both are scored against the ground truth
(the person photo, paired setting): SSIM (higher is better) and LPIPS
(AlexNet, lower is better). On the overfit run's own training samples, LoRA
must win clearly; that is the learning sanity check. On held-out test
samples it is the before/after comparison.

Outputs: EVAL/images/{base,lora}/<id>.png, EVAL/sheet.jpg
(person | garment | base | LoRA | ground truth) and EVAL/results.json.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

import torch
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))

from data import read_manifest  # noqa: E402
from idm import BASE, build_pipeline, free_memory, generate, gpu_peaks_gb, load_components  # noqa: E402
from train_lora import find_data_root  # noqa: E402

THUMB = (192, 256)


def scores(gt: Image.Image, pred: Image.Image, lpips_net) -> tuple[float, float]:
    import numpy as np
    from skimage.metrics import structural_similarity

    a = np.array(gt.convert("RGB"))
    b = np.array(pred.convert("RGB").resize(gt.size, Image.BICUBIC))
    ssim = float(structural_similarity(a, b, channel_axis=2, data_range=255))
    with torch.no_grad():
        ta = torch.from_numpy(a).permute(2, 0, 1)[None].float().div(127.5).sub(1)
        tb = torch.from_numpy(b).permute(2, 0, 1)[None].float().div(127.5).sub(1)
        dist = float(lpips_net(ta, tb).item())
    return round(ssim, 4), round(dist, 4)


def sheet(rows: list[list[tuple[Image.Image, str]]]) -> Image.Image:
    w, h = THUMB[0], THUMB[1] + 18
    out = Image.new("RGB", (w * max(len(r) for r in rows), h * len(rows)), "white")
    for y, row in enumerate(rows):
        for x, (img, label) in enumerate(row):
            out.paste(img.convert("RGB").resize(THUMB, Image.BICUBIC), (x * w, y * h + 18))
            ImageDraw.Draw(out).text((x * w + 3, y * h + 3), label[:34], fill="black")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--data-root")
    ap.add_argument("--adapter", required=True, help="folder written by train_lora.py (adapter/ or a checkpoint's adapter/)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--weights-dir", default="/tmp/smartfit-weights")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--guidance", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args(argv)
    sys.path.insert(0, str(Path(args.repo).resolve()))
    import lpips
    from peft import PeftModel

    root = find_data_root(args.data_root)
    records = read_manifest(Path(args.manifest))
    records = records[: args.limit] if args.limit else records
    out = Path(args.out)
    for sub in ("base", "lora"):
        (out / "images" / sub).mkdir(parents=True, exist_ok=True)

    c = load_components(args.base, Path(args.weights_dir) / args.base.replace("/", "--"))
    model = PeftModel.from_pretrained(c.unet, args.adapter)
    model.eval()
    pipe = build_pipeline(c, args.base, model.get_base_model())
    lpips_net = lpips.LPIPS(net="alex", verbose=False).eval()

    rows, results = [], []
    for n, r in enumerate(records, 1):
        person = Image.open(root / r["person_image_path"])
        garment = Image.open(root / r["cloth_image_path"])
        mask = Image.open(root / r["agnostic_mask_path"])
        pose = Image.open(root / r["densepose_path"])
        sid = r["sample_id"].replace(":", "_")
        row = {"sample_id": r["sample_id"]}
        images = {}
        for variant in ("base", "lora"):
            started = time.time()
            if variant == "base":
                with model.disable_adapter():
                    img = generate(pipe, person, garment, mask, pose, r["garment_caption"], args.seed,
                                   args.steps, args.guidance)
            else:
                img = generate(pipe, person, garment, mask, pose, r["garment_caption"], args.seed,
                               args.steps, args.guidance)
            img.save(out / "images" / variant / f"{sid}.png")
            images[variant] = img
            ssim, dist = scores(person, img, lpips_net)
            row |= {f"{variant}_ssim": ssim, f"{variant}_lpips": dist,
                    f"{variant}_seconds": round(time.time() - started, 1)}
        results.append(row)
        rows.append([(person, r["sample_id"]), (garment, r["garment_caption"]),
                     (images["base"], f"base ssim {row['base_ssim']} lpips {row['base_lpips']}"),
                     (images["lora"], f"LoRA ssim {row['lora_ssim']} lpips {row['lora_lpips']}"),
                     (person, "ground truth")])
        print(f"[{n}/{len(records)}] {r['sample_id']}: base lpips {row['base_lpips']} -> LoRA {row['lora_lpips']}")

    def mean(key):
        return round(statistics.mean(x[key] for x in results), 4) if results else None

    summary = {
        "samples": len(results),
        "base_ssim": mean("base_ssim"), "lora_ssim": mean("lora_ssim"),
        "base_lpips": mean("base_lpips"), "lora_lpips": mean("lora_lpips"),
        "lora_better_lpips": sum(x["lora_lpips"] < x["base_lpips"] for x in results),
        "peak_reserved_gb_by_gpu": gpu_peaks_gb(),
    }
    sheet(rows).save(out / "sheet.jpg", quality=90)
    (out / "results.json").write_text(json.dumps({
        "adapter": args.adapter, "manifest": args.manifest, "steps": args.steps, "guidance": args.guidance,
        "seed": args.seed, "prompt": "model is wearing <caption> / a photo of <caption>",
        "summary": summary, "samples": results}, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    free_memory()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
