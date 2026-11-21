"""Visual review of FashionCLIP recommendations on the real catalog.

    python scripts/review_recommendations.py OUT_DIR

Loads FashionCLIP, syncs the embedding cache with the catalog (same code
path as the service), runs a few example requests and saves one image grid
per request (top results with score, price, sizes) for checking by eye.
"""

from __future__ import annotations

import asyncio
import sys
import time
from pathlib import Path

import httpx
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shared.schemas.recommendation import CvSummary, RecommendProfile, SessionInputs  # noqa: E402
from services.recommendation.catalog_index import CatalogIndex, fetch_image  # noqa: E402
from services.recommendation.embeddings import FashionClip  # noqa: E402
from services.recommendation.ranking import build_query_text, rank  # noqa: E402

EXAMPLES = [
    ("men_formal", RecommendProfile(gender="male", chest_cm=96, waist_cm=82, hip_cm=100), SessionInputs(occasion="office meeting", mood="formal"),
     CvSummary(estimated_size="M")),
    ("men_casual_black", RecommendProfile(gender="male", style_preferences=["streetwear"]),
     SessionInputs(occasion="hangout with friends", color_pref="black", budget_max=3000), CvSummary(estimated_size="L")),
    ("women_summer", RecommendProfile(gender="female"), SessionInputs(occasion="summer day out", mood="fresh"),
     CvSummary(estimated_size="S")),
    ("women_denim", RecommendProfile(gender="female"), SessionInputs(occasion="college", color_pref="blue denim"),
     CvSummary(estimated_size="M")),
]
TOP = 5
TILE = (220, 300)


async def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    model = FashionClip()
    print(f"FashionCLIP loaded in {time.perf_counter() - t0:.1f}s ({model.dim}-d)")
    index = CatalogIndex()
    async with httpx.AsyncClient() as client:
        t0 = time.perf_counter()
        stats = await index.sync(client, model)
        print(f"sync: {stats} in {time.perf_counter() - t0:.1f}s")
        products = [index.products[pid] for pid in index.ids]
        for name, profile, session, cv in EXAMPLES:
            text = build_query_text(profile, session, cv)
            t0 = time.perf_counter()
            qv = model.embed_texts([text])[0]
            rows, removed = rank(products, index.matrix, qv, gender=profile.gender, size=cv.estimated_size,
                                 budget_max=session.budget_max, top_n=TOP,
                                 body={"chest_cm": profile.chest_cm, "waist_cm": profile.waist_cm, "hip_cm": profile.hip_cm})
            ms = (time.perf_counter() - t0) * 1000
            print(f"\n[{name}] {text}\n  ranked in {ms:.0f} ms, filtered out {dict(removed)}")
            grid = Image.new("RGB", (TILE[0] * max(1, len(rows)), TILE[1] + 60), "white")
            draw = ImageDraw.Draw(grid)
            for i, (p, score, fit) in enumerate(rows):
                print(f"  {score:.3f}  {p.name} | {p.category} | PKR {p.price:.0f} | {p.sizes} | "
                      f"size {fit.recommended_size} ({fit.basis}, compatible={fit.compatible}) {fit.note}")
                img = await fetch_image(client, p.image_url)
                img.thumbnail(TILE)
                grid.paste(img, (i * TILE[0], 0))
                draw.text((i * TILE[0] + 4, TILE[1] + 4), f"{score:.3f} PKR {p.price:.0f}", fill="black")
                draw.text((i * TILE[0] + 4, TILE[1] + 22), p.name[:30], fill="black")
            grid.save(out / f"{name}.jpg")


if __name__ == "__main__":
    asyncio.run(main(Path(sys.argv[1])))
