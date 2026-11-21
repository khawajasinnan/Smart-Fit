"""Side-by-side comparison of baseline runs (spec §8.1).

    python compare.py --pack PACK --results results/catvton results/idmvton --out comparison

Needs only Pillow. Reads each run's results.json and writes:
  * sheet_<group>.jpg: one row per job: person | garment | each model |
    ground truth (paired jobs), for judging by eye;
  * comparison.md / comparison.json: speed, peak VRAM, failures and the
    paired SSIM/LPIPS per model.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

THUMB = (240, 320)
LABEL_H = 22


def tile(path: Path | None, label: str) -> Image.Image:
    cell = Image.new("RGB", (THUMB[0], THUMB[1] + LABEL_H), "white")
    if path is not None and path.exists():
        with Image.open(path) as img:
            cell.paste(img.convert("RGB").resize(THUMB, Image.BICUBIC), (0, LABEL_H))
    else:
        ImageDraw.Draw(cell).text((10, LABEL_H + THUMB[1] // 2), "no image", fill="red")
    ImageDraw.Draw(cell).text((4, 4), label[:38], fill="black")
    return cell


def sheet(rows: list[list[Image.Image]]) -> Image.Image:
    cols = max(len(r) for r in rows)
    w, h = THUMB[0], THUMB[1] + LABEL_H
    out = Image.new("RGB", (cols * w, len(rows) * h), "white")
    for y, row in enumerate(rows):
        for x, cell in enumerate(row):
            out.paste(cell, (x * w, y * h))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True)
    ap.add_argument("--results", nargs="+", required=True, help="one results/<model> folder per model")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    pack, out = Path(args.pack), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((pack / "manifest.json").read_text(encoding="utf-8"))
    runs = []
    for folder in map(Path, args.results):
        data = json.loads((folder / "results.json").read_text(encoding="utf-8"))
        runs.append((folder, data, {r["id"]: r for r in data["jobs"]}))

    groups: dict[str, list[dict]] = {}
    for job in manifest["jobs"]:
        groups.setdefault(job["group"], []).append(job)
    for group, jobs in groups.items():
        rows = []
        for job in jobs:
            row = [tile(pack / job["person"], job["id"]), tile(pack / job["garment"], job.get("garment_caption", ""))]
            for folder, data, by_id in runs:
                r = by_id.get(job["id"], {})
                label = data["model"]
                if r.get("status") != "ok":
                    label += f" ({r.get('status', 'missing')})"
                elif "lpips" in r:
                    label += f" ssim {r['ssim']:.3f} lpips {r['lpips']:.3f}"
                row.append(tile(folder / r["image"] if r.get("image") else None, label))
            if job.get("ground_truth"):
                row.append(tile(pack / job["ground_truth"], "ground truth"))
            rows.append(row)
        sheet(rows).save(out / f"sheet_{group}.jpg", quality=90)

    table = []
    for _, data, _ in runs:
        s, m, env = data["summary"], data.get("metrics", {}), data["environment"]
        table.append({
            "model": data["model"],
            "gpu": env.get("gpu"),
            "settings": data["settings"],
            "load_seconds": data["load_seconds"],
            "jobs_ok": s["jobs_ok"],
            "jobs_failed": s["jobs_failed"],
            "median_seconds_per_image": s["median_seconds_per_image"],
            "peak_vram_reserved_gb": s["peak_vram_reserved_gb"],
            "ssim_mean": m.get("ssim_mean"),
            "lpips_mean": m.get("lpips_mean"),
            "paired_jobs": m.get("paired_jobs"),
        })
    (out / "comparison.json").write_text(json.dumps(table, indent=2), encoding="utf-8")
    lines = [
        "| Model | GPU | OK / failed | Median s/image | Peak VRAM (GB) | SSIM (higher=better) | LPIPS (lower=better) | Paired n |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for t in table:
        lines.append(f"| {t['model']} | {t['gpu']} | {t['jobs_ok']} / {t['jobs_failed']} | "
                     f"{t['median_seconds_per_image']} | {t['peak_vram_reserved_gb']} | {t['ssim_mean']} | "
                     f"{t['lpips_mean']} | {t['paired_jobs']} |")
    lines += ["", "Sheets: " + ", ".join(f"sheet_{g}.jpg" for g in groups),
              "", "SSIM/LPIPS use ~10 paired samples: indicative only. Judge the unpaired and Outfitters sheets by eye."]
    (out / "comparison.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
