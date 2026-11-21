"""Where the product catalog lives (spec §10: Supabase `products` table).

* SUPABASE_SERVICE_KEY set -> the `products` table (migration
  20261023000100_products_catalog.sql).
* Not set (local development before the key/migration exist) -> a JSONL
  snapshot at CATALOG_SNAPSHOT_PATH. Same rows, same schema.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

import httpx

from shared.config import settings
from shared.schemas.catalog import ScrapedProduct
from shared.supabase_client import service_delete, service_select, service_upsert

logger = logging.getLogger("smartfit.catalog")

PRODUCTS_TABLE = "products"
PAGE_ROWS = 1000  # PostgREST's maximum rows per request; load_products pages through all
PARALLEL_PAGES = 6  # pages fetched at once by load_products


def uses_supabase() -> bool:
    if settings.catalog_store == "snapshot":
        return False
    if settings.catalog_store == "supabase":
        return True  # fails loudly (CONFIG_MISSING) if the key isn't set
    return bool(settings.supabase_url and settings.supabase_service_key)


def _snapshot() -> Path:
    return Path(settings.catalog_snapshot_path)


def _read_snapshot() -> dict[str, ScrapedProduct]:
    path = _snapshot()
    if not path.exists():
        return {}
    products = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            p = ScrapedProduct.model_validate_json(line)
            products[p.product_id] = p
    return products


async def save_products(client: httpx.AsyncClient, products: list[ScrapedProduct]) -> str:
    """Upsert by product_id. Returns where they went ("supabase" | "snapshot")."""
    if not products:
        return "supabase" if uses_supabase() else "snapshot"
    if uses_supabase():
        rows = [p.model_dump(mode="json") for p in products]
        for i in range(0, len(rows), 200):
            await service_upsert(client, PRODUCTS_TABLE, rows[i : i + 200], on_conflict="product_id")
        return "supabase"
    merged = _read_snapshot()
    merged.update({p.product_id: p for p in products})
    path = _snapshot()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(p.model_dump_json() for p in merged.values()) + "\n", encoding="utf-8")
    tmp.replace(path)
    return "snapshot"


async def load_products(client: httpx.AsyncClient) -> list[ScrapedProduct]:
    """The whole catalog (paged: PostgREST returns at most PAGE_ROWS per request).

    Pages are fetched PARALLEL_PAGES at a time: one after another, 25k
    products took ~47 s (18 Nov 2026), long enough for a user's request to
    hit the gateway's timeout (504); in parallel it takes a few seconds."""
    if uses_supabase():
        async def page(offset: int) -> list[dict]:
            return await service_select(client, PRODUCTS_TABLE, {
                "select": "*", "order": "product_id.asc", "limit": str(PAGE_ROWS), "offset": str(offset)})

        by_id: dict[str, ScrapedProduct] = {}
        offset = 0
        while True:
            pages = await asyncio.gather(*(page(offset + i * PAGE_ROWS) for i in range(PARALLEL_PAGES)))
            for rows in pages:
                for r in rows:  # by id: a refresh writing meanwhile can shift a row across pages
                    p = ScrapedProduct.model_validate(r)
                    by_id[p.product_id] = p
            if any(len(rows) < PAGE_ROWS for rows in pages):
                return list(by_id.values())
            offset += PARALLEL_PAGES * PAGE_ROWS
    return list(_read_snapshot().values())


async def remove_stale_feed_products(client: httpx.AsyncClient, retailer: str, keep_ids: set[str], before) -> int:
    """After a brand's successful refresh: delete its feed products that weren't
    in it (sold out, removed, or no longer among the newest). Admin-added and
    CSV-imported products are never touched. `before` is the refresh's
    scraped_at; every product it kept was saved with that time."""
    if uses_supabase():
        return await service_delete(client, PRODUCTS_TABLE, {
            "retailer": f"eq.{retailer}", "source": "eq.shopify_feed",
            "scraped_at": f"lt.{before.isoformat()}"})
    products = _read_snapshot()
    stale = [pid for pid, p in products.items()
             if p.retailer == retailer and p.source == "shopify_feed" and pid not in keep_ids]
    if not stale:
        return 0
    for pid in stale:
        del products[pid]
    path = _snapshot()
    tmp = path.with_suffix(".tmp")
    tmp.write_text("".join(p.model_dump_json() + "\n" for p in products.values()), encoding="utf-8")
    tmp.replace(path)
    return len(stale)


async def get_product(client: httpx.AsyncClient, product_id: str) -> ScrapedProduct | None:
    if uses_supabase():
        rows = await service_select(client, PRODUCTS_TABLE, {"select": "*", "product_id": f"eq.{product_id}"})
        return ScrapedProduct.model_validate(rows[0]) if rows else None
    return _read_snapshot().get(product_id)


async def delete_product(client: httpx.AsyncClient, product_id: str) -> bool:
    """True if it existed. A feed product comes back on the retailer's next refresh."""
    if uses_supabase():
        return await service_delete(client, PRODUCTS_TABLE, {"product_id": f"eq.{product_id}"}) > 0
    products = _read_snapshot()
    if products.pop(product_id, None) is None:
        return False
    path = _snapshot()
    tmp = path.with_suffix(".tmp")
    tmp.write_text("".join(p.model_dump_json() + "\n" for p in products.values()), encoding="utf-8")
    tmp.replace(path)
    return True


def describe_store() -> str:
    return f"Supabase table '{PRODUCTS_TABLE}'" if uses_supabase() else f"local snapshot {_snapshot()}"
