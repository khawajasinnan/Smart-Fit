"""Marqo-FashionCLIP (spec §7.1): pretrained, inference only, CPU.

Loaded through open_clip ("hf-hub:Marqo/marqo-fashionCLIP"), which reads the
published weights directly. The spec's transformers snippet needs
trust_remote_code=True, i.e. executing Python downloaded from the model repo;
open_clip gives the same model without that.

Vectors are L2-normalised, so a dot product is the cosine similarity.
"""

from __future__ import annotations

import logging
import os
import threading

import numpy as np
from PIL import Image

from shared.config import settings

logger = logging.getLogger("smartfit.recommendation.embeddings")


class FashionClip:
    def __init__(self, model_name: str | None = None) -> None:
        import open_clip
        import torch

        self.model_name = model_name or settings.fashionclip_model
        self._torch = torch
        if settings.huggingface_token and not os.environ.get("HF_TOKEN"):
            os.environ["HF_TOKEN"] = settings.huggingface_token  # huggingface_hub reads only HF_TOKEN
        self.model, _, self.preprocess = open_clip.create_model_and_transforms(self.model_name)
        self.tokenizer = open_clip.get_tokenizer(self.model_name)
        self.model.eval()
        self._lock = threading.Lock()
        with torch.no_grad():
            self.dim = int(self.model.encode_text(self.tokenizer(["shirt"])).shape[-1])
        logger.info("FashionCLIP loaded (%s, %d-dim)", self.model_name, self.dim)

    def _normalise(self, features) -> np.ndarray:
        features = features / features.norm(dim=-1, keepdim=True)
        return features.cpu().numpy().astype(np.float32)

    def embed_images(self, images: list[Image.Image]) -> np.ndarray:
        if not images:
            return np.zeros((0, self.dim), dtype=np.float32)
        batch = self._torch.stack([self.preprocess(img.convert("RGB")) for img in images])
        with self._lock, self._torch.no_grad():
            return self._normalise(self.model.encode_image(batch))

    def embed_texts(self, texts: list[str]) -> np.ndarray:
        with self._lock, self._torch.no_grad():
            return self._normalise(self.model.encode_text(self.tokenizer(texts)))
