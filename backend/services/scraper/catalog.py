"""Catalog ingestion from Pakistani brands' official product feeds (spec §10, §23.12).

Every brand in shared/feed_brands.py publishes a Shopify storefront feed
(/products.json, allowed by its robots.txt), read 250 products a page.
Breakout has no feed, so it comes in through manual_import.py instead.

Kept: adult clothing (men and women 18+). Tops, bottoms and full outfits
(dresses, frocks, 2/3-piece stitched suits, shalwar kameez) get a try-on
slot; unstitched fabric is kept for recommendations without one. Kids' wear,
shoes, accessories, jewellery, make-up, fragrance and home textiles are
skipped and counted.
"""

from __future__ import annotations

import logging
import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime

from pydantic import ValidationError

from shared.audience import is_kids_item
from shared.feed_brands import BY_KEY, FeedBrand
from shared.schemas.catalog import ScrapedProduct
from services.scraper.polite import PoliteClient, RobotsDisallowed
from services.scraper.size_chart import chart_tag, fetch_chart, parse_chart

logger = logging.getLogger("smartfit.scraper.catalog")

# Kept for callers that predate the brand registry.
FeedRetailer = FeedBrand
FEED_RETAILERS: dict[str, FeedBrand] = BY_KEY

FEED_PAGE_SIZE = 250  # Shopify's maximum

# ── Gender ───────────────────────────────────────────────────────────────────
ADULT_GENDER_TAGS = {"men": "men", "women": "women"}
KIDS_TAGS = {"kids", "kid", "boys", "girls", "juniors", "junior"}
KIDS_TAG_FRAGMENTS = ("baby", "toddler", "junior")
_MEN_WORDS = re.compile(r"\b(men|mens|man|male|gents?|menswear|him)\b")
_WOMEN_WORDS = re.compile(r"\b(women|womens|woman|ladies|lady|female|womenswear|her)\b")

# ── Garment kind ─────────────────────────────────────────────────────────────
# Whole words only, so "capri" isn't a cap, "baggy" isn't a bag and
# "watchful" isn't a watch.
_NOT_CLOTHING = re.compile(
    r"\b(shoes?|sneakers?|sandals?|slippers?|chappals?|peshawaris?|khussas?|mules|pumps|heels|boots?|loafers?|"
    r"socks?|underwear|innerwear|briefs?|boxers?|bras?|lingerie|jewell?ery|earrings?|rings?|bangles?|"
    r"necklaces?|bracelets?|hair ?clips?|belts?|braces|wallets?|bags?|handbags?|clutch(es)?|purses?|"
    r"watch(es)?|fragrances?|perfumes?|attars?|body mists?|caps?|hats?|sunglass(es)?|make ?up|cosmetics?|"
    r"lipsticks?|foundations?|mascaras?|nail|skin ?care|bed ?sheets?|duvets?|duvet covers?|quilts?|"
    r"quilt covers?|comforters?|cushions?|curtains?|towels?|pillows?|blankets?|rugs?|home|cufflinks?|ties|"
    r"bow ?ties?|gift ?cards?|gift packaging|handwritten note|vouchers?|masks?)\b"
)
# Accessories worn with clothing: a product is one only when nothing else names a garment
# ("Lawn 3 Piece With Chiffon Dupatta" is a suit).
_ACCESSORY = re.compile(r"\b(shawls?|stoles?|scarf|scarves|dupattas?|hijabs?|mufflers?)\b")
_FABRIC = re.compile(r"\b(un-?stitched|unstitch|unstiched|fabrics?|yardage|cloth piece)\b")
_DRESS = re.compile(
    r"\b(dress(es)?|jump ?suits?|frocks?|maxis?|gowns?|sarees?|saris?|lehe?ngas?|lehnga|ghararas?|"
    r"shararas?|anarkalis?|kaftans?|abayas?|jubbas?|thobes?|co-?ords?|shalwar kameez|kameez shalwar|"
    r"kurta (pajama|shalwar|trouser)s?)\b"
)
# A "suit" / "3 piece" is a Pakistani outfit (kameez, trouser, dupatta) when its
# fabric or garments are named or it's a women's product; otherwise a Western
# jacket-and-trousers suit, which try-on doesn't do.
_SET = re.compile(r"\b(suits?|[23] ?-?(pc|pcs|piece|pieces)|two piece|three piece)\b")
_EASTERN = re.compile(
    r"\b(lawn|khaddar|chiffon|jacquard|cambric|linen|cotton|karandi|marina|silk|velvet|organza|net|"
    r"stitched|embroidered|printed|shalwar|salwar|kameez|qameez|kurta|kurti|dupatta|pajama|eastern|pret|"
    r"ready to wear|trouser)\b"
)
_LOWER = re.compile(
    r"\b(bottoms?|jeans?|trousers?|pants?|shorts|skirts?|joggers?|shalwars?|salwars?|palazzos?|culottes?|"
    r"tights|capris?|chinos?|cargos?|pajamas?|leggings?|dhoti)\b"
)
_UPPER = re.compile(
    r"\b(tees?|t-?shirts?|shirts?|sweatshirts?|blouses?|polos?|sweaters?|hoodies?|outerwear|jackets?|"
    r"coats?|tops?|kurtas?|kurtis?|kameez|tunics?|waistcoats?|blazers?|cardigans?|activewear \(top\)|"
    r"shirts/blouses|vests?|tanks?|sherwanis?|achkans?|prince ?coats?)\b"
)


@dataclass
class IngestStats:
    pages: int = 0
    seen: int = 0
    kept: int = 0
    skipped: Counter = field(default_factory=Counter)


def adult_gender(tags: list[str]) -> str | None:
    """"men" / "women" from a product's tags; None for kids' or untagged items."""
    lowered = [t.strip().lower() for t in tags]
    if any(t in KIDS_TAGS or any(f in t for f in KIDS_TAG_FRAGMENTS) for t in lowered):
        return None
    genders = {ADULT_GENDER_TAGS[t] for t in lowered if t in ADULT_GENDER_TAGS}
    if len(genders) == 1:
        return genders.pop()
    return "unisex" if genders == {"men", "women"} else None


def product_gender(tags: list[str], title: str, product_type: str, handle: str, audience: str) -> str | None:
    """The product's own labels first (tags, then type/title/link words); the
    brand's audience only when they say nothing; None = can't tell (skipped)."""
    from_tags = adult_gender(tags)
    if from_tags:
        return from_tags
    text = " ".join([product_type, title, handle.replace("-", " "), " ".join(tags)]).lower()
    men, women = bool(_MEN_WORDS.search(text)), bool(_WOMEN_WORDS.search(text))
    if men and women:
        return "unisex"
    if men or women:
        return "men" if men else "women"
    return audience if audience in ("men", "women") else None


def garment_kind(text: str) -> str | None:
    """"upper" | "lower" | "dress" | "fabric" | "set" (suit / N-piece) |
    "accessory" | "excluded" | None (no clothing word)."""
    t = text.lower().replace("dress shirt", "shirt").replace("dress pant", "pant")
    if _NOT_CLOTHING.search(t):
        return "excluded"
    if _FABRIC.search(t):
        return "fabric"
    if _DRESS.search(t):
        return "dress"
    if _SET.search(t):
        return "set"
    if _LOWER.search(t):
        return "lower"
    if _UPPER.search(t):
        return "upper"
    if _ACCESSORY.search(t):
        return "accessory"
    return None


def tryon_slot(product_type: str) -> str | None:
    """Try-on slot for a product type, or None (not tried on)."""
    kind = classify_garment(product_type, "")
    return kind if kind in ("upper", "lower", "dress") else None


def classify_garment(product_type: str, title: str, tags: list[str] | None = None, gender: str | None = None) -> str | None:
    """"upper" | "lower" | "dress" | "fabric" | "excluded" | None.

    Product type, then title, then tags (some stores put the garment only in a
    tag, e.g. "3 Piece"). Shoes, bags, make-up... in the type or title exclude
    the product; an accessory word only when nothing names a garment."""
    tag_text = " ".join(t for t in (tags or []) if ":" not in t)  # skip "dhldes:..." data tags
    kinds = [garment_kind(product_type), garment_kind(title), garment_kind(tag_text)]
    if "excluded" in kinds[:2]:
        return "excluded"
    for kind in kinds:
        if kind in ("upper", "lower", "dress", "fabric"):
            return kind
    if "set" in kinds:
        text = f"{product_type} {title} {tag_text}".lower()
        return "dress" if _EASTERN.search(text) or gender == "women" else "excluded"
    if "accessory" in kinds:
        return "excluded"
    return None


def normalise_category(product_type: str) -> str:
    return re.sub(r"\s+", " ", product_type.strip().lower())


def _option_index(item: dict, name: str) -> int | None:
    for i, opt in enumerate(item.get("options") or []):
        if (opt.get("name") or "").strip().lower() == name:
            return i
    return None


def parse_shopify_product(item: dict, retailer: FeedBrand, scraped_at: datetime) -> tuple[ScrapedProduct | None, str]:
    """(product, "") or (None, skip reason). Pure function, unit-tested."""
    title = (item.get("title") or "").strip()
    handle = (item.get("handle") or "").strip()
    if not title or not handle:
        return None, "missing_title_or_handle"

    tags = item.get("tags") or []
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",")]
    product_type = (item.get("product_type") or "").strip()
    if is_kids_item(title, tags, product_type, f"/products/{handle}"):
        return None, "kids_or_ungendered"
    gender = product_gender(tags, title, product_type, handle, retailer.audience)
    if gender is None:
        return None, "kids_or_ungendered"

    kind = classify_garment(product_type, title, tags, gender)
    if kind in (None, "excluded"):
        return None, "not_tryon_clothing"
    slot = None if kind == "fabric" else kind

    images = [img["src"] for img in item.get("images") or [] if img.get("src")]
    if not images:
        return None, "no_image"

    variants = item.get("variants") or []
    size_idx = _option_index(item, "size")
    color_idx = _option_index(item, "color")

    def opt(v: dict, idx: int | None) -> str | None:
        return (v.get(f"option{idx + 1}") or "").strip() or None if idx is not None else None

    all_sizes: list[str] = []
    in_stock: list[str] = []
    prices: list[float] = []
    for v in variants:
        size = opt(v, size_idx)
        if size and size not in all_sizes:
            all_sizes.append(size)
        if v.get("available"):
            if size and size not in in_stock:
                in_stock.append(size)
            try:
                prices.append(float(v.get("price")))
            except (TypeError, ValueError):
                pass
    if not prices:
        return None, "out_of_stock"
    prices = [x for x in prices if x > 0]
    if not prices:
        return None, "no_price"  # e.g. a "coming soon" placeholder listed at 0

    colors: list[str] = []
    for v in variants:
        c = opt(v, color_idx)
        if c and c not in colors:
            colors.append(c)

    try:
        product = ScrapedProduct(
            product_id=f"{retailer.key}:{handle}",
            retailer=retailer.key,
            name=title,
            product_url=f"{retailer.base_url}/products/{handle}",
            image_url=images[0],
            image_urls=images,
            price=min(prices),
            sizes=in_stock,
            all_sizes=all_sizes,
            category=normalise_category(product_type) or kind,
            tryon_category=slot,
            gender=gender,
            colors=colors,
            size_chart_tag=chart_tag(tags),
            source="shopify_feed",
            scraped_at=scraped_at,
        )
    except ValidationError:  # one malformed product must never fail its brand's refresh
        return None, "invalid"
    return product, ""


async def attach_size_charts(
    client: PoliteClient,
    retailer: FeedRetailer,
    products: list[ScrapedProduct],
    previous: dict[str, ScrapedProduct] | None = None,
) -> Counter:
    """Fill size_chart/size_chart_raw. Reuses the previous refresh's chart
    when the product's chart tag hasn't changed (fewer requests)."""
    counts: Counter = Counter()
    previous = previous or {}
    for i, p in enumerate(products):
        if not p.size_chart_tag or not retailer.size_chart_shop:
            counts["no_chart_tag"] += 1
            continue
        old = previous.get(p.product_id)
        if old is not None and old.size_chart_tag == p.size_chart_tag and old.size_chart_raw:
            raw = old.size_chart_raw
            counts["reused"] += 1
        else:
            try:
                raw = await fetch_chart(client, retailer.size_chart_shop, p.size_chart_tag)
            except (RobotsDisallowed, ValueError) as exc:
                logger.warning("Size chart unavailable for %s: %s", p.product_id, exc)
                raw = None
            counts["fetched" if raw else "missing"] += 1
        chart = parse_chart(raw) if raw else None
        if raw and chart is None:
            counts["unusable"] += 1
        products[i] = p.model_copy(update={"size_chart_raw": raw, "size_chart": chart})
    return counts


MAX_FEED_PAGES = 12  # 3,000 products scanned per brand and refresh
# One wait as the store asks, then give up for this refresh: retrying while
# blocked only keeps the block alive (Shopify limits per IP across stores).
MAX_RATE_LIMIT_WAITS = 1
MAX_RETRY_AFTER_SECONDS = 120.0


class FeedRateLimited(RuntimeError):
    """The store kept answering 429 (too many requests); try again next refresh."""


async def get_feed_page(client: PoliteClient, url: str, sleep=None) -> dict:
    """One feed page. On 429 waits as long as the store's Retry-After asks
    (Shopify limits by IP across all its stores) and asks again, a few times."""
    import asyncio

    sleep = sleep or asyncio.sleep
    for _ in range(MAX_RATE_LIMIT_WAITS + 1):
        res = await client.get(url, headers={"Accept": "application/json"})
        if res.status_code == 429:
            try:
                wait = float(res.headers.get("retry-after") or 60)
            except ValueError:
                wait = 60.0
            logger.info("429 from %s; waiting %.0f s as asked", url, min(wait, MAX_RETRY_AFTER_SECONDS))
            await sleep(min(wait, MAX_RETRY_AFTER_SECONDS))
            continue
        if res.status_code != 200 or "json" not in res.headers.get("content-type", "json"):
            raise RuntimeError(f"feed returned HTTP {res.status_code}")
        return res.json()
    raise FeedRateLimited(f"still rate-limited after {MAX_RATE_LIMIT_WAITS} waits")


async def crawl_shopify_feed(
    client: PoliteClient, retailer: FeedBrand, max_products: int, max_pages: int = MAX_FEED_PAGES, sleep=None
) -> tuple[list[ScrapedProduct], IngestStats]:
    """Read up to max_pages of /products.json and keep the newest max_products
    in-stock adult clothing items (whatever order the store lists them in)."""
    stats = IngestStats()
    found: dict[str, tuple[str, ScrapedProduct]] = {}
    scraped_at = datetime.now(UTC)
    for page in range(1, max_pages + 1):
        data = await get_feed_page(client, f"{retailer.base_url}/products.json?limit={FEED_PAGE_SIZE}&page={page}", sleep)
        items = data.get("products") or []
        stats.pages += 1
        if not items:
            break
        for item in items:
            stats.seen += 1
            product, reason = parse_shopify_product(item, retailer, scraped_at)
            if product is None:
                stats.skipped[reason] += 1
                continue
            published = item.get("published_at") or item.get("created_at") or ""
            found.setdefault(product.product_id, (published, product))
        if len(items) < FEED_PAGE_SIZE:
            break  # last page
    newest = sorted(found.values(), key=lambda pair: pair[0], reverse=True)
    products = [product for _, product in newest[:max_products]]
    stats.kept = len(products)
    if len(newest) > max_products:
        stats.skipped["over_brand_limit"] += len(newest) - max_products
    return products, stats
