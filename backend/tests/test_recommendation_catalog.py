"""Spec §7 recommendation: size gate, query text, ranking, embedding cache,
POST /recommend. A deterministic fake embedder stands in for FashionCLIP."""

import asyncio
import hashlib
import io
from datetime import UTC, datetime

import httpx
import numpy as np
import pytest

pytest.importorskip("pyarrow")

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

import services.recommendation.main as rec  # noqa: E402
from shared.schemas.catalog import ScrapedProduct  # noqa: E402
from shared.schemas.recommendation import CvSummary, RecommendProfile, SessionInputs  # noqa: E402
from services.recommendation.catalog_index import CatalogIndex, fetch_image  # noqa: E402
from services.recommendation.ranking import build_query_text, rank, size_fit  # noqa: E402

NOW = datetime(2026, 10, 23, tzinfo=UTC)
DIM = 8


def product(pid, *, gender="men", price=2000.0, sizes=("S", "M"), slot="upper", image=None, name=None, chart=None):
    return ScrapedProduct(
        product_id=f"outfitters:{pid}", retailer="outfitters", name=name or pid,
        product_url=f"https://outfitters.com.pk/products/{pid}",
        image_url=image or f"https://cdn.shopify.com/{pid}.jpg", image_urls=[],
        price=price, sizes=list(sizes), all_sizes=list(sizes), category="tees", tryon_category=slot,
        gender=gender, size_chart=chart, source="shopify_feed", scraped_at=NOW,
    )


# Real Outfitters charts (Oct 2026), already converted to circumferences (cm).
JEANS_CHART = {"30": {"waist_cm": 87.0, "hip_cm": 105.0}, "32": {"waist_cm": 92.0, "hip_cm": 110.0},
               "34": {"waist_cm": 97.0, "hip_cm": 115.0}, "36": {"waist_cm": 102.0, "hip_cm": 120.0}}
TEE_CHART = {"S": {"chest_cm": 110.0}, "M": {"chest_cm": 116.0}, "L": {"chest_cm": 122.0}, "XL": {"chest_cm": 128.0}}


class FakeEmbedder:
    """Image vector derived from the image's pixel colour; text vector from a hash."""

    model_name = "fake-clip"
    dim = DIM

    def __init__(self):
        self.image_calls = 0

    def embed_images(self, images):
        self.image_calls += len(images)
        out = []
        for img in images:
            r, g, b = img.getpixel((0, 0))
            v = np.array([r, g, b, 1, 0, 0, 0, 0], dtype=np.float32)
            out.append(v / np.linalg.norm(v))
        return np.stack(out)

    def embed_texts(self, texts):
        out = []
        for t in texts:
            seed = int(hashlib.md5(t.encode()).hexdigest()[:8], 16)
            v = np.random.default_rng(seed).random(DIM).astype(np.float32)
            out.append(v / np.linalg.norm(v))
        return np.stack(out)


def png(color) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (4, 4), color).save(buf, "PNG")
    return buf.getvalue()


COLORS = {"red": (255, 0, 0), "green": (0, 255, 0), "blue": (0, 0, 255)}


def image_transport(fail: set[str] = frozenset()):
    def handler(req):
        name = req.url.path.rsplit("/", 1)[-1].split(".")[0]
        if name in fail:
            return httpx.Response(404)
        color = next((c for k, c in COLORS.items() if k in name), (128, 128, 128))
        return httpx.Response(200, content=png(color), headers={"content-type": "image/png"})

    return httpx.MockTransport(handler)


# ── size / fit (product charts, no cross-system guessing) ─────────────────


def test_chart_picks_smallest_fitting_size_in_stock():
    jeans = product("j", sizes=["30", "32", "34"], chart=JEANS_CHART)
    fit = size_fit(jeans, "M", {"waist_cm": 89, "hip_cm": 100})
    assert (fit.compatible, fit.recommended_size, fit.basis) == (True, "32", "size_chart")


def test_chart_size_out_of_stock_is_incompatible():
    jeans = product("j", sizes=["30"], chart=JEANS_CHART)
    fit = size_fit(jeans, None, {"waist_cm": 89})
    assert (fit.compatible, fit.recommended_size) == (False, "32")
    assert "out of stock" in fit.note


def test_chart_nothing_big_enough():
    fit = size_fit(product("j", sizes=["30", "36"], chart=JEANS_CHART), None, {"waist_cm": 110})
    assert fit.compatible is False and fit.recommended_size is None


def test_chart_chest_needs_ease():
    tee = product("t", sizes=["S", "M", "L"], chart=TEE_CHART)
    assert size_fit(tee, None, {"chest_cm": 104}).recommended_size == "S"  # 110 >= 104 + 4
    assert size_fit(tee, None, {"chest_cm": 108}).recommended_size == "M"  # 110 < 112


def test_chart_beats_the_letter_size():
    # CV says S, but this tee's own chart says the user needs M.
    tee = product("t", sizes=["S", "M"], chart=TEE_CHART)
    fit = size_fit(tee, "S", {"chest_cm": 108})
    assert (fit.recommended_size, fit.basis) == ("M", "size_chart")


def test_no_chart_letter_sizes_match_letters_only():
    tee = product("t", sizes=["S", "M"])
    assert size_fit(tee, "M", {}).compatible is True
    assert size_fit(tee, "L", {}).compatible is False


def test_no_chart_waist_sizes_are_never_converted():
    # The old generic chart said men's M = waist 30-32: false for real jeans
    # (Outfitters' "30" has an 87 cm waist). Now: unknown, with the real sizes.
    jeans = product("j", sizes=["30", "32"])
    fit = size_fit(jeans, "M", {"waist_cm": 80})
    assert fit.compatible is None and fit.recommended_size is None and fit.basis == "unknown"
    assert "30, 32" in fit.note


JOGGER_CHART = {  # elastic waist: relaxed 70-88, stretches to 90-108
    "S": {"waist_relaxed_cm": 70.0, "waist_stretched_cm": 90.0},
    "M": {"waist_relaxed_cm": 76.0, "waist_stretched_cm": 96.0},
}


def test_elastic_waist_fits_up_to_stretched_and_warns_only_from_relaxed():
    jogger = product("j", sizes=["S", "M"], chart=JOGGER_CHART)
    snug = size_fit(jogger, None, {"waist_cm": 72})
    assert (snug.recommended_size, snug.compatible) == ("S", True) and "loose" not in snug.note
    stretched = size_fit(jogger, None, {"waist_cm": 92})  # past S's 90 stretch
    assert stretched.recommended_size == "M"
    assert size_fit(jogger, None, {"waist_cm": 97}).compatible is False


def test_one_size_fits():
    assert size_fit(product("cap", sizes=["FREE"]), "XL", {}).compatible is True


def test_query_text_is_readable_natural_language():
    text = build_query_text(
        RecommendProfile(gender="female", style_preferences=["Casual", "Minimalist"]),
        SessionInputs(occasion="wedding", mood="elegant", color_pref="navy", budget_max=5000),
        CvSummary(body_type="hourglass", skin_tone="medium", estimated_size="M"),
    )
    assert text == ("elegant navy outfit for a wedding for a woman with an hourglass body type, "
                    "medium skin tone, size M, budget under 5000 PKR, style: casual, minimalist")
    assert build_query_text(RecommendProfile(), SessionInputs(), CvSummary()) == "outfit"


def test_rank_filters_before_scoring_and_sorts_by_cosine():
    products = [
        product("near", sizes=["M"]),
        product("far", sizes=["M"]),
        product("women", gender="women", sizes=["M"]),
        product("pricey", price=9000, sizes=["M"]),
        product("no_m", sizes=["S"]),
        product("unisex", gender="unisex", sizes=["M"]),
        product("jeans", sizes=["30", "32"]),  # fit unknown: kept, flagged
    ]
    q = np.array([1, 0, 0, 0, 0, 0, 0, 0], dtype=np.float32)
    vecs = {"near": [1, 0.1], "far": [0.1, 1], "unisex": [0.6, 0.6], "jeans": [0.3, 1]}
    matrix = np.stack([
        np.array(vecs.get(p.product_id.split(":")[1], [0, 1]) + [0] * 6, dtype=np.float32) for p in products
    ])
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    rows, removed = rank(products, matrix, q, gender="male", size="M", budget_max=5000, top_n=10)
    assert [p.product_id.split(":")[1] for p, _, _ in rows] == ["near", "unisex", "jeans", "far"]
    assert [fit.compatible for _, _, fit in rows] == [True, True, None, True]
    assert removed == {"gender": 1, "budget": 1, "size": 1}
    assert rows[0][1] > rows[1][1] > rows[2][1] > rows[3][1]


# ── embedding cache ───────────────────────────────────────────────────────


def test_sync_embeds_once_reuses_and_reacts_to_changes(tmp_path):
    index = CatalogIndex(str(tmp_path / "emb.parquet"))
    emb = FakeEmbedder()
    red, green = product("red"), product("green")

    async def sync(items):
        async with httpx.AsyncClient(transport=image_transport()) as c:
            return await index.sync(c, emb, items)

    s1 = asyncio.run(sync([red, green]))
    assert (s1.embedded, s1.reused, emb.image_calls) == (2, 0, 2)
    assert index.matrix.shape == (2, DIM)

    fresh = CatalogIndex(str(tmp_path / "emb.parquet"))  # survives a restart
    async def sync_fresh(items):
        async with httpx.AsyncClient(transport=image_transport()) as c:
            return await fresh.sync(c, emb, items)

    s2 = asyncio.run(sync_fresh([red, green]))
    assert (s2.embedded, s2.reused, emb.image_calls) == (0, 2, 2)

    green_new_photo = product("green", image="https://cdn.shopify.com/blue-green.jpg")
    s3 = asyncio.run(sync_fresh([green_new_photo]))  # red removed, green's image changed
    assert (s3.embedded, s3.dropped) == (1, 1)
    assert fresh.ids == ["outfitters:green"]


def test_failed_image_is_skipped_not_fatal(tmp_path):
    index = CatalogIndex(str(tmp_path / "emb.parquet"))

    async def run():
        async with httpx.AsyncClient(transport=image_transport(fail={"broken"})) as c:
            return await index.sync(c, FakeEmbedder(), [product("red"), product("broken")])

    stats = asyncio.run(run())
    assert (stats.embedded, stats.failed) == (1, 1)
    assert index.ids == ["outfitters:red"]


def test_image_fetch_only_from_allowed_hosts():
    async def run(url):
        async with httpx.AsyncClient(transport=image_transport()) as c:
            return await fetch_image(c, url)

    with pytest.raises(ValueError):
        asyncio.run(run("https://evil.example/x.jpg"))
    with pytest.raises(ValueError):
        asyncio.run(run("http://cdn.shopify.com/x.jpg"))
    assert asyncio.run(run("https://cdn.shopify.com/red.jpg")).size == (4, 4)


# ── POST /recommend ───────────────────────────────────────────────────────


@pytest.fixture
def client(tmp_path, monkeypatch):
    index = CatalogIndex(str(tmp_path / "emb.parquet"))
    with TestClient(rec.app) as c:
        monkeypatch.setattr(rec, "_index", index)
        yield c, index


def test_recommend_returns_503_while_model_loads(client, monkeypatch):
    c, _ = client
    monkeypatch.setattr(rec, "_embedder", None)
    monkeypatch.setattr(rec, "_model_error", None)
    res = c.post("/recommend", json={})
    assert res.status_code == 503 and res.json()["error"]["code"] == "MODEL_LOADING"


def test_recommend_spec_contract(client, monkeypatch):
    c, index = client
    emb = FakeEmbedder()
    monkeypatch.setattr(rec, "_embedder", emb)

    async def fill():
        async with httpx.AsyncClient(transport=image_transport()) as h:
            await index.sync(h, emb, [product("red", sizes=["M", "L"]), product("blue", sizes=["S"]),
                                      product("green", gender="women", sizes=["M"])])

    asyncio.run(fill())
    body = c.post("/recommend", json={
        "profile": {"gender": "male"},
        "session_inputs": {"occasion": "eid", "budget_max": 5000},
        "cv_analysis": {"estimated_size": "M"},
        "top_n": 5,
    }).json()
    assert [r["product_id"] for r in body["recommendations"]] == ["outfitters:red"]
    r = body["recommendations"][0]
    assert set(r) >= {"product_id", "name", "image_url", "price", "similarity_score", "available_sizes"}
    assert r["available_sizes"] == ["M", "L"] and r["size_compatible"] is True
    assert (r["recommended_size"], r["size_basis"]) == ("M", "label")
    assert body["filtered_out"] == {"gender": 1, "size": 1}
    assert body["catalog_size"] == 3
    assert "outfit for an eid for a man" in body["query_text"]
