"""Virtual try-on service — SRDS SFR-026 (2D try-on), SFR-027 (unavailable
handling), SFR-028 (zoomable display, served as image URLs), SF-UC-06.

One job = one garment on 1-4 photos of the user (front, right, back, left).
The garment is a catalog product (product_id) or a photo of the user's own
clothes (garment: photo + top/bottom/dress), which is never stored.
Each photo becomes one 2D try-on image (IDM-VTON + the DressCode LoRA, spec
§23.8/§23.20); the app shows them as a drag-to-spin 360° view.

    POST /tryon            start a job -> 202 {job_id, ...}        (async, spec §8.6)
    GET  /tryon/{job_id}   poll; finished views get signed URLs
    POST /tryon/sign       fresh signed URLs for saved results (wardrobe)

Results are stored in the private `tryon-results` bucket under the user's own
folder and handed out only as time-limited signed URLs (SRDS §4.2). A view
already generated for the same photo + product + model is reused, never
regenerated (spec §13.2). The user id comes from the gateway, which verified
the user's token (x-user-id).
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import io
import logging
import math
import re
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from urllib.parse import quote

import httpx
from fastapi import Header
from fastapi.concurrency import run_in_threadpool
from PIL import Image

from services.tryon import imaging, warping
from services.tryon.gpu_runner import Runner, ViewOutcome, ViewTask, get_runner, runner_error
from shared import catalog_store
from shared.config import settings
from shared.feed_brands import brand_name
from shared.head_crop import crop_head
from shared.schemas.catalog import ScrapedProduct
from shared.schemas.errors import AppError, ErrorEnvelope
from shared.schemas.tryon import (
    VIEW_ORDER,
    CustomGarment,
    SignRequest,
    SignResponse,
    TryOnFit,
    TryOnJob,
    TryOnJobRequest,
    TryOnViewResult,
)
from shared.service_app import create_service_app
from shared.size_fit import clean_body, own_garment_fit, size_fit
from shared.size_estimate import estimate_size, letter_sizes, same_size
from shared.supabase_client import service_select, storage_signed_url, storage_upload

logger = logging.getLogger("smartfit.tryon")

REQUIREMENTS = "SFR-026, SFR-027, SFR-028"
IDM_CATEGORY = {"upper": "upper_body", "lower": "lower_body", "dress": "dresses"}
MAX_GARMENT_BYTES = 12_000_000
GARMENT_CANDIDATES = 8  # product photos checked for a flat-lay (Outfitters' are often the 6th to 8th)


@dataclass
class _View:
    angle: str
    cache_key: str
    status: str = "queued"
    call_id: str | None = None
    storage_path: str | None = None
    error_code: str | None = None
    message: str | None = None
    cached: bool = False
    fitting_path: str | None = None  # the cloth-warping preview (warping.py), once made


@dataclass
class _Job:
    job_id: str
    user_id: str
    product_id: str
    category: str
    model_version: str
    mode: str
    started: float
    views: list[_View]
    fit: TryOnFit | None = None
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    tasks: list[asyncio.Task] = field(default_factory=list)  # fitting previews in progress

    @property
    def active(self) -> bool:
        return any(v.status in ("queued", "running") for v in self.views)


_jobs: dict[str, _Job] = {}
_known_results: dict[str, str] = {}  # cache_key -> storage path (this process)
_client: httpx.AsyncClient | None = None


@asynccontextmanager
def _warm_gpu_client() -> None:
    """Connect to the GPU backend once at start-up, so the first try-on doesn't pay for it."""
    try:
        runner = get_runner() if settings.tryon_backend else None
        warm = getattr(runner, "warm", None)
        if warm is not None:
            warm()
    except Exception as exc:  # noqa: BLE001 - only a head start; a real request reports errors
        logger.info("GPU client warm-up skipped (%s)", type(exc).__name__)


async def lifespan(_app):
    global _client
    _client = httpx.AsyncClient(follow_redirects=True, headers={"User-Agent": settings.scraper_user_agent})
    warm_up = asyncio.create_task(run_in_threadpool(_warm_gpu_client))
    try:
        yield
    finally:
        warm_up.cancel()
        await _client.aclose()
        _client = None


def _health() -> dict:
    runner = get_runner() if settings.tryon_backend else None
    return {
        "implemented": True,
        "backend": settings.tryon_backend or "not connected",
        "connected": runner is not None,
        "backend_error": runner_error(),
        "test_mode": settings.tryon_backend == "mock",
        "active_jobs": sum(1 for j in _jobs.values() if j.active),
    }


app = create_service_app(
    "tryon",
    "SmartFit Try-On Service",
    "2D diffusion virtual try-on (IDM-VTON + DressCode LoRA) with a 4-photo 360° view (SFR-026..028).",
    lifespan=lifespan,
    health_extra=_health,
)


# ── helpers ──────────────────────────────────────────────────────────────────


def _http() -> httpx.AsyncClient:
    if _client is None:  # TestClient without lifespan
        raise RuntimeError("try-on HTTP client not started")
    return _client


_GONE_MESSAGES = {
    "gone": "{brand} no longer sells this item, so it can't be tried on. Try something similar instead.",
    "sold_out": "This item is sold out at {brand} in every size, so it can't be tried on right now.",
    "not_clothing": "Try-on isn't available for this item. You can still see its photos.",
    "unknown_brand": "This item isn't in our catalog any more, so it can't be tried on.",
}


async def _recheck_at_store(product_id: str) -> dict:
    """The scraper's {"status", "product"} for a product missing from the catalog."""
    try:
        res = await _http().post(
            f"{settings.scraper_url.rstrip('/')}/catalog/products/{quote(product_id, safe=':')}/recheck",
            timeout=45.0,
        )
        res.raise_for_status()
        data = res.json()
        return data if isinstance(data, dict) else {"status": "unreachable"}
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("Product re-check failed for %s: %s", product_id, type(exc).__name__)
        return {"status": "unreachable"}


async def _find_product(product_id: str) -> ScrapedProduct:
    """The catalog product, or, when the catalog no longer has it (the daily
    refresh keeps each brand's newest items, so saved items can drop out), the
    same product re-checked at the brand's store by the scraper and saved back.
    Never a bare 404: the app always gets a reason it can show."""
    product = await catalog_store.get_product(_http(), product_id)
    if product is not None:
        return product
    data = await _recheck_at_store(product_id)
    status = data.get("status")
    if status == "available" and data.get("product"):
        return ScrapedProduct.model_validate(data["product"])
    brand = brand_name(product_id.partition(":")[0]) if ":" in product_id else "The store"
    if status == "unreachable":
        raise AppError(503, "STORE_UNREACHABLE",
                       f"We couldn't reach {brand}'s store to check this item. Please try again in a minute.",
                       headers={"Retry-After": "60"})
    template = _GONE_MESSAGES.get(status or "", _GONE_MESSAGES["unknown_brand"])
    raise _unavailable("gone", template.format(brand=brand))


def _require_user(x_user_id: str | None) -> str:
    if not x_user_id:
        raise AppError(401, "UNAUTHORIZED", "Please log in to use virtual try-on.")
    return x_user_id


def _unavailable(reason: str, message: str) -> AppError:
    # SFR-027: a first-class state the app shows with alternatives (product photos, the store page).
    return AppError(422, "TRYON_UNAVAILABLE", message, {"reason": reason})


def _require_runner() -> Runner:
    runner = get_runner() if settings.tryon_backend else None
    if runner is None:
        raise AppError(
            503,
            "TRYON_NOT_CONNECTED",
            "Virtual try-on isn't connected to its GPU yet. Please try again later.",
            {"backend": settings.tryon_backend or None},
        )
    return runner


def _lora_for(category: str) -> bool:
    enabled = {c.strip() for c in settings.tryon_lora_categories.split(",") if c.strip()}
    return settings.lora_weights_enabled and category in enabled


def _model_version(use_lora: bool) -> str:
    return f"idm-vton+{settings.tryon_lora_version}" if use_lora else "idm-vton"


# Bumped when the generation itself changes, so older cached results are made again
# (20 Nov 2026: hair kept, sleeve length in the caption; then the old top's sleeves over the
# trousers repainted too, top_mask.py; no invented tattoos or watches on the skin it paints).
PIPELINE_REVISION = "2026-11-20-hair-sleeve-top-skin"


def _cache_key(person_jpeg: bytes, item_id: str, garment_ref: str, version: str, mode: str,
               caption: str = "") -> str:
    """Same photo + same garment + same model = same result (spec §13.2).
    garment_ref is the product photo's URL, or the hash of an uploaded garment photo."""
    h = hashlib.sha256()
    for part in (person_jpeg, item_id.encode(), garment_ref.encode(), version.encode(),
                 f"{settings.tryon_steps}:{settings.tryon_seed}:{mode}".encode(), caption.encode(),
                 PIPELINE_REVISION.encode()):
        h.update(hashlib.sha256(part).digest())
    return h.hexdigest()[:40]


@dataclass
class _Garment:
    item_id: str  # catalog product id, or "custom:<hash>" for the user's own clothes
    category: str  # "upper" | "lower" | "dress"
    jpeg: bytes  # framed 768x1024
    ref: str  # cache reference (product photo URL or uploaded photo hash)
    caption: str


async def _fetch_image(url: str) -> Image.Image | None:
    try:
        res = await _http().get(url, timeout=20.0)
    except httpx.HTTPError:
        return None
    if res.status_code != 200 or len(res.content) > MAX_GARMENT_BYTES:
        return None
    try:
        return imaging.open_image(res.content)
    except AppError:
        return None


async def _people_in_photo(img: Image.Image) -> int | None:
    """How many people the CV service sees in a product photo; None if it can't say."""
    try:
        res = await _http().post(f"{settings.cv_analysis_url.rstrip('/')}/pose/check", timeout=30.0,
                                 json={"image_base64": base64.b64encode(imaging.to_jpeg(img)).decode()})
        people = res.json().get("people") if res.status_code == 200 else None
        return people if isinstance(people, int) else None
    except (httpx.HTTPError, ValueError, AttributeError) as exc:
        logger.info("people count unavailable (%s)", type(exc).__name__)
        return None


async def _garment(product: ScrapedProduct) -> tuple[Image.Image, str]:
    """The product photo to try on: the garment alone (IDM-VTON's best input)
    among the first few photos, else the main photo.

    1. A flat-lay: the garment on a plain light background, standing out from
       it. Studio photos of a model on a plain background look the same to the
       background test (20 Nov 2026: Outfitters' first photo, a model in a tee
       AND trousers, was taken as the tee's flat-lay), so a candidate must also
       have nobody in it. If the CV service can't say, the background test
       decides, as before.
    2. Else a studio shot the CV service says has nobody in it: a white garment
       on a pale grey backdrop is too faint for test 1 (20 Nov 2026: a white
       cropped shirt's real flat-lay was skipped, the model photo was used, and
       the try-on came out with dark sleeves the shirt doesn't have).
    3. Else the main photo."""
    urls = [product.image_url] + [u for u in product.image_urls if u != product.image_url]
    urls = urls[:GARMENT_CANDIDATES]
    # fetched together (20 Nov 2026: one after another took up to ~9 s of a try-on's start)
    images = await asyncio.gather(*(_fetch_image(u) for u in urls))
    loaded = [(img, url) for url, img in zip(urls, images, strict=True) if img is not None]
    if not loaded:
        raise _unavailable("garment_image", "We couldn't load this product's photo from the store right now. "
                                            "Please try again, or view it on the store.")
    faint: list[tuple[Image.Image, str]] = []
    for img, url in loaded:
        if imaging.looks_like_flatlay(img):
            if not await _people_in_photo(img):
                return img, url
        elif imaging.plain_backdrop(img):
            faint.append((img, url))
    for img, url in faint:
        if await _people_in_photo(img) == 0:  # known to be empty: an unknown count isn't enough here
            return img, url
    return loaded[0]


async def _garment_sleeve(jpeg: bytes) -> str | None:
    """Sleeve length seen in the garment photo (FashionCLIP, recommendation service);
    None when it isn't sure or can't be reached (the caption then has none)."""
    try:
        res = await _http().post(f"{settings.recommendation_url.rstrip('/')}/garment/check", timeout=30.0,
                                 json={"image_base64": base64.b64encode(jpeg).decode()})
        sleeve = res.json().get("sleeve") if res.status_code == 200 else None
        return sleeve if sleeve in ("long sleeve", "short sleeve", "sleeveless") else None
    except (httpx.HTTPError, ValueError, AttributeError) as exc:
        logger.info("sleeve check unavailable (%s)", type(exc).__name__)
        return None


async def _sleeve_caption(caption: str, name: str, category: str, jpeg: bytes) -> str:
    """The caption with the sleeve length: from the name, else from the photo (tops and full outfits)."""
    if category not in ("upper", "dress"):
        return caption
    named = imaging.sleeve_from_name(name)
    if named:  # the brand's own word, in IDM-VTON's vocabulary
        return imaging.canonical_sleeve(caption, named)
    if "sleeve" in caption.lower():  # the name mentions sleeves but not clearly: leave it
        return caption
    return imaging.with_sleeve(caption, await _garment_sleeve(jpeg))


async def _catalog_garment(product: ScrapedProduct) -> _Garment:
    img, url = await _garment(product)
    jpeg = imaging.to_jpeg(imaging.frame_garment(img))
    category = product.tryon_category or "upper"
    caption = await _sleeve_caption(imaging.garment_caption(product.name, product.category), product.name,
                                    category, jpeg)
    return _Garment(item_id=product.product_id, category=category, jpeg=jpeg, ref=url, caption=caption)


_CATEGORY_WORDS = {"upper": "top", "lower": "trousers", "dress": "dress"}


def _custom_garment(body: TryOnJobRequest) -> _Garment:
    """The user's own clothes photo: checked and cleaned like the person photos
    (metadata stripped), never stored, only sent to the GPU."""
    g = body.garment
    assert g is not None  # the request validator guarantees one garment source
    img = imaging.decode_photo(g.image_base64, max_bytes=settings.cv_max_image_bytes, angle="garment",
                               min_side=imaging.MIN_GARMENT_SIDE)
    jpeg = imaging.to_jpeg(imaging.frame_garment(img))
    digest = hashlib.sha256(jpeg).hexdigest()
    caption = imaging.garment_caption(g.name or "", _CATEGORY_WORDS[g.category])
    return _Garment(item_id=f"custom:{digest[:16]}", category=g.category, jpeg=jpeg, ref=digest, caption=caption)


_USER_ID = re.compile(r"^[0-9a-fA-F-]{8,64}$")


async def _body_measurements(user_id: str) -> dict[str, float] | None:
    """The user's chest/waist/hip (cm) from their own profile; None = couldn't read it."""
    if not _USER_ID.match(user_id):  # the id goes into a database filter
        return None
    try:
        rows = await service_select(_http(), "profiles", {"select": "chest_cm,waist_cm,hip_cm", "id": f"eq.{user_id}"})
    except AppError as exc:
        logger.warning("couldn't read the profile measurements: %s", exc.code)
        return None
    return clean_body(rows[0]) if rows else {}


# profile gender (as the app stores it) -> the catalog's product gender
_WEARS = {"male": "men", "man": "men", "men": "men", "female": "women", "woman": "women", "women": "women"}


async def _profile_wears(user_id: str) -> str | None:
    """"men" / "women" from the user's own profile; None when it isn't set (or
    is "non-binary" / "prefer not to say"), in which case nothing is blocked."""
    if not _USER_ID.match(user_id):
        return None
    try:
        rows = await service_select(_http(), "profiles", {"select": "gender", "id": f"eq.{user_id}"})
    except AppError as exc:
        logger.warning("couldn't read the profile gender: %s", exc.code)
        return None
    gender = str((rows[0] or {}).get("gender") or "").strip().lower() if rows else ""
    return _WEARS.get(gender)


async def _gender_verdict(jpeg: bytes, kind: str, photo: bytes | None = None) -> str | None:
    """The recommendation service's confident answer ("men"/"women" for a garment,
    "man"/"woman" for a face), or None: not sure, model missing, or service down.
    For a face, `photo` is the whole photo it came from (a second opinion)."""
    payload = {"image_base64": base64.b64encode(jpeg).decode(), "kind": kind}
    if photo is not None:
        payload["photo_base64"] = base64.b64encode(photo).decode()
    try:
        res = await _http().post(f"{settings.recommendation_url.rstrip('/')}/gender/check", timeout=30.0,
                                 json=payload)
        if res.status_code != 200:
            logger.info("gender check unavailable (HTTP %s); skipped", res.status_code)
            return None
        data = res.json()
        return data.get("label") if isinstance(data, dict) and data.get("available") else None
    except (httpx.HTTPError, ValueError) as exc:
        logger.info("gender check unavailable (%s); skipped", type(exc).__name__)
        return None


def _head_jpeg(person_jpeg: bytes, verdict: dict | None) -> bytes | None:
    """The head of the person in the (front) photo, from the HRNet keypoints."""
    if not verdict or not verdict.get("keypoints"):
        return None
    try:
        img = Image.open(io.BytesIO(person_jpeg))
        img.load()
    except OSError:
        return None
    head = crop_head(img.convert("RGB"), verdict["keypoints"])
    return imaging.to_jpeg(head) if head is not None else None


_WEARER = {"man": "men", "woman": "women"}


async def _check_wearer(user_id: str, product: ScrapedProduct | None, own: _Garment | None,
                        persons: list[tuple[str, bytes]], person_checks: dict[str, dict]) -> None:
    """Menswear is tried on men and womenswear on women (18 Nov 2026: a women's
    outfit was put on a man's photo).

    * The garment: a catalog product's gender comes from its brand's feed; the
      user's own clothes photo is judged by the garment model. Unisex, or a
      model that isn't sure, never blocks.
    * The wearer: the face in the front photo when the face model is sure AND
      the whole photo agrees (the photo is who will wear it), otherwise the
      profile's gender, otherwise nobody is blocked.
    Only confident answers count (each model keeps them >= 97 % right on held-out data)."""
    front = next(((a, j) for a, j in persons if a == "front"), persons[0])
    head = _head_jpeg(front[1], person_checks.get(front[0]))
    garment_task = _gender_verdict(own.jpeg, "garment") if own is not None else None
    face_task = _gender_verdict(head, "face", front[1]) if head is not None else None
    garment_label, face_label = await asyncio.gather(
        garment_task if garment_task is not None else _none(), face_task if face_task is not None else _none())

    if product is not None:
        clothes = product.gender if product.gender in ("men", "women") else None
    else:
        clothes = garment_label if garment_label in ("men", "women") else None
    if clothes is None:
        return
    wearer, source = _WEARER.get(face_label or ""), "photo"
    if wearer is None:
        wearer, source = await _profile_wears(user_id), "profile"
    if wearer is None or wearer == clothes:
        return
    item = ("a women's outfit" if clothes == "women" else "a men's outfit") if product is not None else \
        ("women's clothing" if clothes == "women" else "men's clothing")
    other = "men's" if wearer == "men" else "women's"
    if source == "photo":
        who = "a man" if wearer == "men" else "a woman"
        message = (f"This looks like {item} and the person in your photo looks like {who}, so it isn't tried on. "
                   f"Choose something from the {other} collection, or use a photo of the person who will wear it.")
    else:
        you = "male" if wearer == "men" else "female"
        message = (f"This is {item} and your profile is set to {you}, so it isn't tried on your photo. "
                   f"Pick something from the {other} collection instead.")
    raise _unavailable("gender", message)


async def _none() -> None:
    return None


def _fit_out(status: str, fit) -> TryOnFit:
    return TryOnFit(status=status, basis=fit.basis, size=fit.recommended_size, note=fit.note)


async def _estimated_size(user_id: str) -> str | None:
    """The user's standard size (XS..4XL) from their own profile (the largest of chest,
    waist and hip sizes, else BMI; shared/size_estimate.py, as the body scan); None when
    there's nothing to go on."""
    if not _USER_ID.match(user_id):
        return None
    try:
        rows = await service_select(_http(), "profiles", {
            "select": "gender,chest_cm,waist_cm,hip_cm,height_cm,weight_kg", "id": f"eq.{user_id}"})
    except AppError as exc:
        logger.warning("couldn't read the profile for the size: %s", exc.code)
        return None
    if not rows:
        return None
    r = rows[0]

    def num(key: str) -> float | None:
        try:
            v = float(r.get(key)) if r.get(key) is not None else None
        except (TypeError, ValueError):
            return None
        return v if v and v > 0 else None

    label, source = estimate_size({}, r.get("gender"), num("chest_cm"), num("height_cm"), num("weight_kg"),
                                  profile_waist=num("waist_cm"), profile_hip=num("hip_cm"))
    return None if source == "default_fallback" else label


def _sold_out_in_size(product: ScrapedProduct, size: str) -> bool:
    """The product is made in this size, but none is in stock right now. Labels are read
    as sizes ("L (14)", "X-Large", "S-M"), not compared as text."""
    def read(label: str) -> set[str]:
        return letter_sizes(label) or {same_size(label)}

    wanted = read(size)
    made = {x for s in (product.all_sizes or product.sizes) for x in read(s)}
    in_stock = {x for s in product.sizes for x in read(s)}
    return bool(wanted & made) and not wanted & in_stock


async def _check_fit(user_id: str, product: ScrapedProduct | None, own: CustomGarment | None) -> TryOnFit:
    """SFR-025, before any GPU work. The size verdict ("fits" / "small" / "big" /
    "unknown") is reported, never a reason to refuse (user's call, 15 Nov 2026);
    the one refusal is a store item whose estimated size, the user's size, is
    sold out (SFR-025 wording, user's call 20 Nov 2026)."""
    body = await _body_measurements(user_id)
    if product is not None:
        fit = size_fit(product, None, body or {})
        if fit.basis != "size_chart" and any(letter_sizes(s) for s in (product.all_sizes or product.sizes)):
            letter = await _estimated_size(user_id)  # no chart: the size the body scan / profile gives
            if letter:
                fit = size_fit(product, letter, body or {})
        size = fit.recommended_size
        if size and fit.compatible is False and _sold_out_in_size(product, size):
            shop = brand_name(product.retailer)
            raise _unavailable("size_sold_out",
                               f"Your size ({size}) is sold out at {shop} right now, so this can't be tried on. "
                               "You can still look at its photos, open it on the store, or pick something "
                               "similar that's in stock in your size.")
        if fit.verdict in ("fits", "small", "big"):
            return _fit_out(fit.verdict, fit)
        note = fit.note or "We couldn't check the fit: add your measurements in your profile."
        if body is None:
            note = "We couldn't check the fit right now."
        elif fit.basis == "unknown" and body:
            note = "We couldn't check the fit: this brand doesn't publish a size chart."
        return TryOnFit(status="unknown", basis="unknown", note=note)

    assert own is not None
    widths = {k: v for k, v in (("chest_cm", own.chest_width_cm), ("waist_cm", own.waist_width_cm)) if v}
    if body is None:
        return TryOnFit(status="unknown", basis="unknown",
                        note="We couldn't read your measurements, so the size isn't checked.")
    try:
        fit = own_garment_fit(own.category, widths, body)
    except ValueError as exc:
        # a missing tape measurement: still try it on, just say the size is unchecked
        return TryOnFit(status="unknown", basis="measurements", note=str(exc))
    return _fit_out(fit.verdict, fit)


# The clothes photo must show clothing of the chosen kind (FashionCLIP, recommendation service).
NOT_CLOTHING_MIN = 0.6  # "shoes / bag / not clothing" at least this likely -> refused
MISMATCH_MAX_CHOSEN = 0.15  # the chosen kind this unlikely ...
MISMATCH_MIN_OTHER = 0.6  # ... and another kind this likely -> refused, with a suggestion
_KIND_WORDS = {"upper": "a top", "lower": "a bottom (trousers, jeans, skirt)", "dress": "a full outfit or dress"}


async def _classify_garment(jpeg: bytes) -> dict[str, float] | None:
    try:
        res = await _http().post(f"{settings.recommendation_url.rstrip('/')}/garment/check", timeout=30.0,
                                 json={"image_base64": base64.b64encode(jpeg).decode()})
        if res.status_code != 200:
            logger.info("garment check unavailable (HTTP %s); skipped", res.status_code)
            return None
        scores = res.json().get("scores")
        return scores if isinstance(scores, dict) else None
    except (httpx.HTTPError, ValueError) as exc:
        logger.info("garment check unavailable (%s); skipped", type(exc).__name__)
        return None


async def _check_garment_photo(garment: _Garment) -> None:
    """Refuse a photo that isn't clothing, or clearly another kind than chosen.
    If the checker is down the try-on still runs (the GPU checks the person)."""
    scores = await _classify_garment(garment.jpeg)
    if not scores:
        return
    if scores.get("other", 0.0) >= NOT_CLOTHING_MIN:
        raise AppError(422, "NOT_CLOTHING", "This photo doesn't look like clothing. Please use a clear photo of one "
                                            "top, bottom or outfit.", {"angle": "garment"})
    kinds = {k: scores.get(k, 0.0) for k in _KIND_WORDS}
    best = max(kinds, key=kinds.__getitem__)
    if best != garment.category and kinds[garment.category] < MISMATCH_MAX_CHOSEN and kinds[best] >= MISMATCH_MIN_OTHER:
        raise AppError(422, "GARMENT_MISMATCH",
                       f"This looks like {_KIND_WORDS[best]}, not {_KIND_WORDS[garment.category]}. "
                       "Please choose the right type.", {"angle": "garment", "suggested": best})


PERSON_CODES = {"NO_PERSON", "MULTIPLE_PEOPLE", "POSE_NOT_UPRIGHT", "PERSON_TOO_SMALL", "BODY_CUT_OFF"}


async def _person_verdict(angle: str, person_jpeg: bytes, category: str) -> dict | None:
    """HRNet photo check in the CV service; None if it can't be reached."""
    try:
        res = await _http().post(f"{settings.cv_analysis_url.rstrip('/')}/pose/check", timeout=30.0,
                                 json={"image_base64": base64.b64encode(person_jpeg).decode(), "category": category,
                                       "angle": angle})
        if res.status_code != 200:
            logger.info("person check unavailable (HTTP %s); skipped", res.status_code)
            return None
        verdict = res.json()
        return verdict if isinstance(verdict, dict) else None
    except (httpx.HTTPError, ValueError) as exc:
        logger.info("person check unavailable (%s); skipped", type(exc).__name__)
        return None


async def _check_person_photos(persons: list[tuple[str, bytes]], category: str) -> dict[str, dict]:
    """Every photo shows one upright person with the body parts this garment
    needs (HRNet), before any paid GPU work. If the checker is down the try-on
    still runs: the GPU step checks the person too."""
    verdicts = await asyncio.gather(*(_person_verdict(angle, jpeg, category) for angle, jpeg in persons))
    for (angle, _), verdict in zip(persons, verdicts):
        if verdict and verdict.get("ok") is False and verdict.get("code") in PERSON_CODES:
            raise AppError(422, verdict["code"], str(verdict.get("message") or "Please retake this photo."),
                           {"angle": angle})
    return {angle: v for (angle, _), v in zip(persons, verdicts) if v}


async def _stored(path: str) -> str | None:
    """Signed URL if the object exists, else None."""
    try:
        return await storage_signed_url(_http(), settings.storage_bucket_tryon, path)
    except AppError:
        return None


def _status(views: list[_View]) -> str:
    states = {v.status for v in views}
    if states & {"queued", "running"}:
        return "running"
    if states == {"done"}:
        return "done"
    if "done" in states:
        return "partial"
    return "failed"


def _estimate(n_views: int) -> int:
    # Two GPU containers work in parallel; the first request also warms one up.
    return math.ceil(n_views / 2) * settings.tryon_seconds_per_view + 60


async def _view_results(job: _Job) -> list[TryOnViewResult]:
    out = []
    for v in job.views:
        url = await _stored(v.storage_path) if v.status == "done" and v.storage_path else None
        fitting = await _stored(v.fitting_path) if v.fitting_path else None
        out.append(TryOnViewResult(angle=v.angle, status=v.status, image_url=url, storage_path=v.storage_path,
                                   error_code=v.error_code, message=v.message, cached=v.cached,
                                   fitting_url=fitting, fitting_path=v.fitting_path if fitting else None))
    return out


def _fitting_jpeg(person_jpeg: bytes, garment: _Garment, keypoints: list[dict]) -> bytes | None:
    """The cloth-warping preview (warping.py) as JPEG; None when it can't be made. CPU only.
    Only for a studio garment photo: a photo with a model in it would warp the model too."""
    garment_img = Image.open(io.BytesIO(garment.jpeg)).convert("RGB")
    if not imaging.plain_backdrop(garment_img):
        return None
    person = Image.open(io.BytesIO(person_jpeg)).convert("RGB")
    preview = warping.fitting_preview(person, garment_img, keypoints, garment.category, garment.caption)
    return imaging.to_jpeg(preview, quality=88) if preview is not None else None


async def _make_fitting(user_id: str, view: _View, person_jpeg: bytes, garment: _Garment,
                        keypoints: list[dict]) -> None:
    """Fitting preview for one view, in the background; never affects the try-on itself."""
    path = f"{user_id}/{view.cache_key}_fit.jpg"
    try:
        if await _stored(path):  # made for an earlier, identical try-on
            view.fitting_path = path
            return
        jpeg = await run_in_threadpool(_fitting_jpeg, person_jpeg, garment, keypoints)
        if jpeg is None:
            return
        await storage_upload(_http(), settings.storage_bucket_tryon, path, jpeg, "image/jpeg")
        view.fitting_path = path
    except Exception as exc:  # noqa: BLE001 - a preview must never break the try-on
        logger.info("fitting preview skipped for %s (%s)", view.angle, type(exc).__name__)


async def _job_response(job: _Job) -> TryOnJob:
    return TryOnJob(
        job_id=job.job_id, status=_status(job.views), product_id=job.product_id, category=job.category,
        fit=job.fit, views=await _view_results(job), mode=job.mode, model_version=job.model_version,
        elapsed_seconds=round(time.time() - job.started, 1), estimated_seconds=_estimate(len(job.views)),
    )


def _forget_old_jobs() -> None:
    cutoff = time.time() - settings.tryon_job_ttl_seconds
    for job_id in [j for j, job in _jobs.items() if job.started < cutoff]:
        _jobs.pop(job_id, None)


_FRIENDLY = {
    "NO_PERSON": "We couldn't find your whole body in the {angle} photo. Stand back so you're visible "
                 "from head to knees, in good light, and try again.",
    "GPU_ERROR": "The try-on generator had a problem with the {angle} photo. Please try again.",
}


def _apply(view: _View, outcome: ViewOutcome) -> None:
    if outcome.state == "failed":
        view.status = "failed"
        view.error_code = outcome.error_code or "GPU_ERROR"
        template = _FRIENDLY.get(view.error_code)
        view.message = template.format(angle=view.angle) if template else (outcome.message or _FRIENDLY["GPU_ERROR"].format(angle=view.angle))


# ── endpoints ────────────────────────────────────────────────────────────────


@app.post("/tryon", status_code=202, response_model=TryOnJob,
          responses={401: {"model": ErrorEnvelope}, 404: {"model": ErrorEnvelope}, 422: {"model": ErrorEnvelope},
                     429: {"model": ErrorEnvelope}, 503: {"model": ErrorEnvelope}})
async def start_try_on(body: TryOnJobRequest, x_user_id: str | None = Header(None)) -> TryOnJob:
    user_id = _require_user(x_user_id)
    _forget_old_jobs()

    angles = [v.angle for v in body.views]
    if len(set(angles)) != len(angles):
        raise AppError(422, "VALIDATION_ERROR", "Each side (front, right, back, left) can only be used once.")
    if "front" not in angles:
        raise AppError(422, "VALIDATION_ERROR", "A front photo is needed for the try-on.")

    product: ScrapedProduct | None = None
    if body.product_id is not None:
        product = await _find_product(body.product_id)
        if product.tryon_category is None:
            raise _unavailable("not_supported", "Try-on isn't available for this item (unstitched fabric or an "
                                                "accessory). You can still see its photos and view it on the store.")

    # SFR-025: a garment that doesn't fit the user is never tried on. Checked
    # here on the server, from the user's own profile measurements.
    fit = await _check_fit(user_id, product, body.garment)

    runner = _require_runner()
    if any(j.active and j.user_id == user_id for j in _jobs.values()):
        raise AppError(429, "TRYON_IN_PROGRESS", "You already have a try-on in progress. Please wait for it to finish.",
                       headers={"Retry-After": "20"})
    if sum(1 for j in _jobs.values() if j.active) >= max(1, settings.max_concurrent_tryon_jobs):
        raise AppError(429, "TRYON_BUSY", "The try-on studio is busy right now. Please try again in a minute.",
                       headers={"Retry-After": "60"})

    # Validate every photo before any GPU work (rules.md §5, spec §8.3).
    persons = []
    for v in sorted(body.views, key=lambda v: VIEW_ORDER.index(v.angle)):
        img = imaging.decode_photo(v.image_base64, max_bytes=settings.cv_max_image_bytes, angle=v.angle, person=True)
        persons.append((v.angle, imaging.to_jpeg(imaging.frame_person(img))))
    category = product.tryon_category if product is not None else body.garment.category  # type: ignore[union-attr]
    person_checks = await _check_person_photos(persons, category)
    own = _custom_garment(body) if product is None else None
    # menswear on men, womenswear on women: before the garment photo is fetched or any GPU work
    await _check_wearer(user_id, product, own, persons, person_checks)

    if product is not None:
        garment = await _catalog_garment(product)
    else:
        garment = own  # type: ignore[assignment]
        await _check_garment_photo(garment)
        garment.caption = await _sleeve_caption(garment.caption, body.garment.name or "",  # type: ignore[union-attr]
                                                garment.category, garment.jpeg)
    use_lora = _lora_for(garment.category)
    version = _model_version(use_lora)

    job = _Job(job_id=uuid.uuid4().hex, user_id=user_id, product_id=garment.item_id,
               category=garment.category, model_version=version, mode=runner.mode, started=time.time(), views=[],
               fit=fit)
    to_submit: list[tuple[_View, ViewTask]] = []
    for angle, person_jpeg in persons:
        key = _cache_key(person_jpeg, garment.item_id, garment.ref, version, runner.mode, garment.caption)
        view = _View(angle=angle, cache_key=key)
        path = f"{user_id}/{key}.jpg"
        if _known_results.get(key) == path or await _stored(path):
            view.status, view.storage_path, view.cached = "done", path, True
            _known_results[key] = path
        else:
            to_submit.append((view, ViewTask(person_jpeg=person_jpeg, garment_jpeg=garment.jpeg,
                                             category=IDM_CATEGORY[garment.category], caption=garment.caption,
                                             use_lora=use_lora, seed=settings.tryon_seed, steps=settings.tryon_steps,
                                             angle=angle)))
        job.views.append(view)

    async def submit(view: _View, task: ViewTask) -> None:
        try:
            view.call_id = await run_in_threadpool(runner.submit, task)
            view.status = "running"
        except Exception as exc:  # noqa: BLE001
            logger.warning("try-on submit failed: %s", type(exc).__name__)
            _apply(view, ViewOutcome("failed", error_code="GPU_ERROR"))

    # a 360° try-on's four views go to the GPU together (one at a time took up to ~20 s)
    await asyncio.gather(*(submit(v, t) for v, t in to_submit))
    # the cloth-warping previews, on the CPU while the GPU works (from the photo check's body points)
    for view, (_, person_jpeg) in zip(job.views, persons, strict=True):
        keypoints = (person_checks.get(view.angle) or {}).get("keypoints") or []
        if keypoints:
            job.tasks.append(asyncio.create_task(_make_fitting(user_id, view, person_jpeg, garment, keypoints)))

    _jobs[job.job_id] = job
    logger.info("try-on job %s: %d view(s), %s, %s", job.job_id, len(job.views), version, runner.mode)
    return await _job_response(job)


@app.get("/tryon/{job_id}", response_model=TryOnJob,
         responses={401: {"model": ErrorEnvelope}, 404: {"model": ErrorEnvelope}})
async def get_try_on(job_id: str, x_user_id: str | None = Header(None)) -> TryOnJob:
    user_id = _require_user(x_user_id)
    job = _jobs.get(job_id)
    if job is None or job.user_id != user_id:  # never reveal another user's job
        raise AppError(404, "NOT_FOUND", "This try-on has expired. Please start it again.")
    runner = get_runner()
    async with job.lock:  # two polls at once must not upload twice
        for view in job.views:
            if view.status != "running" or not view.call_id:
                continue
            if runner is None:
                _apply(view, ViewOutcome("failed", error_code="GPU_ERROR"))
                continue
            outcome = await run_in_threadpool(runner.poll, view.call_id)
            if outcome.state == "done" and outcome.image_jpeg:
                path = f"{user_id}/{view.cache_key}.jpg"
                try:
                    await storage_upload(_http(), settings.storage_bucket_tryon, path, outcome.image_jpeg, "image/jpeg")
                except AppError as exc:
                    logger.warning("try-on upload failed: %s", exc.message)
                    view.status, view.error_code = "failed", "STORAGE_ERROR"
                    view.message = "Your try-on was made but couldn't be saved. Please try again."
                    continue
                view.status, view.storage_path = "done", path
                _known_results[view.cache_key] = path
            else:
                _apply(view, outcome)
    return await _job_response(job)


@app.post("/tryon/sign", response_model=SignResponse, responses={401: {"model": ErrorEnvelope}})
async def sign_results(body: SignRequest, x_user_id: str | None = Header(None)) -> SignResponse:
    """Fresh links for try-on images saved in the wardrobe (signed URLs expire).
    Only paths in the user's own folder are signed."""
    user_id = _require_user(x_user_id)
    urls = {}
    for path in body.paths:
        if path.startswith(f"{user_id}/") and ".." not in path:
            url = await _stored(path)
            if url:
                urls[path] = url
    return SignResponse(urls=urls)
