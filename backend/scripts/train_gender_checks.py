"""Train the two try-on gender checks (18 Nov 2026): menswear on men, womenswear on women.

    python scripts/train_gender_checks.py garment [--per-gender 1200]
    python scripts/train_gender_checks.py face --dataset ../datasets/CelebAMask-HQ/CelebAMask-HQ [--per-gender 3000]

Both are a logistic regression on Marqo-FashionCLIP image embeddings (the
model the recommendation service already runs), saved with a decision
threshold chosen on held-out data so that a confident answer is right at
least TARGET_PRECISION of the time; anything less confident is "not sure"
and never blocks a try-on.

* garment: catalog products labelled men / women by their brand's own feed,
  the photo the try-on itself would use (the first flat-lay, else the main
  photo). Held-out set = whole BRANDS the model never saw.
* face: CelebAMask-HQ faces with the "Male" attribute, shrunk to the size a
  head has in a full-body phone photo (48-160 px) before embedding. Held out:
  faces never trained on.

Writes services/recommendation/models/gender/{garment,face}_gender.joblib and a
.json report with the measured accuracy (gitignored: dataset-derived).
"""

from __future__ import annotations

import argparse
import asyncio
import io
import json
import random
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

OUT = BACKEND / "services" / "recommendation" / "models" / "gender"
CACHE = BACKEND / ".cache" / "gender"
TARGET_PRECISION = 0.97
# Never below these per side, whatever the search finds. Measured on held-out data:
# garment 0.85 both sides -> 0 wrong of 625 photos from unseen brands, sure on 93 % (18 Nov 2026).
# face: "man" 0.90; "woman" 0.70 (19 Nov 2026) -> 97.9 % right on CelebA, and on real phone
# photos 50/52 women sure (was 17/52 at 0.90) with 0 of 72 men above 0.06. The person check
# also needs the whole photo to agree (gender_check.check_person). A try-on is only blocked
# when the clothes AND the person are both sure and disagree.
MIN_THRESHOLD = {"garment_gender": {"men": 0.85, "women": 0.85},
                 "face_gender": {"man": 0.90, "woman": 0.70}}
SEED = 7


def embedder():
    from services.recommendation.embeddings import FashionClip

    return FashionClip()


def embed_all(clip, images: list[Image.Image], batch: int = 32) -> np.ndarray:
    out = []
    for i in range(0, len(images), batch):
        out.append(clip.embed_images(images[i:i + batch]))
        print(f"  embedded {min(i + batch, len(images))}/{len(images)}", end="\r", flush=True)
    print()
    return np.concatenate(out) if out else np.zeros((0, clip.dim), np.float32)


def fit_and_report(x_tr, y_tr, x_te, y_te, labels: tuple[str, str], name: str, extra: dict) -> None:
    """y: 1 = labels[1]. A threshold per side: answer labels[1] when p >= t1 and
    labels[0] when 1 - p >= t0; anything in between is "not sure"."""
    import joblib
    from sklearn.linear_model import LogisticRegression

    model = LogisticRegression(C=1.0, max_iter=3000, class_weight="balanced")
    model.fit(x_tr, y_tr)
    p = model.predict_proba(x_te)[:, 1]
    pred = (p >= 0.5).astype(int)
    acc = float((pred == y_te).mean())

    def side_stats(t):
        res = {}
        for cls in (0, 1):
            conf = (p >= t) if cls == 1 else (p <= 1 - t)
            n = int(conf.sum())
            res[labels[cls]] = {"confident": n, "precision": float((y_te[conf] == cls).mean()) if n else None}
        cover = float(((p >= t) | (p <= 1 - t)).mean())
        return res, cover

    # Per side: the smallest t whose confident answers reach TARGET_PRECISION, floored.
    grid = np.arange(0.5, 0.996, 0.005)
    thresholds = []
    for cls in (0, 1):
        found = 0.995
        for t in grid:
            v = side_stats(t)[0][labels[cls]]
            if v["precision"] is not None and v["precision"] >= TARGET_PRECISION and v["confident"] >= 10:
                found = float(round(t, 3))
                break
        thresholds.append(max(found, MIN_THRESHOLD.get(name, {}).get(labels[cls], 0.5)))
    res = {}
    for cls in (0, 1):
        res[labels[cls]] = side_stats(thresholds[cls])[0][labels[cls]]
    sure = (p >= thresholds[1]) | (p <= 1 - thresholds[0])
    cover = float(sure.mean())
    t = max(thresholds)
    report = {"name": name, "labels": list(labels), "train": int(len(y_tr)), "test": int(len(y_te)),
              "held_out_accuracy": round(acc, 4), "threshold": t,
              "thresholds": dict(zip(labels, thresholds, strict=True)), "target_precision": TARGET_PRECISION,
              "confident_share": round(cover, 4),
              "confident_precision": {k: (round(v["precision"], 4) if v["precision"] is not None else None)
                                      for k, v in res.items()},
              **extra}
    OUT.mkdir(parents=True, exist_ok=True)
    joblib.dump({"model": model, "labels": labels, "threshold": t, "thresholds": tuple(thresholds)},
                OUT / f"{name}.joblib")
    (OUT / f"{name}.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


# ── garment ───────────────────────────────────────────────────────────────────


async def fetch_garment_images(per_gender: int) -> tuple[list[Image.Image], list[int], list[str]]:
    import httpx

    from services.tryon import imaging
    from shared import catalog_store

    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
        products = await catalog_store.load_products(client)
        rng = random.Random(SEED)
        pools = {g: [p for p in products if p.gender == g and p.tryon_category] for g in ("men", "women")}
        picked = []
        for g, pool in pools.items():
            rng.shuffle(pool)
            picked += pool[:per_gender]
        print(f"catalog: {len(products)} products; sampled {len(picked)}")
        sem = asyncio.Semaphore(8)

        async def get(url):
            try:
                async with sem:
                    r = await client.get(url, headers={"User-Agent": "SmartFitBot/1.0 (research)"})
                if r.status_code != 200 or len(r.content) > 8_000_000:
                    return None
                img = Image.open(io.BytesIO(r.content)).convert("RGB")
                img.thumbnail((512, 512))
                return img
            except Exception:  # noqa: BLE001
                return None

        async def garment_photo(p):
            urls = [p.image_url] + [u for u in p.image_urls if u != p.image_url]
            first = None
            for u in urls[:3]:
                img = await get(u)
                if img is None:
                    continue
                first = first or img
                if imaging.looks_like_flatlay(img):
                    return img
            return first

        imgs = await asyncio.gather(*(garment_photo(p) for p in picked))
    out_i, out_y, out_b = [], [], []
    for p, img in zip(picked, imgs, strict=True):
        if img is not None:
            out_i.append(img)
            out_y.append(1 if p.gender == "women" else 0)
            out_b.append(p.retailer)
    return out_i, out_y, out_b


def train_garment(per_gender: int) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    cache = CACHE / f"garment_{per_gender}.npz"
    if cache.exists():
        d = np.load(cache, allow_pickle=True)
        x, y, brands = d["x"], d["y"], list(d["brands"])
    else:
        t = time.time()
        images, y, brands = asyncio.run(fetch_garment_images(per_gender))
        print(f"fetched {len(images)} photos in {time.time() - t:.0f} s")
        x = embed_all(embedder(), images)
        y = np.asarray(y)
        np.savez(cache, x=x, y=y, brands=np.asarray(brands))
    # held out: whole brands (about a quarter of the photos), mixed men/women brands included
    rng = random.Random(SEED)
    uniq = sorted(set(brands))
    rng.shuffle(uniq)
    test_brands, n = set(), 0
    for b in uniq:
        if n >= 0.25 * len(brands):
            break
        test_brands.add(b)
        n += brands.count(b)
    te = np.asarray([b in test_brands for b in brands])
    fit_and_report(x[~te], y[~te], x[te], y[te], ("men", "women"), "garment_gender",
                   {"held_out_brands": sorted(test_brands)})


# ── face ──────────────────────────────────────────────────────────────────────


def small_face(img: Image.Image, rng: random.Random) -> Image.Image:
    """A 1024 px CelebA-HQ face at the size it has in a full-body photo."""
    side = rng.randint(48, 160)
    return img.resize((side, side), Image.BILINEAR)


def train_face(dataset: Path, per_gender: int) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    cache = CACHE / f"face_{per_gender}.npz"
    if cache.exists():
        d = np.load(cache)
        x, y = d["x"], d["y"]
    else:
        lines = (dataset / "CelebAMask-HQ-attribute-anno.txt").read_text().splitlines()
        cols = lines[1].split()
        male = cols.index("Male")
        rows = [ln.split() for ln in lines[2:]]
        rng = random.Random(SEED)
        rng.shuffle(rows)
        men = [r[0] for r in rows if r[1 + male] == "1"][:per_gender]
        women = [r[0] for r in rows if r[1 + male] == "-1"][:per_gender]
        names = men + women
        y = np.asarray([0] * len(men) + [1] * len(women))
        imgs = [small_face(Image.open(dataset / "CelebA-HQ-img" / n).convert("RGB"), rng) for n in names]
        x = embed_all(embedder(), imgs)
        np.savez(cache, x=x, y=y)
    idx = np.arange(len(y))
    np.random.default_rng(SEED).shuffle(idx)
    cut = int(0.75 * len(idx))
    fit_and_report(x[idx[:cut]], y[idx[:cut]], x[idx[cut:]], y[idx[cut:]], ("man", "woman"), "face_gender",
                   {"dataset": "CelebAMask-HQ (Male attribute), faces shrunk to 48-160 px"})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("which", choices=["garment", "face"])
    ap.add_argument("--per-gender", type=int, default=None)
    ap.add_argument("--dataset", type=Path, default=BACKEND.parent / "datasets" / "CelebAMask-HQ" / "CelebAMask-HQ")
    a = ap.parse_args()
    if a.which == "garment":
        train_garment(a.per_gender or 1200)
    else:
        train_face(a.dataset, a.per_gender or 3000)


if __name__ == "__main__":
    main()
