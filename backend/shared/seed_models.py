"""Seed a persistent model folder from the models baked into the image
(spec §23.26). Run before a service starts (a Kubernetes initContainer):

    python -m shared.seed_models <baked dir> <volume dir> <card file name>

* Empty volume (first boot): copy the baked models in.
* The volume's model was trained on a different feature list than this
  release uses (the code changed): replace it with the baked one, keeping
  the volume's history and old versions.
* Otherwise keep what is there: those are the models learned from users.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path


def _features(card: Path) -> list | None:
    try:
        return json.loads(card.read_text(encoding="utf-8")).get("features")
    except (OSError, ValueError, AttributeError):
        return None


def seed(baked: Path, volume: Path, card_name: str) -> str:
    volume.mkdir(parents=True, exist_ok=True)
    live_card = volume / card_name
    if live_card.exists() and _features(live_card) == _features(baked / card_name):
        return "kept the learned models"
    reason = "first boot" if not live_card.exists() else "the feature list changed"
    for item in baked.iterdir():
        if item.is_file() and item.name not in (card_name, "history.json") and not item.name.startswith("."):
            shutil.copy2(item, volume / item.name)
    if (baked / card_name).exists():
        shutil.copy2(baked / card_name, live_card)  # the card last
    return f"seeded from the image ({reason})"


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: python -m shared.seed_models <baked dir> <volume dir> <card file name>")
    print(seed(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]))
