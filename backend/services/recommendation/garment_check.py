"""What is in a clothes photo? (try-on with the user's own clothes)

Zero-shot FashionCLIP: the photo's image vector is compared with short text
descriptions of tops, bottoms, full outfits and things that aren't clothing.
The probabilities of each group's descriptions are summed, so "kurta" and
"t-shirt" both count for "upper". Used by the try-on service to refuse a
photo of shoes or a bag, and to catch an obvious type mix-up (trousers
chosen as a "Top") before any GPU time is spent.
"""

from __future__ import annotations

import numpy as np
from PIL import Image

from services.recommendation.catalog_index import Embedder

PROMPTS: dict[str, list[str]] = {
    "upper": [
        "a photo of a shirt", "a photo of a t-shirt", "a photo of a polo shirt", "a photo of a kurta",
        "a photo of a jacket", "a photo of a hoodie", "a photo of a sweater", "a photo of a blouse",
        "a photo of a women's top", "a photo of a waistcoat",
    ],
    "lower": [
        "a photo of trousers", "a photo of jeans", "a photo of a skirt", "a photo of shorts",
        "a photo of a shalwar", "a photo of joggers", "a photo of leggings",
    ],
    "dress": [
        "a photo of a dress", "a photo of a long frock", "a photo of a jumpsuit",
        "a photo of a shalwar kameez suit", "a photo of a maxi dress", "a photo of an abaya",
    ],
    "other": [
        "a photo of shoes", "a photo of sneakers", "a photo of sandals", "a photo of a handbag",
        "a photo of jewellery", "a photo of a watch", "a photo of a cap", "a photo of sunglasses",
        "a photo of a perfume bottle", "a photo of furniture", "a photo of food", "a photo of an animal",
        "a photo of a car", "a screenshot of text", "a photo of a landscape",
    ],
}
GROUPS = tuple(PROMPTS)

# Sleeve length, in IDM-VTON's own caption words (its training captions are
# "<sleeve length> <neckline> <item>"). Measured 20 Nov 2026 on 210 catalog
# try-on photos whose names state the sleeve length: 98.6 % right; at
# SLEEVE_MIN 0.8 it is sure on 97 % and right on 99.5 % of those.
SLEEVE_PROMPTS: dict[str, list[str]] = {
    "long sleeve": ["a photo of a long sleeve shirt", "a photo of a long sleeve kurta",
                    "a photo of a long sleeve dress"],
    "short sleeve": ["a photo of a short sleeve shirt", "a photo of a short sleeve kurta",
                     "a photo of a short sleeve dress"],
    "sleeveless": ["a photo of a sleeveless shirt", "a photo of a sleeveless kurta",
                   "a photo of a sleeveless dress"],
}
SLEEVE_MIN = 0.8
# CLIP's usual logit scale: turns cosine similarities into a sharp softmax.
LOGIT_SCALE = 100.0


class GarmentClassifier:
    def __init__(self, embedder: Embedder) -> None:
        self._embedder = embedder
        self._labels = [g for g in GROUPS for _ in PROMPTS[g]]
        self._text = embedder.embed_texts([p for g in GROUPS for p in PROMPTS[g]])
        self._sleeve_labels = [s for s in SLEEVE_PROMPTS for _ in SLEEVE_PROMPTS[s]]
        self._sleeve_text = embedder.embed_texts([p for s in SLEEVE_PROMPTS for p in SLEEVE_PROMPTS[s]])

    @staticmethod
    def _grouped(text: np.ndarray, labels: list[str], vec: np.ndarray, groups) -> dict[str, float]:
        logits = LOGIT_SCALE * (text @ vec)
        probs = np.exp(logits - logits.max())
        probs /= probs.sum()
        out = {g: 0.0 for g in groups}
        for label, p in zip(labels, probs, strict=True):
            out[label] += float(p)
        return {g: round(v, 4) for g, v in out.items()}

    def scores(self, image: Image.Image) -> dict[str, float]:
        """{"upper": p, "lower": p, "dress": p, "other": p}, summing to 1."""
        return self.check(image)[0]

    def check(self, image: Image.Image) -> tuple[dict[str, float], str | None, float]:
        """(kind scores, sleeve length or None when not sure, its probability) from one image vector."""
        vec = self._embedder.embed_images([image])[0]
        kinds = self._grouped(self._text, self._labels, vec, GROUPS)
        sleeves = self._grouped(self._sleeve_text, self._sleeve_labels, vec, SLEEVE_PROMPTS)
        best = max(sleeves, key=sleeves.__getitem__)
        return kinds, (best if sleeves[best] >= SLEEVE_MIN else None), sleeves[best]
