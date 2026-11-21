"""Cached FashionCLIP image embeddings for the catalog (spec §7.2).

Each product image is embedded once and stored in a parquet file
(product_id, image_url, model, vector). On sync, a product is re-embedded
only if it's new or its image_url changed (or the model changed); products
no longer in the catalog are dropped. A brute-force cosine over a few
thousand 512-d vectors takes milliseconds, so no FAISS at this scale.
"""

from __future__ import annotations

import asyncio
import io
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlparse

import httpx
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
from PIL import Image
from starlette.concurrency import run_in_threadpool

from shared.catalog_store import load_products
from shared.config import settings
from shared.schemas.catalog import ScrapedProduct

logger = logging.getLogger("smartfit.recommendation.index")

ALLOWED_IMAGE_HOSTS = {"cdn.shopify.com", "outfitters.com.pk", "www.breakout.com.pk"}
MAX_IMAGE_BYTES = 8_000_000
EMBED_BATCH = 16
DOWNLOAD_CONCURRENCY = 4


class Embedder(Protocol):
    model_name: str
    dim: int

    def embed_images(self, images: list[Image.Image]) -> np.ndarray: ...
    def embed_texts(self, texts: list[str]) -> np.ndarray: ...


@dataclass
class SyncStats:
    products: int = 0
    reused: int = 0
    embedded: int = 0
    failed: int = 0
    dropped: int = 0


async def fetch_image(client: httpx.AsyncClient, url: str) -> Image.Image:
    parsed = urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() not in ALLOWED_IMAGE_HOSTS:
        raise ValueError(f"image host not allowed: {parsed.hostname}")
    res = await client.get(url, timeout=30, follow_redirects=False,
                           headers={"User-Agent": settings.scraper_user_agent})
    res.raise_for_status()
    if len(res.content) > MAX_IMAGE_BYTES:
        raise ValueError("image too large")
    img = Image.open(io.BytesIO(res.content))
    img.load()
    return img.convert("RGB")


class CatalogIndex:
    def __init__(self, cache_path: str | None = None) -> None:
        self.cache_path = Path(cache_path or settings.embedding_cache_path)
        self.products: dict[str, ScrapedProduct] = {}
        self.ids: list[str] = []
        self.matrix = np.zeros((0, 0), dtype=np.float32)
        self._sync_lock = asyncio.Lock()

    def __len__(self) -> int:
        return len(self.ids)

    def _read_cache(self) -> dict[str, tuple[str, str, np.ndarray]]:
        if not self.cache_path.exists():
            return {}
        table = pq.read_table(self.cache_path)
        rows = table.to_pydict()
        return {
            pid: (url, model, np.asarray(vec, dtype=np.float32))
            for pid, url, model, vec in zip(rows["product_id"], rows["image_url"], rows["model"], rows["vector"])
        }

    def _write_cache(self, cache: dict[str, tuple[str, str, np.ndarray]]) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        pids = list(cache)
        table = pa.table({
            "product_id": pids,
            "image_url": [cache[p][0] for p in pids],
            "model": [cache[p][1] for p in pids],
            "vector": [cache[p][2].tolist() for p in pids],
        })
        tmp = self.cache_path.with_suffix(".tmp")
        pq.write_table(table, tmp)
        tmp.replace(self.cache_path)

    async def sync(self, client: httpx.AsyncClient, embedder: Embedder,
                   products: list[ScrapedProduct] | None = None) -> SyncStats:
        """Bring the cache and in-memory matrix in line with the catalog."""
        async with self._sync_lock:
            catalog = products if products is not None else await load_products(client)
            allowed = {r.strip() for r in settings.fashionclip_retailers.split(",") if r.strip()}
            if allowed:
                catalog = [p for p in catalog if p.retailer in allowed]
            cache = self._read_cache()
            stats = SyncStats(products=len(catalog))
            stats.dropped = len(set(cache) - {p.product_id for p in catalog})

            todo = [p for p in catalog
                    if p.product_id not in cache
                    or cache[p.product_id][0] != p.image_url
                    or cache[p.product_id][1] != embedder.model_name]
            stats.reused = len(catalog) - len(todo)

            sem = asyncio.Semaphore(DOWNLOAD_CONCURRENCY)

            async def load(p: ScrapedProduct):
                async with sem:
                    try:
                        return p, await fetch_image(client, p.image_url)
                    except (httpx.HTTPError, ValueError, OSError) as exc:
                        logger.warning("Image failed for %s: %s", p.product_id, exc)
                        return p, None

            for start in range(0, len(todo), EMBED_BATCH):
                loaded = await asyncio.gather(*(load(p) for p in todo[start : start + EMBED_BATCH]))
                ok = [(p, img) for p, img in loaded if img is not None]
                stats.failed += len(loaded) - len(ok)
                if ok:
                    vectors = await run_in_threadpool(embedder.embed_images, [img for _, img in ok])
                    for (p, _), vec in zip(ok, vectors):
                        cache[p.product_id] = (p.image_url, embedder.model_name, vec)
                    stats.embedded += len(ok)

            keep = {p.product_id: p for p in catalog if p.product_id in cache}
            cache = {pid: cache[pid] for pid in keep}
            self._write_cache(cache)
            self.products = keep
            self.ids = list(keep)
            self.matrix = (np.stack([cache[pid][2] for pid in self.ids])
                           if self.ids else np.zeros((0, embedder.dim), dtype=np.float32))
            logger.info("Catalog index synced: %s", stats)
            return stats
