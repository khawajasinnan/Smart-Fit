"""Shared helpers for the try-on baseline runners (spec §8.1).

Runs inside Kaggle as a plain script (no SmartFit imports): reads the data
pack's manifest.json, times each job, records peak GPU memory and writes
results/<model>/results.json in one format for both models, so
compare.py can line them up.
"""

from __future__ import annotations

import json
import platform
import statistics
import sys
import time
from pathlib import Path


def find_pack(explicit: str | None) -> Path:
    """The data pack root (folder holding manifest.json)."""
    if explicit:
        root = Path(explicit)
        if not (root / "manifest.json").exists():
            sys.exit(f"manifest.json not found in {root}")
        return root
    hits = sorted(Path("/kaggle/input").glob("**/manifest.json"))
    if not hits:
        sys.exit("No manifest.json under /kaggle/input. Attach the SmartFit try-on pack dataset.")
    return hits[0].parent


def load_manifest(pack: Path) -> dict:
    return json.loads((pack / "manifest.json").read_text(encoding="utf-8"))


def gpu_info(torch) -> dict:
    if not torch.cuda.is_available():
        return {"gpu": None}
    p = torch.cuda.get_device_properties(0)
    return {
        "gpu": p.name,
        "gpu_count": torch.cuda.device_count(),
        "vram_gb": round(p.total_memory / 1e9, 1),
        "compute_capability": f"{p.major}.{p.minor}",
        "bf16_supported": bool(torch.cuda.is_bf16_supported()),
    }


def environment(torch, packages: list[str]) -> dict:
    import importlib.metadata as md

    versions = {}
    for name in packages:
        try:
            versions[name] = md.version(name)
        except md.PackageNotFoundError:
            versions[name] = None
    return {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "cuda": torch.version.cuda,
        **gpu_info(torch),
        "packages": versions,
    }


class JobTimer:
    """Wall time per job (CUDA-synchronised) and peak memory since reset.

    Peaks are summed over all GPUs (a model split over two GPUs needs both);
    by_gpu has the per-GPU reserved peaks.
    """

    def __init__(self, torch) -> None:
        self.torch = torch
        self.gpus = range(torch.cuda.device_count()) if torch.cuda.is_available() else range(0)

    def __enter__(self):
        for i in self.gpus:
            self.torch.cuda.synchronize(i)
            self.torch.cuda.reset_peak_memory_stats(i)
        self.start = time.perf_counter()
        return self

    def __exit__(self, *exc):
        for i in self.gpus:
            self.torch.cuda.synchronize(i)
        self.seconds = round(time.perf_counter() - self.start, 2)
        if not self.gpus:
            self.peak_alloc_gb = self.peak_reserved_gb = None
            self.by_gpu = []
            return False
        cuda = self.torch.cuda
        self.by_gpu = [round(cuda.max_memory_reserved(i) / 1e9, 2) for i in self.gpus]
        self.peak_reserved_gb = round(sum(self.by_gpu), 2)
        self.peak_alloc_gb = round(sum(cuda.max_memory_allocated(i) for i in self.gpus) / 1e9, 2)
        return False


def summarise(jobs: list[dict]) -> dict:
    """Median time excludes the first job (CUDA warm-up)."""
    done = [j for j in jobs if j.get("status") == "ok"]
    times = [j["seconds"] for j in done[1:]] or [j["seconds"] for j in done]
    peaks = [j["peak_reserved_gb"] for j in done if j.get("peak_reserved_gb") is not None]
    return {
        "jobs_ok": len(done),
        "jobs_failed": sum(1 for j in jobs if j.get("status") != "ok"),
        "median_seconds_per_image": round(statistics.median(times), 2) if times else None,
        "max_seconds_per_image": max(times) if times else None,
        "peak_vram_reserved_gb": max(peaks) if peaks else None,
    }


def paired_metrics(pack: Path, out: Path, jobs: list[dict], results: list[dict], device: str) -> dict:
    """SSIM and LPIPS (AlexNet) against the ground truth, for paired jobs.

    Adds "ssim"/"lpips" to each result row. With ~10 samples these are
    indicative only; the full-test-set numbers come in step 5 (spec §8.5).
    """
    try:
        import lpips
        import numpy as np
        import torch
        from PIL import Image
        from skimage.metrics import structural_similarity
    except ImportError as exc:
        return {"skipped": f"metrics packages missing: {exc}"}

    by_id = {j["id"]: j for j in jobs}
    net = lpips.LPIPS(net="alex", verbose=False).to(device).eval()
    ssims, dists = [], []
    for row in results:
        job = by_id[row["id"]]
        if row.get("status") != "ok" or not job.get("ground_truth"):
            continue
        gt = Image.open(pack / job["ground_truth"]).convert("RGB")
        pred = Image.open(out / row["image"]).convert("RGB").resize(gt.size, Image.BICUBIC)
        a, b = np.array(gt), np.array(pred)  # writable copies for torch.from_numpy
        row["ssim"] = round(float(structural_similarity(a, b, channel_axis=2, data_range=255)), 4)
        with torch.no_grad():
            ta = torch.from_numpy(a).permute(2, 0, 1)[None].float().div(127.5).sub(1).to(device)
            tb = torch.from_numpy(b).permute(2, 0, 1)[None].float().div(127.5).sub(1).to(device)
            row["lpips"] = round(float(net(ta, tb).item()), 4)
        ssims.append(row["ssim"])
        dists.append(row["lpips"])
    if not ssims:
        return {"paired_jobs": 0}
    return {
        "paired_jobs": len(ssims),
        "ssim_mean": round(statistics.mean(ssims), 4),
        "lpips_mean": round(statistics.mean(dists), 4),
        "note": "higher SSIM and lower LPIPS are better; small sample, indicative only",
    }


def write_results(out: Path, payload: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps(payload["summary"], indent=2))
