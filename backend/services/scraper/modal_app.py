"""Cloud runner for the catalog scraper (Modal; the user's choice, 13 Nov 2026).

Shopify rate-limits the developer's home internet address for every store
(HTTP 429 on all product pages), so the catalog refresh reads the brands from
a Modal server instead, the way the deployed scraper would run on its own
server. Nothing about the scraping changes (services/scraper/polite.py):

* the honest user agent (SCRAPER_USER_AGENT), robots.txt checked first,
* 2 s between requests to a store, one brand at a time (max_containers=1),
* a 429 is waited out once as the store asks, then the brand is skipped and
  the whole refresh stops (catalog_service.refresh_feeds); a robots.txt
  "no" is never retried.

Only product data travels: the function returns the products it read and
the local scraper service saves them as before. No Supabase key, .env or user
data is ever sent to Modal.

    modal deploy backend/services/scraper/modal_app.py      # once, and after scraper code changes
    modal run backend/services/scraper/modal_app.py::check --brand outfitters   # one brand, 20 products
"""

from __future__ import annotations

from pathlib import Path

import modal

APP_NAME = "smartfit-scraper"
FUNCTION_NAME = "crawl_brand"

# backend/ on the deploying PC. Inside the container this file sits at /root and
# the code was already copied in, so the path only matters locally.
_PARENTS = Path(__file__).resolve().parents
_BACKEND = _PARENTS[2] if len(_PARENTS) > 2 else Path("/root/app")
_IGNORE = ["**/__pycache__/**", "**/*.pyc"]

image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("httpx==0.27.2", "protego==0.3.1", "pydantic==2.9.2", "pydantic-settings==2.6.1")
    .env({"PYTHONPATH": "/root/app", "CATALOG_REFRESH_HOURS": "0"})
    # Code only: shared/ (settings, schemas, brand list) and the scraper package.
    .add_local_file(_BACKEND / "services" / "__init__.py", "/root/app/services/__init__.py")
    .add_local_dir(_BACKEND / "services" / "scraper", "/root/app/services/scraper", ignore=_IGNORE)
    .add_local_dir(_BACKEND / "shared", "/root/app/shared", ignore=_IGNORE)
)

app = modal.App(APP_NAME, image=image)


@app.function(cpu=0.5, memory=1024, timeout=3600, max_containers=1, retries=0)
def crawl_brand(key: str, max_products: int, previous_charts: list[dict]) -> dict:
    """Read one brand's feed (and its size charts) politely.

    previous_charts: [{"product_id", "size_chart_tag", "size_chart_raw"}] from
    the last refresh, so unchanged size charts aren't fetched again.
    Returns {"ok": True, "products": [...], "stats": {...}} or
    {"ok": False, "kind": "robots" | "rate_limited" | "failed" | "unknown_brand", "message": str}."""
    import asyncio
    import logging
    from types import SimpleNamespace

    import httpx

    from services.scraper.catalog import FEED_RETAILERS, FeedRateLimited, attach_size_charts, crawl_shopify_feed
    from services.scraper.polite import PoliteClient, RobotsDisallowed

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    retailer = FEED_RETAILERS.get(key)
    if retailer is None:
        return {"ok": False, "kind": "unknown_brand", "message": f"{key} is not a feed brand"}
    previous = {c["product_id"]: SimpleNamespace(size_chart_tag=c.get("size_chart_tag"),
                                                 size_chart_raw=c.get("size_chart_raw"))
                for c in previous_charts if c.get("product_id")}

    async def run() -> dict:
        async with httpx.AsyncClient() as client:
            polite = PoliteClient(client)
            batch, stats = await crawl_shopify_feed(polite, retailer, max_products)
            charts: dict = {}
            if retailer.size_chart_shop:
                charts = dict(await attach_size_charts(polite, retailer, batch, previous))
        return {"ok": True, "products": [p.model_dump(mode="json") for p in batch],
                "stats": {"pages": stats.pages, "seen": stats.seen, "kept": len(batch),
                          "skipped": dict(stats.skipped), "size_charts": charts}}

    try:
        return asyncio.run(run())
    except RobotsDisallowed as exc:
        return {"ok": False, "kind": "robots", "message": str(exc)}
    except FeedRateLimited as exc:
        return {"ok": False, "kind": "rate_limited", "message": str(exc)}
    except (httpx.HTTPError, RuntimeError, ValueError) as exc:
        return {"ok": False, "kind": "failed", "message": f"{type(exc).__name__}: {exc}"[:300]}


@app.local_entrypoint()
def check(brand: str = "outfitters", limit: int = 20) -> None:
    """Quick check from your PC: read one brand in the cloud, print a summary (saves nothing)."""
    res = crawl_brand.remote(brand, limit, [])
    if not res["ok"]:
        print(f"{brand}: NOT read ({res['kind']}): {res['message']}")
        return
    print(f"{brand}: {len(res['products'])} products, stats {res['stats']}")
    for p in res["products"][:5]:
        print(f"  {p['name']} | PKR {p['price']} | {p['gender']} | try-on: {p['tryon_category']}")
