"""Build the try-on baseline data pack (spec §8.1) for upload to Kaggle.

    python services/tryon/baseline/build_pack.py OUT_DIR [--zip]
    python services/tryon/baseline/build_pack.py OUT_DIR --roboflow-candidates CANDIDATE_DIR
    python services/tryon/baseline/build_pack.py OUT_DIR --roboflow-picks PICKS_DIR --zip

Runs locally (backend/.venv-cpu). Writes OUT_DIR/manifest.json plus the
images it refers to and a copy of the runner code (code/), so one private
Kaggle dataset holds everything the notebooks need.

Jobs (same for both models):
  * vitonhd_paired:   N seeded VITON-HD test persons wearing their own
                      garment (ground truth available -> SSIM/LPIPS);
  * vitonhd_unpaired: the same persons with the official test_pairs.txt
                      garment (the realistic case: someone else's garment);
  * outfitters:       K catalog upper-body products on the first P persons.
                      Catalog primary images are model shots, so the first
                      product image with no person in it (MediaPipe pose)
                      and a whole garment on a plain background is used as
                      the flat-lay;
  * roboflow:         optional, garments picked by hand from the crops
                      written by --roboflow-candidates (test only, §23.4).

All try-ons use VITON-HD persons, so masks and DensePose come from the
dataset (spec §23.5). Non-VITON garments are padded to 3:4 with their own
background colour and resized to 768x1024, the VITON-HD garment format.

Licences: VITON-HD and the Roboflow export are non-commercial; retailer
images are the retailer's. Upload the pack as a PRIVATE Kaggle dataset.
"""

from __future__ import annotations

import argparse
import asyncio
import io
import json
import random
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse

BASELINE = Path(__file__).resolve().parent
BACKEND = BASELINE.parents[2]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))

SIZE = (768, 1024)
IDM_COMMIT = "0d5f3ec2d737487a9bb24e4100936ad254780383"
TAGS_URL = f"https://raw.githubusercontent.com/yisol/IDM-VTON/{IDM_COMMIT}/vitonhd_test_tagged.json"
IMAGE_HOSTS = {"cdn.shopify.com", "outfitters.com.pk"}
# Roboflow classes usable as upper-body test garments, with the caption used.
ROBOFLOW_UPPER = {"Kameez Womens": "kameez", "Shirt": "shirt"}
CODE_FILES = ("common.py", "run_catvton.py", "run_idmvton.py", "compare.py",
              "requirements-catvton.txt", "requirements-idmvton.txt")


def idm_captions(tags: dict) -> dict[str, str]:
    """file_name -> garment text, built exactly like IDM-VTON's inference.py."""
    captions = {}
    for entries in tags.values():
        for elem in entries:
            text = ""
            for template in ("sleeveLength", "neckLine", "item"):
                for tag in elem["tag_info"]:
                    if tag["tag_name"] == template and tag["tag_category"] is not None:
                        text += tag["tag_category"] + " "
            captions[elem["file_name"]] = text.strip()
    return captions


def border_colour(img) -> tuple[int, int, int]:
    import numpy as np

    a = np.asarray(img.convert("RGB"))
    edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    return tuple(int(v) for v in np.median(edge, axis=0))


def looks_like_flatlay(img) -> bool:
    """Whole garment on a plain background: a uniform border, and the garment
    neither touches the edges (close-up crops do) nor is tiny."""
    import numpy as np

    a = np.asarray(img.convert("RGB").resize((192, 256))).astype(np.int16)
    bg = np.array(border_colour(img), dtype=np.int16)
    fg = np.abs(a - bg).max(axis=2) > 30
    edge = np.concatenate([fg[:4].ravel(), fg[-4:].ravel(), fg[:, :4].ravel(), fg[:, -4:].ravel()])
    return min(bg) >= 200 and edge.mean() < 0.02 and 0.15 < fg.mean() < 0.85


def pad_to_garment(img):
    """Centre on a 3:4 canvas of the photo's own background colour, then
    resize to 768x1024."""
    from PIL import Image

    w, h = img.size
    if w * 4 > h * 3:
        cw, ch = w, round(w * 4 / 3)
    else:
        cw, ch = round(h * 3 / 4), h
    canvas = Image.new("RGB", (cw, ch), border_colour(img))
    canvas.paste(img, ((cw - w) // 2, (ch - h) // 2))
    return canvas.resize(SIZE, Image.LANCZOS)


def load_tags(path: str | None, out: Path) -> dict:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    import httpx

    res = httpx.get(TAGS_URL, timeout=60, follow_redirects=False)
    res.raise_for_status()
    (out / "meta").mkdir(parents=True, exist_ok=True)
    (out / "meta" / "vitonhd_test_tagged.json").write_bytes(res.content)
    return res.json()


def add_vitonhd(viton: Path, out: Path, n: int, seed: int, captions: dict[str, str]) -> tuple[list[dict], list[str]]:
    test = viton / "test"
    unpaired = {}
    for line in (viton / "test_pairs.txt").read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 2:
            unpaired[parts[0]] = parts[1]
    persons = sorted(p.name for p in (test / "image").iterdir() if p.name in unpaired)
    chosen = sorted(random.Random(seed).sample(persons, n))

    for sub in ("persons", "masks", "densepose", "garments/vitonhd"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    jobs = []
    for name in chosen:
        stem = name.removesuffix(".jpg")
        shutil.copy2(test / "image" / name, out / "persons" / name)
        shutil.copy2(test / "agnostic-mask" / f"{stem}_mask.png", out / "masks" / f"{stem}_mask.png")
        shutil.copy2(test / "image-densepose" / name, out / "densepose" / name)
        person = {"person": f"persons/{name}", "mask": f"masks/{stem}_mask.png", "densepose": f"densepose/{name}"}
        for group, cloth in (("vitonhd_paired", name), ("vitonhd_unpaired", unpaired[name])):
            shutil.copy2(test / "cloth" / cloth, out / "garments" / "vitonhd" / cloth)
            job = {"id": f"{group.split('_')[1]}_{stem}_{cloth.removesuffix('.jpg')}", "group": group, **person,
                   "garment": f"garments/vitonhd/{cloth}", "garment_caption": captions.get(cloth) or "shirts"}
            if group == "vitonhd_paired":
                job["ground_truth"] = f"persons/{name}"
            jobs.append(job)
    return jobs, chosen


async def find_flatlays(count: int, seed: int, max_products: int) -> list[tuple[dict, object, str]]:
    """(product, flat-lay image, its URL) for `count` upper-body catalog products."""
    import cv2
    import httpx
    import numpy as np
    from PIL import Image
    from services.cv_analysis.pose import PoseEstimator
    from services.scraper.polite import PoliteClient
    from shared.config import settings

    snapshot = Path(settings.catalog_snapshot_path)
    if not snapshot.is_absolute():
        snapshot = BACKEND / snapshot
    products = [json.loads(line) for line in snapshot.read_text(encoding="utf-8").splitlines() if line.strip()]
    upper = sorted((p for p in products if p.get("tryon_category") == "upper"), key=lambda p: p["product_id"])
    random.Random(seed).shuffle(upper)
    pose = PoseEstimator()
    found = []
    try:
        async with httpx.AsyncClient() as http:
            polite = PoliteClient(http)
            for product in upper[:max_products]:
                for url in product.get("image_urls") or [product["image_url"]]:
                    if urlparse(url).hostname not in IMAGE_HOSTS:
                        continue
                    res = await polite.get(url, timeout=30, follow_redirects=False)
                    res.raise_for_status()
                    img = Image.open(io.BytesIO(res.content)).convert("RGB")
                    bgr = cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)
                    if not pose.detect_people(bgr) and looks_like_flatlay(img):
                        found.append((product, img, url))
                        print(f"  flat-lay: {product['product_id']} {product['name']}")
                        break
                if len(found) == count:
                    return found
    finally:
        pose.close()
    print(f"  only {len(found)} of {count} flat-lays found in {max_products} products")
    return found


def add_outfitters(out: Path, flatlays: list, persons: list[str]) -> list[dict]:
    (out / "garments" / "outfitters").mkdir(parents=True, exist_ok=True)
    jobs, sources = [], []
    for product, img, url in flatlays:
        slug = product["product_id"].split(":", 1)[1]
        pad_to_garment(img).save(out / "garments" / "outfitters" / f"{slug}.jpg", quality=95)
        sources.append({"product_id": product["product_id"], "name": product["name"],
                        "product_url": product["product_url"], "image_url": url})
        for name in persons:
            stem = name.removesuffix(".jpg")
            jobs.append({"id": f"outfitters_{stem}_{slug}", "group": "outfitters",
                         "person": f"persons/{name}", "mask": f"masks/{stem}_mask.png",
                         "densepose": f"densepose/{name}", "garment": f"garments/outfitters/{slug}.jpg",
                         "garment_caption": product["name"].lower()})
    (out / "meta").mkdir(exist_ok=True)
    (out / "meta" / "outfitters_sources.json").write_text(json.dumps(sources, indent=2), encoding="utf-8")
    return jobs


def export_roboflow_candidates(raw: Path, dest: Path) -> int:
    """Crop every upper-body garment box so they can be picked by eye."""
    from PIL import Image

    dest.mkdir(parents=True, exist_ok=True)
    n = 0
    for split in ("train", "valid", "test"):
        coco = json.loads((raw / split / "_annotations.coco.json").read_text(encoding="utf-8"))
        cats = {c["id"]: c["name"] for c in coco["categories"]}
        files = {i["id"]: i["file_name"] for i in coco["images"]}
        for ann in coco["annotations"]:
            cat = cats[ann["category_id"]]
            if cat not in ROBOFLOW_UPPER:
                continue
            x, y, w, h = ann["bbox"]
            if min(w, h) < 120:
                continue
            with Image.open(raw / split / files[ann["image_id"]]) as img:
                mx, my = w * 0.05, h * 0.05
                box = (max(0, x - mx), max(0, y - my), min(img.width, x + w + mx), min(img.height, y + h + my))
                crop = img.convert("RGB").crop(tuple(round(v) for v in box))
            crop.save(dest / f"{ROBOFLOW_UPPER[cat]}__{split}_{ann['id']}.jpg", quality=95)
            n += 1
    return n


def add_roboflow(out: Path, picks: Path, persons: list[str]) -> list[dict]:
    from PIL import Image

    (out / "garments" / "roboflow").mkdir(parents=True, exist_ok=True)
    jobs = []
    for i, path in enumerate(sorted(picks.glob("*.jpg"))):
        caption = path.name.split("__", 1)[0] if "__" in path.name else "shirt"
        with Image.open(path) as img:
            pad_to_garment(img.convert("RGB")).save(out / "garments" / "roboflow" / path.name, quality=95)
        name = persons[i % len(persons)]
        stem = name.removesuffix(".jpg")
        jobs.append({"id": f"roboflow_{stem}_{path.stem}", "group": "roboflow", "person": f"persons/{name}",
                     "mask": f"masks/{stem}_mask.png", "densepose": f"densepose/{name}",
                     "garment": f"garments/roboflow/{path.name}", "garment_caption": caption})
    return jobs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--viton", default=str(REPO / "datasets" / "viton-hd"))
    ap.add_argument("--tags", help="local vitonhd_test_tagged.json (default: download from the pinned IDM-VTON commit)")
    ap.add_argument("--persons", type=int, default=10)
    ap.add_argument("--outfitters", type=int, default=4, help="number of catalog garments")
    ap.add_argument("--outfitter-persons", type=int, default=4)
    ap.add_argument("--max-products", type=int, default=40, help="products to check for a flat-lay")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--roboflow-raw", default=str(REPO / "datasets" / "pakistani-roboflow" / "raw"))
    ap.add_argument("--roboflow-candidates", help="write crops here for manual picking, then exit")
    ap.add_argument("--roboflow-picks", help="folder of picked crops to include")
    ap.add_argument("--zip", action="store_true", help="also write OUT.zip for upload")
    args = ap.parse_args()

    if args.roboflow_candidates:
        n = export_roboflow_candidates(Path(args.roboflow_raw), Path(args.roboflow_candidates))
        print(f"{n} candidate crops in {args.roboflow_candidates}. Copy the clean, front-facing ones to a "
              "picks folder and rerun with --roboflow-picks.")
        return 0

    out = Path(args.out)
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty; choose a new folder.")
    out.mkdir(parents=True, exist_ok=True)

    captions = idm_captions(load_tags(args.tags, out))
    jobs, persons = add_vitonhd(Path(args.viton), out, args.persons, args.seed, captions)
    print(f"VITON-HD: {len(persons)} persons, {len(jobs)} jobs")
    if args.outfitters:
        flatlays = asyncio.run(find_flatlays(args.outfitters, args.seed, args.max_products))
        jobs += add_outfitters(out, flatlays, persons[: args.outfitter_persons])
    if args.roboflow_picks:
        jobs += add_roboflow(out, Path(args.roboflow_picks), persons)

    (out / "code").mkdir()
    for name in CODE_FILES:
        shutil.copy2(BASELINE / name, out / "code" / name)
    manifest = {"version": 1, "height": SIZE[1], "width": SIZE[0], "seed": args.seed,
                "note": "Private research pack: VITON-HD / Roboflow are non-commercial; retailer images belong "
                        "to the retailer. Do not make this dataset public.",
                "jobs": jobs}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    counts = {}
    for j in jobs:
        counts[j["group"]] = counts.get(j["group"], 0) + 1
    print(f"manifest: {len(jobs)} jobs {counts}")
    if args.zip:
        archive = shutil.make_archive(str(out), "zip", root_dir=out)
        print(f"zip: {archive} ({Path(archive).stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
