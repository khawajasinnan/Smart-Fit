"""Menswear or womenswear? A man or a woman in the photo? (try-on check, 18 Nov 2026)

Two small logistic regressions on FashionCLIP image embeddings, trained and
measured by scripts/train_gender_checks.py (garment: catalog photos labelled
by the brands' feeds; face: CelebAMask-HQ). Each was saved with a threshold
per side that keeps its confident answers right at least 97 % of the time on
held-out data; anything below it is "not sure" and never blocks a try-on.

A person (19 Nov 2026) is judged from the face AND the whole photo: the face
model gives the answer, and the garment model run on the full photo (clothes,
hair, figure) must point the same way, otherwise the answer is "not sure".
Measured on real photos: 72/72 men and 50/52 women sure, 0 wrong.

This is about clothes and their usual wearer, not identity: the answer only
decides whether a garment is tried on, it is never stored or shown as a
judgement about the person.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np
from PIL import Image

logger = logging.getLogger("smartfit.recommendation.gender")

MODEL_DIR = Path(__file__).resolve().parent / "models" / "gender"
Kind = Literal["garment", "face"]


@dataclass
class GenderVerdict:
    label: str | None  # garment: "men" / "women"; face: "man" / "woman"; None = not sure
    probability: float  # of the label (or of the likelier one when not sure)
    available: bool = True


class GenderChecker:
    def __init__(self, embedder, model_dir: Path = MODEL_DIR) -> None:
        import joblib

        self._embedder = embedder
        self._models: dict[str, dict] = {}
        for kind in ("garment", "face"):
            path = model_dir / f"{kind}_gender.joblib"
            if path.exists():
                self._models[kind] = joblib.load(path)
            else:
                logger.warning("%s gender model missing (%s): that check is skipped", kind, path)

    def available(self, kind: Kind) -> bool:
        return kind in self._models

    def check(self, image: Image.Image, kind: Kind) -> GenderVerdict:
        bundle = self._models.get(kind)
        if bundle is None:
            return GenderVerdict(None, 0.5, available=False)
        vec = self._embedder.embed_images([image.convert("RGB")])
        p = float(bundle["model"].predict_proba(np.asarray(vec))[0, 1])  # P(second label)
        labels = bundle["labels"]
        # One threshold per side (older bundles: one for both).
        t0, t1 = (float(t) for t in bundle.get("thresholds", (bundle["threshold"], bundle["threshold"])))
        if p >= t1:
            return GenderVerdict(labels[1], round(p, 4))
        if 1 - p >= t0:
            return GenderVerdict(labels[0], round(1 - p, 4))
        return GenderVerdict(None, round(max(p, 1 - p), 4))

    def check_person(self, head: Image.Image, photo: Image.Image | None) -> GenderVerdict:
        """Man or woman: the face model's confident answer, kept only when the
        whole photo (garment model: womenswear / menswear look) agrees.
        Without the photo or the garment model, the face answer stands alone."""
        face = self.check(head, "face")
        bundle = self._models.get("garment")
        if face.label is None or photo is None or bundle is None:
            return face
        vec = self._embedder.embed_images([photo.convert("RGB")])
        p_women = float(bundle["model"].predict_proba(np.asarray(vec))[0, 1])
        body = "woman" if p_women >= 0.5 else "man"
        if body != face.label:
            logger.info("face says %s but the whole photo looks like %s: not sure", face.label, body)
            return GenderVerdict(None, face.probability)
        return face
