"""Upload each catalog hairstyle's source photo to the Modal Volume (spec §23.27).

    python backend/scripts/upload_hairstyle_refs.py [--dataset datasets/CelebAMask-HQ/CelebAMask-HQ]

HairFastGAN needs a photo of someone wearing the style as its reference: for
every entry in services/hairstyle/catalog/index.json that is the CelebA-HQ
image it was cut from ("CelebAMask-HQ #20898" -> CelebA-HQ-img/20898.jpg),
uploaded as /refs_raw/<style id>.jpg. Then run prepare_refs to align them.
CelebAMask-HQ is non-commercial research data: it goes to this project's own
private Modal Volume only, never to git.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "backend" / "services" / "hairstyle" / "catalog" / "index.json"
VOLUME = "smartfit-hairstyle-weights"


def references(index: Path, dataset: Path) -> tuple[dict[str, Path], list[str]]:
    found, missing = {}, []
    for item in json.loads(index.read_text(encoding="utf-8")):
        m = re.search(r"#(\d+)", item.get("source", ""))
        photo = dataset / "CelebA-HQ-img" / f"{m.group(1)}.jpg" if m else None
        if photo is not None and photo.exists():
            found[item["id"]] = photo
        else:
            missing.append(item["id"])
    return found, missing


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dataset", type=Path, default=ROOT / "datasets" / "CelebAMask-HQ" / "CelebAMask-HQ")
    args = ap.parse_args()
    found, missing = references(INDEX, args.dataset)
    if missing:
        print(f"no source photo for {len(missing)} styles: {missing[:5]}")
    if not found:
        return 1
    import modal

    volume = modal.Volume.from_name(VOLUME, create_if_missing=True)
    with volume.batch_upload(force=True) as batch:
        for style_id, photo in found.items():
            batch.put_file(str(photo), f"/refs_raw/{style_id}.jpg")
    print(f"uploaded {len(found)} reference photos to {VOLUME}:/refs_raw")
    return 0


if __name__ == "__main__":
    sys.exit(main())
