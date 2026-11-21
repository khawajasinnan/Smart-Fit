"""Catalog management for the admin panel (SFR-040).

Internal endpoints: the gateway calls them only after checking the caller is
an admin. They work on whichever catalog store is active (Supabase or the
local snapshot). After a change the recommendation service is asked to
re-sync its embedding cache (best effort, in the background).
"""

from __future__ import annotations

from typing import Literal

import httpx
from fastapi import APIRouter, BackgroundTasks, Query
from pydantic import BaseModel, Field

from shared.catalog_store import delete_product, get_product, load_products, save_products
from shared.schemas.catalog import ScrapedProduct
from shared.schemas.errors import AppError
from services.scraper.catalog_service import notify_recommendation
from services.scraper.manual_import import RETAILER_HOSTS, parse_manual_csv, product_from_fields

router = APIRouter(prefix="/catalog", tags=["catalog admin"])

EDITABLE = ("name", "image_url", "extra_image_urls", "price", "sizes_in_stock", "all_sizes", "category",
            "tryon_category", "gender", "colors")


class ProductFields(BaseModel):
    name: str
    image_url: str
    extra_image_urls: list[str] = Field(default_factory=list)
    price: float
    sizes_in_stock: list[str] = Field(default_factory=list)
    all_sizes: list[str] = Field(default_factory=list)
    category: str
    tryon_category: Literal["upper", "lower", "dress"]
    gender: Literal["men", "women", "unisex"]
    colors: list[str] = Field(default_factory=list)


class NewProduct(ProductFields):
    retailer: Literal["outfitters", "breakout"]
    product_url: str


class ProductPatch(BaseModel):
    name: str | None = None
    image_url: str | None = None
    extra_image_urls: list[str] | None = None
    price: float | None = None
    sizes_in_stock: list[str] | None = None
    all_sizes: list[str] | None = None
    category: str | None = None
    tryon_category: Literal["upper", "lower", "dress"] | None = None
    gender: Literal["men", "women", "unisex"] | None = None
    colors: list[str] | None = None


class CsvImport(BaseModel):
    retailer: Literal["breakout"]
    csv_text: str = Field(max_length=2_000_000)


def _fields_of(p: ScrapedProduct) -> dict:
    return {
        "name": p.name, "product_url": p.product_url, "image_url": p.image_url,
        "extra_image_urls": [u for u in p.image_urls if u != p.image_url], "price": p.price,
        "sizes_in_stock": p.sizes, "all_sizes": p.all_sizes, "category": p.category,
        "tryon_category": p.tryon_category, "gender": p.gender, "colors": p.colors,
    }


def _summary(p: ScrapedProduct) -> dict:
    return {
        "product_id": p.product_id, "retailer": p.retailer, "name": p.name, "product_url": p.product_url,
        "image_url": p.image_url, "price": p.price, "sizes": p.sizes, "all_sizes": p.all_sizes,
        "category": p.category, "tryon_category": p.tryon_category, "gender": p.gender, "colors": p.colors,
        "has_size_chart": bool(p.size_chart), "source": p.source, "scraped_at": p.scraped_at.isoformat(),
    }


async def _resync() -> None:
    async with httpx.AsyncClient() as client:
        await notify_recommendation(client)


@router.get("/products")
async def list_products(
    search: str = "",
    retailer: str = "",
    tryon_category: str = "",
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> dict:
    async with httpx.AsyncClient() as client:
        products = await load_products(client)
    term = search.strip().lower()
    hits = [
        p for p in products
        if (not retailer or p.retailer == retailer)
        and (not tryon_category or p.tryon_category == tryon_category)
        and (not term or term in p.name.lower() or term in p.category.lower() or term in p.product_id.lower())
    ]
    hits.sort(key=lambda p: p.scraped_at, reverse=True)
    start = (page - 1) * page_size
    return {"items": [_summary(p) for p in hits[start:start + page_size]], "total": len(hits),
            "page": page, "page_size": page_size,
            "by_retailer": {r: sum(1 for p in products if p.retailer == r) for r in RETAILER_HOSTS}}


@router.post("/products", status_code=201)
async def add_product(body: NewProduct, background: BackgroundTasks) -> dict:
    product, problem = product_from_fields(body.model_dump(), body.retailer, "admin")
    if problem:
        raise AppError(400, "INVALID_PRODUCT", problem)
    async with httpx.AsyncClient() as client:
        if await get_product(client, product.product_id):
            raise AppError(409, "ALREADY_EXISTS", "That product is already in the catalog; edit it instead.")
        await save_products(client, [product])
    background.add_task(_resync)
    return _summary(product)


@router.patch("/products/{product_id}")
async def edit_product(product_id: str, body: ProductPatch, background: BackgroundTasks) -> dict:
    async with httpx.AsyncClient() as client:
        existing = await get_product(client, product_id)
        if existing is None:
            raise AppError(404, "NOT_FOUND", "That product isn't in the catalog.")
        fields = _fields_of(existing) | body.model_dump(exclude_none=True)
        product, problem = product_from_fields(fields, existing.retailer, existing.source)
        if problem:
            raise AppError(400, "INVALID_PRODUCT", problem)
        product = product.model_copy(update={
            "size_chart_tag": existing.size_chart_tag, "size_chart": existing.size_chart,
            "size_chart_raw": existing.size_chart_raw,
        })
        await save_products(client, [product])
    background.add_task(_resync)
    return _summary(product)


@router.delete("/products/{product_id}")
async def remove_product(product_id: str, background: BackgroundTasks) -> dict:
    async with httpx.AsyncClient() as client:
        if not await delete_product(client, product_id):
            raise AppError(404, "NOT_FOUND", "That product isn't in the catalog.")
    background.add_task(_resync)
    return {"deleted": product_id}


@router.post("/import-csv")
async def import_csv(body: CsvImport, background: BackgroundTasks) -> dict:
    products, problems = parse_manual_csv(body.csv_text, body.retailer)
    async with httpx.AsyncClient() as client:
        stored_in = await save_products(client, products)
    if products:
        background.add_task(_resync)
    return {"stored": len(products), "stored_in": stored_in, "problems": problems}
