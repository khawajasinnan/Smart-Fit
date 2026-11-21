"""Recommendation service — SRDS SFR-023 (curated, ranked list), SFR-025
(size compatibility), SF-UC-05. Spec §7.

POST /recommend      spec §7.5: FashionCLIP ranking over the scraped catalog
                     (hard filters for gender, budget and size first).
POST /catalog/sync   re-embed new/changed product images (called by the
                     scraper after a catalog refresh; also runs at start-up).
POST /recommend/app  the app's current contract (via /api/v1/scrape/recommend):
                     live keyword search across brands + the scraped catalog. Kept
                     working until the app moves to /recommend.

FashionCLIP loads in the background at start-up; until it is ready,
/recommend answers 503 MODEL_LOADING and /recommend/app is unaffected
(graceful degradation, SRDS §4.3.1).
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import io
import logging
import re
import time
import uuid
from typing import Literal
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import BackgroundTasks, FastAPI, Request
from PIL import Image
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from shared.audience import is_adult_product
from shared.catalog_store import load_products
from shared.config import settings
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.schemas.recommendation import (
    ProductRecommendation,
    Recommendation,
    RecommendRequest,
    RecommendResponse,
    ScrapeRecommendRequest,
    ScrapeRecommendResponse,
)
from shared.service_app import create_service_app
from shared.supabase_client import service_insert
from shared.taxonomy import build_search_context, gender_garment_conflict
from services.recommendation.catalog_index import CatalogIndex, Embedder
from services.recommendation.garment_check import GarmentClassifier
from services.recommendation.gender_check import GenderChecker
from services.recommendation.live_check import live_check
from services.recommendation.local_catalog import catalog_item, is_product_page, local_products
from services.recommendation.ranking import build_query_text, rank
from services.recommendation.keyword_ranking import rank_products
from services.recommendation.size_match import fit_products, user_letter_size
from shared.culture_styles import culture_guide
from services.recommendation.ml import real_feedback
from services.recommendation.ml.features import extract, to_row
from services.recommendation.ml.ranker import MODEL_DIR as LEARNED_MODEL_DIR
from services.recommendation.ml.ranker import LearnedRanker
from shared.model_registry import file_stamp, read_history
from shared.retrain_scheduler import retrain_loop

logger = logging.getLogger("smartfit.recommendation")

_client: httpx.AsyncClient | None = None
_embedder: Embedder | None = None
_index = CatalogIndex()
_model_error: str | None = None

# Catalog fallback for /recommend/app, reloaded at most every CATALOG_TTL_SECONDS.
CATALOG_TTL_SECONDS = 900.0
# The first request after a start waits at most this long for the catalog (gateway gives up at 85 s).
CATALOG_FIRST_WAIT_SECONDS = 45.0
_catalog_items: list[dict] = []
_catalog_task: asyncio.Task | None = None
_catalog_loaded_at: float | None = None


async def _load_model_and_sync() -> None:
    """Background start-up: load FashionCLIP, then embed the catalog."""
    global _embedder, _model_error
    try:
        from services.recommendation.embeddings import FashionClip

        _embedder = await run_in_threadpool(FashionClip)
    except Exception as exc:  # no network / bad weights: the app path keeps working
        _model_error = f"{type(exc).__name__}: {exc}"
        logger.exception("FashionCLIP failed to load")
        return
    try:
        assert _client is not None
        await _index.sync(_client, _embedder)
    except Exception:
        logger.exception("Initial catalog sync failed; POST /catalog/sync to retry")


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    global _client
    _client = httpx.AsyncClient(timeout=settings.scraper_timeout_seconds)
    # warm the catalog cache now, so no user's request waits for it (the 504 of 18 Nov 2026)
    _start_catalog_reload()
    task = asyncio.create_task(_load_model_and_sync()) if settings.fashionclip_autoload else None
    # spec §23.26: learn from real users' feedback on a schedule (0 = off)
    retrain = asyncio.create_task(retrain_loop("services.recommendation.ml.auto_retrain",
                                               settings.auto_retrain_hours))         if settings.auto_retrain_hours > 0 else None
    try:
        yield
    finally:
        for t in (task, retrain, _catalog_task):
            if t is not None:
                t.cancel()
        await _client.aclose()
        _client = None


app = create_service_app(
    "recommendation",
    "SmartFit Recommendation Service",
    "FashionCLIP ranking over the scraped catalog (spec §7) + the app's keyword path (SFR-023..025).",
    lifespan=lifespan,
    health_extra=lambda: {
        "model_loaded": _embedder is not None,
        "model_error": _model_error,
        "catalog_size": len(_index),
    },
)


CANDIDATE_LIMIT = 2000  # catalog matches handed to ranking
LIVE_CHECK_SPARE = 4  # extra candidates checked, so sold-out ones can be replaced
PER_BRAND_FIRST_PASS = 2


def diversify(ranked: list[ProductRecommendation], n: int) -> list[ProductRecommendation]:
    """Best n, at most PER_BRAND_FIRST_PASS per brand first, then by score:
    with dozens of brands one store mustn't fill every slot. A product the
    Random Forest validator rejected (spec §23.25) never takes a brand's
    first-pass slot; it can only fill what is left."""
    first, rest, per_brand = [], [], {}
    for p in ranked:
        if p.validated is False:
            rest.append(p)
            continue
        count = per_brand.get(p.brand, 0)
        (first if count < PER_BRAND_FIRST_PASS else rest).append(p)
        per_brand[p.brand] = count + 1
    picked = first[:n]
    return picked + rest[: n - len(picked)]


def _gender_ok(item: dict, gender: str) -> bool:
    tags = set(item.get("tags") or [])
    return gender == "unisex" or gender in tags or "unisex" in tags


async def _reload_catalog() -> None:
    """Read the whole catalog store into the cache. Never raises: if the store
    can't be read, the FashionCLIP index's copy (or the last good load) stays."""
    global _catalog_items, _catalog_loaded_at
    assert _client is not None, "lifespan not started"
    started = time.monotonic()
    try:
        products = await load_products(_client)
    except Exception as exc:  # store down: never fail the chat because of the catalog
        logger.warning("Catalog store unavailable (%s) — using the cached catalog", type(exc).__name__)
        products = list(_index.products.values())
        if not products:
            _catalog_loaded_at = time.monotonic()  # don't hammer a down store on every request
            return
    _catalog_items = [catalog_item(p) for p in products]
    _catalog_loaded_at = time.monotonic()
    logger.info("Catalog loaded: %d products in %.1f s", len(_catalog_items), _catalog_loaded_at - started)


def _start_catalog_reload() -> asyncio.Task:
    """One shared reload at a time, however many requests arrive meanwhile."""
    global _catalog_task
    if _catalog_task is None or _catalog_task.done():
        _catalog_task = asyncio.create_task(_reload_catalog())
    return _catalog_task


async def catalog_fallback_items() -> list[dict]:
    """Scraped catalog products in the keyword-ranking shape, cached.

    A user's request never waits for a reload once a catalog is cached: when
    the cache is older than CATALOG_TTL_SECONDS the cached copy is served and
    a fresh one loads in the background (loading 25k products used to block
    the request every 15 min, and a slow store made the gateway answer 504).
    Only the very first request after a start (normally the start-up warm-up
    has finished by then) waits for the load, at most CATALOG_FIRST_WAIT_SECONDS."""
    fresh = _catalog_loaded_at is not None and time.monotonic() - _catalog_loaded_at < CATALOG_TTL_SECONDS
    if fresh:
        return _catalog_items
    task = _start_catalog_reload()
    if _catalog_items:
        return _catalog_items  # stale while the background reload runs
    try:
        await asyncio.wait_for(asyncio.shield(task), timeout=CATALOG_FIRST_WAIT_SECONDS)
    except TimeoutError:
        logger.warning("Catalog still loading after %.0f s; answering from what is ready", CATALOG_FIRST_WAIT_SECONDS)
    return _catalog_items or [catalog_item(p) for p in _index.products.values()]


async def recommend_products(request: ScrapeRecommendRequest,
                             impressions: list[tuple[str, int, list[float]]] | None = None) -> ScrapeRecommendResponse:
    """`impressions`, when given, receives (product id, rank, model inputs) for
    each product shown by the learned ranker (spec §23.26 self-learning)."""
    profile = request.profile
    context = build_search_context(
        profile,
        request.user_message,
        request.assistant_message,
        request.chat_context,
        request.dynamic_prefs,
    )
    if request.taste is not None:
        context["taste"] = request.taste.model_dump()
    context["occasion"] = request.dynamic_prefs.get("occasion")
    # Nothing asked for at all: browse the whole catalog for this profile.
    context["browse"] = not request.user_message.strip() and not context.get("detected_garment")
    gender = context["gender"]
    query = context["search_query"]
    exact_category = context.get("exact_category")
    # No garment named (e.g. Home's "Trending for you"): use the profile-based query.
    detected_garment = context.get("detected_garment") or query or "outfits"

    conflict = gender_garment_conflict(gender, exact_category or "") or gender_garment_conflict(
        gender, detected_garment
    )
    if conflict:
        return ScrapeRecommendResponse(
            products=[],
            search_query=context.get("search_queries", [""])[0] if context.get("search_queries") else "",
            brands_searched=[],
            stylist_message=conflict["message"]
            + " Suggested alternatives: "
            + ", ".join(conflict["alternatives"])
            + ".",
        )

    if context.get("invalid_budget"):
        return ScrapeRecommendResponse(
            products=[],
            search_query=query,
            brands_searched=[],
            message=(
                "Budget cannot be a negative amount. Please enter a positive "
                "PKR budget, for example 5000 PKR."
            ),
        )

    max_total = min(request.max_products, settings.max_total_products)
    catalog = await catalog_fallback_items()
    # Every catalog product that fits the request (gender, garment, budget,
    # colour, brand), then the best ones; the catalog is synced from every
    # feed brand every few hours (spec §23.12).
    raw = local_products(profile, context, CANDIDATE_LIMIT, catalog)

    # "View on store" must open the exact product, never a home/collection page;
    # and SmartFit is for adults: children's wear never reaches the app.
    raw = [p for p in raw if is_product_page(p.get("product_url") or "") and is_adult_product(p)]
    raw = everyday_filter(raw, context, max_total)
    # only products made and in stock in the user's size, each with its own size label (size_match.py)
    raw, size_dropped = fit_products(raw, profile, context.get("requested_size"))

    logger.info("Catalog matches: %d of %d — ranking top %d", len(raw), len(catalog), max_total)
    best = diversify(rank_candidates(raw, profile, context), max_total + LIVE_CHECK_SPARE)
    assert _client is not None, "lifespan not started"
    ranked = await live_check(_client, best, max_total, user_agent=settings.scraper_user_agent) \
        if settings.live_check_enabled else best[:max_total]
    # A budget named in the chat is a hard limit, whatever happened above
    # (ranking, live price check): nothing over it is ever shown.
    if context.get("budget_max"):
        ranked = [r for r in ranked if not r.price_pkr or r.price_pkr <= context["budget_max"]]
    brands = sorted({p["brand"] for p in catalog if _gender_ok(p, gender)})
    if impressions is not None and ranked and ranked[0].ranking_model != "rules":
        by_id = {p.get("id"): p for p in raw}
        impressions.extend((r.id, i, to_row(extract(by_id[r.id], profile, context)))
                           for i, r in enumerate(ranked, start=1) if r.id in by_id)

    message = (
        f"Found {len(ranked)} items from Pakistani brands matching "
        f'"{detected_garment}" for your profile.'
        if ranked
        else f'No products matched "{detected_garment}" right now. '
        "Try describing a different style, garment, or occasion."
    )
    pmax = context.get("profile_budget_max")
    if ranked and not context.get("budget_max") and pmax and all((p.price_pkr or 0) > pmax for p in ranked):
        message += (f" They're above your usual budget of PKR {int(pmax):,}; "
                    "tell me a budget and I'll show only items under it.")
    if not ranked and context.get("budget_max"):
        message = _over_budget_message(profile, context, catalog, detected_garment) or message
    elif not ranked and size_dropped:
        size = user_letter_size(profile, context.get("requested_size"))
        message = (f'No {detected_garment} in your size ({size}) right now: the ones that match are sold out '
                   "or not made in it. Try another style or colour.")

    return ScrapeRecommendResponse(
        products=ranked,
        search_query=query,
        brands_searched=brands,
        message=message,
    )


_BRIDAL = re.compile(r"\b(bridal|bride|brides|dulhan|nikah|nikkah|baraat|barat|walima|peshwas|lehenga|lehnga|"
                     r"sherwani|groom)\b")
PROFILE_BUDGET_STRETCH = 3.0  # without a chat budget, items over 3x the profile budget are left out ...


def everyday_filter(raw: list[dict], context: dict, wanted: int) -> list[dict]:
    """Bridal / wedding-party wear only when the user asks for it (a casual or
    unspecified request never shows a PKR 500,000 bridal set), and, when no
    budget was named in the chat, nothing far above the profile budget, as long
    as enough items within it remain."""
    asked = f"{context.get('combined_text') or ''} {context.get('exact_category') or ''} {context.get('occasion') or ''}".lower()
    if not _BRIDAL.search(asked.replace("-", " ")):
        raw = [p for p in raw if not _BRIDAL.search(f"{p.get('title') or ''} {p.get('category') or ''}".lower())]
    pmax = context.get("profile_budget_max")
    if pmax and not context.get("budget_max"):
        within = [p for p in raw if not p.get("price_pkr") or p["price_pkr"] <= pmax * PROFILE_BUDGET_STRETCH]
        if len(within) >= wanted:  # ... unless that would leave too few to show
            raw = within
    return raw


def rank_candidates(raw: list[dict], profile, context: dict) -> list[ProductRecommendation]:
    """Rules filter (hard exclusions), then the learned models rank, validate
    and explain (spec §23.25); rule order when the models aren't trained."""
    ranked = rank_products(raw, profile, context, len(raw))
    learned = _learned_ranker() if settings.learned_ranking_enabled else None
    if learned is None:
        return ranked
    try:
        return learned.rerank(raw, ranked, profile, context)
    except Exception:  # a broken model must never take recommendations down
        logger.exception("Learned ranking failed; using rule ranking")
        return ranked


_ranker_cache: list[LearnedRanker | None] = []
_ranker_stamp: list[float | None] = []


def _learned_ranker() -> LearnedRanker | None:
    """The live models. Reloaded when the model card changes, so a model the
    self-learning job promotes (spec §23.26) is used without a restart."""
    stamp = file_stamp(LEARNED_MODEL_DIR / "model_card.json")
    if not _ranker_cache or (_ranker_stamp and stamp != _ranker_stamp[0]):
        _ranker_cache[:] = [LearnedRanker.load(LEARNED_MODEL_DIR)]
        _ranker_stamp[:] = [stamp]
        if _ranker_cache[0] is not None:
            logger.info("Recommendation models loaded (version %s)", _ranker_cache[0].card.get("version"))
    return _ranker_cache[0]


def _over_budget_message(profile, context: dict, catalog: list[dict], garment: str) -> str | None:
    """Nothing under the budget asked for: say what the cheapest real match
    costs instead of a bare "no products" (the budget stays a hard limit)."""
    loose = {**context, "budget_min": None, "budget_max": None}
    matches = [p for p in local_products(profile, loose, CANDIDATE_LIMIT, catalog)
               if is_product_page(p.get("product_url") or "") and is_adult_product(p) and p.get("price_pkr")]
    if not matches:
        return None
    cheapest = min(matches, key=lambda p: p["price_pkr"])
    return (f'No {garment} under PKR {int(context["budget_max"]):,} right now. '
            f'The most affordable one is PKR {int(cheapest["price_pkr"]):,} at {cheapest["brand"]} '
            f"({len(matches)} options in total). Raise your budget a little and I'll show them.")


async def log_recommendation_event(user_id: str | None, product_ids: list[str], latency_ms: int, model: str) -> None:
    """Analytics row for the admin dashboard (SFR-041). Best effort: never
    affects the user's response; skipped when Supabase isn't configured."""
    if not (settings.supabase_url and settings.supabase_service_key) or _client is None:
        return
    try:
        valid_user = str(uuid.UUID(user_id)) if user_id else None
    except ValueError:
        valid_user = None
    try:
        await service_insert(_client, "recommendation_events", {
            "user_id": valid_user, "product_ids": product_ids, "latency_ms": latency_ms, "model": model,
        })
    except Exception as exc:  # analytics must never break recommendations
        logger.info("recommendation event not logged (%s)", exc)


async def log_impressions(user_id: str | None, rows: list[tuple[str, int, list[float]]]) -> None:
    """What the learned ranker showed a signed-in user, for self-learning
    (spec §23.26). Best effort, after the response; never for guests."""
    if not (settings.impression_logging_enabled and settings.supabase_url and settings.supabase_service_key):
        return
    if _client is None or not user_id:
        return
    try:
        valid_user = str(uuid.UUID(user_id))
    except ValueError:
        return
    learned = _ranker_cache[0] if _ranker_cache else None
    version = str((learned.card.get("version") or learned.card.get("trained_at")) if learned else "unknown")
    try:
        await real_feedback.log_impressions(_client, valid_user, rows, version)
    except Exception as exc:  # learning data must never break recommendations
        logger.info("impressions not logged (%s)", exc)


@app.get("/ml/status")
async def ml_status() -> dict:
    """The live recommendation models and the last self-learning attempts."""
    learned = _learned_ranker()
    card = learned.card if learned else None
    return {
        "learned_ranking_enabled": settings.learned_ranking_enabled,
        "live_model": None if card is None else {
            k: card.get(k) for k in ("version", "trained_at", "label_source", "rows", "real_training_rows",
                                     "metrics", "real_holdout")},
        "auto_retrain_every_hours": settings.auto_retrain_hours,
        "min_new_reactions": settings.auto_retrain_min_feedback,
        "history": read_history(LEARNED_MODEL_DIR),
    }


@app.get("/culture/guide")
async def culture_guide_route(culture: str = "", gender: str = "") -> dict:
    """The outfit guide for a profile's culture (shared/culture_styles.py; 21 Nov 2026).
    {"guide": null} when the culture isn't one of the guide's."""
    return {"guide": culture_guide(culture, gender)}


@app.post("/recommend/app", response_model=ScrapeRecommendResponse)
async def recommend_app(
    body: ScrapeRecommendRequest, request: Request, background: BackgroundTasks
) -> ScrapeRecommendResponse:
    started = time.perf_counter()
    shown: list[tuple[str, int, list[float]]] = []
    result = await recommend_products(body, shown)
    if shown:
        background.add_task(log_impressions, request.headers.get("x-user-id"), shown)
    background.add_task(
        log_recommendation_event,
        request.headers.get("x-user-id"),
        [p.id for p in result.products],
        int((time.perf_counter() - started) * 1000),
        "keyword+catalog",
    )
    return result


def _require_model() -> Embedder:
    if _embedder is None:
        if _model_error:
            raise AppError(503, "MODEL_UNAVAILABLE", "Recommendations are temporarily unavailable.")
        raise AppError(503, "MODEL_LOADING", "Recommendations are starting up. Please try again in a moment.")
    return _embedder


@app.post("/recommend", response_model=RecommendResponse, responses={503: {"model": ErrorEnvelope}})
async def recommend(body: RecommendRequest) -> RecommendResponse:
    embedder = _require_model()
    query_text = build_query_text(body.profile, body.session_inputs, body.cv_analysis)
    query_vector = (await run_in_threadpool(embedder.embed_texts, [query_text]))[0]
    products = [_index.products[pid] for pid in _index.ids]
    rows, removed = rank(
        products,
        _index.matrix,
        query_vector,
        gender=body.profile.gender,
        size=body.cv_analysis.estimated_size,
        budget_max=body.session_inputs.budget_max,
        top_n=body.top_n or settings.recommend_top_n,
        body={"chest_cm": body.profile.chest_cm, "waist_cm": body.profile.waist_cm, "hip_cm": body.profile.hip_cm},
    )
    return RecommendResponse(
        recommendations=[
            Recommendation(
                product_id=p.product_id,
                name=p.name,
                image_url=p.image_url,
                price=p.price,
                similarity_score=round(score, 4),
                available_sizes=p.sizes,
                product_url=p.product_url,
                retailer=p.retailer,
                category=p.category,
                tryon_category=p.tryon_category,
                size_compatible=fit.compatible,
                recommended_size=fit.recommended_size,
                size_basis=fit.basis,
                size_note=fit.note,
            )
            for p, score, fit in rows
        ],
        query_text=query_text,
        catalog_size=len(products),
        filtered_out=dict(removed),
    )


class GarmentCheckRequest(BaseModel):
    image_base64: str = Field(min_length=100, max_length=20_000_000)


class GarmentCheckResponse(BaseModel):
    scores: dict[str, float]  # upper / lower / dress / other, summing to 1
    best: str
    sleeve: str | None = None  # "long sleeve" / "short sleeve" / "sleeveless"; None = not sure
    sleeve_probability: float = 0.0


_garment_classifier: GarmentClassifier | None = None


@app.post("/garment/check", response_model=GarmentCheckResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def garment_check(body: GarmentCheckRequest) -> GarmentCheckResponse:
    """What kind of garment is in this photo (try-on with the user's own clothes)?"""
    global _garment_classifier
    embedder = _require_model()
    try:
        raw = base64.b64decode(body.image_base64.split(",", 1)[-1], validate=False)
        image = Image.open(io.BytesIO(raw))
        image.load()
    except (binascii.Error, ValueError, OSError, Image.DecompressionBombError) as exc:
        raise AppError(422, "INVALID_IMAGE", "That clothes photo couldn't be read.") from exc
    if _garment_classifier is None or getattr(_garment_classifier, "_embedder", None) is not embedder:
        _garment_classifier = await run_in_threadpool(GarmentClassifier, embedder)
    scores, sleeve, sleeve_p = await run_in_threadpool(_garment_classifier.check, image.convert("RGB"))
    return GarmentCheckResponse(scores=scores, best=max(scores, key=scores.__getitem__), sleeve=sleeve,
                                sleeve_probability=sleeve_p)


class GenderCheckRequest(BaseModel):
    image_base64: str = Field(min_length=100, max_length=20_000_000)
    kind: Literal["garment", "face"]
    # face only: the whole photo the head was cropped from, as a second opinion
    photo_base64: str | None = Field(default=None, min_length=100, max_length=20_000_000)


class GenderCheckResponse(BaseModel):
    label: str | None  # garment: men / women; face: man / woman; None = not sure
    probability: float
    available: bool  # False: the model for this check isn't installed (the check is skipped)


_gender_checker = None


@app.post("/gender/check", response_model=GenderCheckResponse,
          responses={422: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def gender_check(body: GenderCheckRequest) -> GenderCheckResponse:
    """Is this garment menswear or womenswear / is this a man or a woman (a head
    crop)? Used by the try-on so men's clothes go on men and women's on women."""
    global _gender_checker
    embedder = _require_model()

    def read(b64: str) -> Image.Image:
        try:
            image = Image.open(io.BytesIO(base64.b64decode(b64.split(",", 1)[-1], validate=False)))
            image.load()
            return image
        except (binascii.Error, ValueError, OSError, Image.DecompressionBombError) as exc:
            raise AppError(422, "INVALID_IMAGE", "That photo couldn't be read.") from exc

    image = read(body.image_base64)
    photo = read(body.photo_base64) if body.kind == "face" and body.photo_base64 else None
    if _gender_checker is None or getattr(_gender_checker, "_embedder", None) is not embedder:
        _gender_checker = await run_in_threadpool(GenderChecker, embedder)
    if body.kind == "face":
        v = await run_in_threadpool(_gender_checker.check_person, image, photo)
    else:
        v = await run_in_threadpool(_gender_checker.check, image, body.kind)
    return GenderCheckResponse(label=v.label, probability=v.probability, available=v.available)


@app.post("/catalog/sync")
async def catalog_sync() -> dict:
    embedder = _require_model()
    assert _client is not None, "lifespan not started"
    stats = await _index.sync(_client, embedder)
    return stats.__dict__
