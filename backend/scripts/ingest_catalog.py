"""Build the product catalog from the command line (spec §10).

    # Outfitters, from its official product feed (robots.txt-checked, rate-limited)
    python scripts/ingest_catalog.py feed --retailer outfitters --max 150

    # Breakout, from a hand-collected CSV (spec §10 fallback)
    python scripts/ingest_catalog.py csv --retailer breakout path/to/breakout.csv

Products go to the Supabase `products` table when SUPABASE_SERVICE_KEY is set,
otherwise to the local snapshot (CATALOG_SNAPSHOT_PATH). Add --no-sync to skip
asking a running recommendation service to re-embed.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shared.catalog_store import describe_store, save_products  # noqa: E402
from services.scraper.catalog import FEED_RETAILERS  # noqa: E402
from services.scraper.catalog_service import notify_recommendation, refresh_feeds  # noqa: E402
from services.scraper.manual_import import MANUAL_RETAILERS, parse_manual_csv  # noqa: E402


async def run(args: argparse.Namespace) -> int:
    async with httpx.AsyncClient() as client:
        if args.mode == "feed":
            result = await refresh_feeds(client, [args.retailer], args.max, notify=not args.no_sync)
            print(result.model_dump_json(indent=2))
            return 1 if result.errors else 0

        products, problems = parse_manual_csv(Path(args.csv).read_text(encoding="utf-8"), args.retailer)
        for problem in problems:
            print("  ✗", problem)
        if not products:
            print("No valid rows; nothing stored.")
            return 1
        stored_in = await save_products(client, products)
        synced = False if args.no_sync else await notify_recommendation(client)
        print(f"Stored {len(products)} {args.retailer} products in {stored_in} "
              f"({len(problems)} rows rejected). Recommendation synced: {synced}")
        return 0


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)
    feed = sub.add_parser("feed", help="crawl a retailer's product feed")
    feed.add_argument("--retailer", choices=sorted(FEED_RETAILERS), required=True)
    feed.add_argument("--max", type=int, default=None, help="products to keep (default CATALOG_MAX_PRODUCTS)")
    feed.add_argument("--no-sync", action="store_true")
    csv_ = sub.add_parser("csv", help="import a hand-collected CSV")
    csv_.add_argument("--retailer", choices=sorted(MANUAL_RETAILERS), required=True)
    csv_.add_argument("csv")
    csv_.add_argument("--no-sync", action="store_true")
    args = ap.parse_args()
    print(f"Catalog store: {describe_store()}")
    return asyncio.run(run(args))


if __name__ == "__main__":
    raise SystemExit(main())
