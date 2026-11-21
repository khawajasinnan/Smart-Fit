"""The hairstyle catalog: transparent hair cut-outs + their anchors and features.

Built once by scripts/build_hairstyle_catalog.py from CelebAMask-HQ (hand-
annotated hair masks on CelebA-HQ faces; non-commercial research licence,
so the cut-outs are not committed to git). Layout:

    services/hairstyle/catalog/index.json      list of entries (below)
    services/hairstyle/catalog/<id>.png        RGBA hair cut-out
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

import cv2

from services.hairstyle.overlay import HairAsset
from services.hairstyle.shape_classifier import StyleFeatures

logger = logging.getLogger("smartfit.hairstyle.catalog")

CATALOG_DIR = Path(__file__).resolve().parent / "catalog"
INDEX_NAME = "index.json"


@dataclass
class CatalogEntry:
    id: str
    name: str
    colour: str
    features: StyleFeatures
    asset: HairAsset
    source: str  # e.g. "CelebAMask-HQ #1234"


def entry_from_json(item: dict, directory: Path) -> CatalogEntry:
    rgba = cv2.imread(str(directory / item["file"]), cv2.IMREAD_UNCHANGED)
    if rgba is None or rgba.ndim != 3 or rgba.shape[2] != 4:
        raise ValueError(f"{item['file']} is not an RGBA PNG")
    f = item["features"]
    return CatalogEntry(
        id=item["id"],
        name=item["name"],
        colour=item.get("colour", ""),
        features=StyleFeatures(gender=f["gender"], length=f["length"], bangs=bool(f["bangs"]), wavy=bool(f["wavy"]),
                               top_volume=float(f["top_volume"]), side_width=float(f["side_width"])),
        asset=HairAsset(rgba=rgba, anchors=item["anchors"], skin_luma=item.get("skin_luma")),
        source=item.get("source", ""),
    )


def load_catalog(directory: Path = CATALOG_DIR) -> list[CatalogEntry]:
    """Every valid entry; a broken file is logged and skipped, never fatal."""
    index = directory / INDEX_NAME
    if not index.exists():
        return []
    entries = []
    for item in json.loads(index.read_text(encoding="utf-8")):
        try:
            entries.append(entry_from_json(item, directory))
        except (KeyError, ValueError, TypeError) as exc:
            logger.warning("skipping hairstyle %s: %s", item.get("id"), exc)
    logger.info("hairstyle catalog: %d styles", len(entries))
    return entries
