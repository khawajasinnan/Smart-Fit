"""Check a VITON-HD copy before training/evaluation (spec §5.1, §8.5).

    python scripts/verify_vitonhd.py [DATASET_DIR]      (default: datasets/viton-hd)

Reports, per split:
  * pairs file: format, duplicates, paired (person wears its own cloth) vs
    unpaired lines. The official pair files are unpaired (demo / FID);
    SSIM/LPIPS and LoRA training need the *paired* setting (person + own
    garment, same id), which is possible when every person's own garment
    exists;
  * every file each pair needs exists in every folder;
  * every image opens and has the expected size (header-only read: fast);
  * train/test leakage: the same person or garment id in both splits.
Exit code 0 = no problems.
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

from PIL import Image

# folder -> (filename suffix replacing ".jpg", expected size or None)
PERSON_FILES = {
    "image": (".jpg", (768, 1024)),
    "agnostic-mask": ("_mask.png", (768, 1024)),
    "agnostic-v3.2": (".jpg", (768, 1024)),
    "image-densepose": (".jpg", (768, 1024)),
    "image-parse-v3": (".png", (768, 1024)),
    "image-parse-agnostic-v3.2": (".png", (768, 1024)),
    "openpose_img": ("_rendered.png", None),
    "openpose_json": ("_keypoints.json", None),
}
CLOTH_FILES = {
    "cloth": (".jpg", (768, 1024)),
    "cloth-mask": (".jpg", (768, 1024)),
}
TRAIN_ONLY = {"gt_cloth_warped_mask": (".jpg", None)}


def read_pairs(path: Path) -> tuple[list[tuple[str, str]], list[str]]:
    pairs, problems = [], []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        parts = line.split()
        if not parts:
            continue
        if len(parts) != 2 or not all(p.endswith(".jpg") for p in parts):
            problems.append(f"{path.name}:{n}: bad line {line!r}")
            continue
        pairs.append((parts[0], parts[1]))
    return pairs, problems


def check_split(root: Path, split: str) -> tuple[dict, list[str]]:
    problems: list[str] = []
    pairs, bad = read_pairs(root / f"{split}_pairs.txt")
    problems += bad
    persons = [p for p, _ in pairs]
    cloths = [c for _, c in pairs]
    dup_lines = sum(n - 1 for n in Counter(pairs).values() if n > 1)
    dup_persons = sum(n - 1 for n in Counter(persons).values() if n > 1)
    paired = sum(1 for p, c in pairs if p == c)
    if dup_lines:
        problems.append(f"{split}: {dup_lines} duplicate pair lines")

    folders = dict(PERSON_FILES) | dict(CLOTH_FILES) | (TRAIN_ONLY if split == "train" else {})
    counts = {}
    for folder, (suffix, size) in folders.items():
        d = root / split / folder
        if not d.is_dir():
            problems.append(f"{split}/{folder}: folder missing")
            continue
        names = {f.name for f in d.iterdir()}
        counts[folder] = len(names)
        ids = cloths if folder in CLOTH_FILES else persons
        needed = {i.removesuffix(".jpg") + suffix for i in ids}
        missing = needed - names
        if missing:
            problems.append(f"{split}/{folder}: {len(missing)} files missing, e.g. {sorted(missing)[:3]}")
        if size is None:
            continue
        unreadable = wrong = 0
        for name in sorted(needed & names):
            try:
                with Image.open(d / name) as img:
                    if img.size != size:
                        wrong += 1
            except OSError:
                unreadable += 1
        if unreadable:
            problems.append(f"{split}/{folder}: {unreadable} unreadable images")
        if wrong:
            problems.append(f"{split}/{folder}: {wrong} images not {size[0]}x{size[1]}")
    image_ids = {f.name for f in (root / split / "image").iterdir()} if (root / split / "image").is_dir() else set()
    cloth_ids = {f.name for f in (root / split / "cloth").iterdir()} if (root / split / "cloth").is_dir() else set()
    own_missing = len(image_ids - cloth_ids)
    if own_missing:
        problems.append(f"{split}: {own_missing} persons have no own garment (paired evaluation impossible for them)")
    info = {
        "own_garment_for_every_person (paired setting possible)": own_missing == 0,
        "pairs": len(pairs),
        "paired_lines": paired,
        "unpaired_lines": len(pairs) - paired,
        "persons_used_more_than_once": dup_persons,
        "distinct_persons": len(set(persons)),
        "distinct_cloths": len(set(cloths)),
        "files_per_folder": counts,
    }
    return info, problems


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "datasets" / "viton-hd"
    if not root.is_dir():
        print(f"Not found: {root}")
        return 1
    all_problems: list[str] = []
    ids = {}
    for split in ("train", "test"):
        info, problems = check_split(root, split)
        all_problems += problems
        print(f"\n== {split}")
        for k, v in info.items():
            print(f"  {k}: {v}")
        pairs, _ = read_pairs(root / f"{split}_pairs.txt")
        ids[split] = ({p for p, _ in pairs}, {c for _, c in pairs})
    person_leak = ids["train"][0] & ids["test"][0]
    cloth_leak = ids["train"][1] & ids["test"][1]
    print(f"\n== leakage: persons in both splits: {len(person_leak)}, cloths in both splits: {len(cloth_leak)}")
    if person_leak or cloth_leak:
        all_problems.append(f"train/test overlap: {len(person_leak)} persons, {len(cloth_leak)} cloths")
    print("\n== result:", "OK" if not all_problems else f"{len(all_problems)} problem(s)")
    for p in all_problems:
        print("  ✗", p)
    return 0 if not all_problems else 1


if __name__ == "__main__":
    raise SystemExit(main())
