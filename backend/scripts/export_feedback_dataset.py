"""Export users' recommendation feedback as a labelled dataset (spec §23.15).

    python scripts/export_feedback_dataset.py OUT.jsonl      # from backend/, needs SUPABASE_SERVICE_KEY

Every row of public.user_feedback becomes one JSON line:
  {"user": <pseudonym>, "kind": "product" | "quiz", "label": 1 | 0 | <choice>,
   "source": "app" | "notification", "product": {...snapshot...}, "quiz": "...", "at": "..."}

* loved_fit -> label 1, disliked ("not for me") -> label 0: training pairs for
  a ranking model (product features vs. the user's taste).
* rating rows from the style quizzes -> label = the chosen option.

User ids are replaced by a salted hash (FEEDBACK_EXPORT_SALT), so the file can
be shared for model work without exposing accounts. The live app already uses
the same feedback through the taste profile; this file is for offline training.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import httpx  # noqa: E402

from shared.supabase_client import service_select  # noqa: E402

PAGE = 1000
PRODUCT_FIELDS = ("id", "brand", "title", "category", "price_pkr", "colors", "tags", "product_url")


def pseudonym(user_id: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{user_id}".encode()).hexdigest()[:16]


def to_example(row: dict, salt: str) -> dict | None:
    """One user_feedback row -> one training example (None for kinds not used)."""
    kind, data = row.get("feedback_type"), row.get("feedback_data") or {}
    if not isinstance(data, dict):
        data = {}
    base = {"user": pseudonym(str(row.get("user_id")), salt), "source": data.get("source", "app"),
            "at": row.get("created_at")}
    if kind in ("loved_fit", "disliked"):
        product = {k: data.get(k) for k in PRODUCT_FIELDS if data.get(k) is not None}
        product.setdefault("id", row.get("product_id"))
        return base | {"kind": "product", "label": 1 if kind == "loved_fit" else 0, "product": product}
    if kind == "rating" and data.get("quiz"):
        return base | {"kind": "quiz", "quiz": data["quiz"], "label": data.get("choice")}
    return None


async def fetch_all(client: httpx.AsyncClient) -> list[dict]:
    rows, offset = [], 0
    while True:
        page = await service_select(client, "user_feedback", {
            "select": "user_id,product_id,feedback_type,feedback_data,created_at",
            "order": "created_at.asc", "limit": str(PAGE), "offset": str(offset)})
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        offset += PAGE


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out")
    args = ap.parse_args()
    salt = os.environ.get("FEEDBACK_EXPORT_SALT", "smartfit")

    async def run():
        async with httpx.AsyncClient(timeout=30) as client:
            return await fetch_all(client)

    examples = [e for e in (to_example(r, salt) for r in asyncio.run(run())) if e is not None]
    Path(args.out).write_text("".join(json.dumps(e) + "\n" for e in examples), encoding="utf-8")
    loves = sum(e["kind"] == "product" and e["label"] == 1 for e in examples)
    nopes = sum(e["kind"] == "product" and e["label"] == 0 for e in examples)
    quiz = sum(e["kind"] == "quiz" for e in examples)
    print(f"{len(examples)} examples -> {args.out} ({loves} loved, {nopes} not for me, {quiz} quiz answers)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
