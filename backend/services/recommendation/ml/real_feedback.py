"""Real training rows from real users (spec §23.26).

    impressions (what the ranker showed a user, with the exact model inputs)
  + user_feedback (that user's "loved" / "not for me" on those products)
  = labelled result lists for LambdaRank and labelled rows for the validator.

Grades: loved -> 4, "not for me" -> 0, shown but not reacted to -> 2 (neutral:
an ignored product is weak evidence either way). Only lists with at least one
reaction are used. Rows logged under a different feature list (an older model
version) are skipped, never misread. No user id or text reaches the model:
only the 19 numbers and the grade.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field

import httpx

from shared.supabase_client import service_count, service_insert, service_select
from services.recommendation.ml.features import FEATURE_NAMES

IMPRESSIONS_TABLE = "recommendation_impressions"
LABELS = {"loved_fit": 4, "disliked": 0}
NEUTRAL = 2
PAGE = 1000
MAX_IMPRESSIONS = 300_000


def feature_set_id() -> str:
    """Short id of the feature list, stored with each impression."""
    return hashlib.sha1(",".join(FEATURE_NAMES).encode()).hexdigest()[:8]


@dataclass
class RealData:
    rows: list[list[float]] = field(default_factory=list)
    grades: list[int] = field(default_factory=list)
    groups: list[int] = field(default_factory=list)
    reactions: int = 0  # labelled rows (loved + not for me)
    skipped_old_features: int = 0


def build_groups(impressions: list[dict], feedback: list[dict]) -> RealData:
    """Join impressions with reactions into labelled result lists."""
    reaction: dict[tuple[str, str], int] = {}
    for f in feedback:
        label = LABELS.get(f.get("feedback_type"))
        if label is not None and f.get("user_id") and f.get("product_id"):
            reaction[(str(f["user_id"]), str(f["product_id"]))] = label

    current = feature_set_id()
    by_request: dict[str, list[dict]] = {}
    data = RealData()
    for imp in impressions:
        feats = imp.get("features")
        version = str(imp.get("model_version") or "")
        if not isinstance(feats, list) or len(feats) != len(FEATURE_NAMES) or not version.endswith(f":{current}"):
            data.skipped_old_features += 1
            continue
        by_request.setdefault(str(imp.get("request_id")), []).append(imp)

    for rows in by_request.values():
        rows.sort(key=lambda r: r.get("rank", 0))
        labels = [reaction.get((str(r.get("user_id")), str(r.get("product_id")))) for r in rows]
        if len(rows) < 2 or all(label is None for label in labels):
            continue
        for r, label in zip(rows, labels):
            data.rows.append([float(v) for v in r["features"]])
            data.grades.append(NEUTRAL if label is None else label)
            data.reactions += label is not None
        data.groups.append(len(rows))
    return data


async def _pages(client: httpx.AsyncClient, table: str, params: dict[str, str], cap: int) -> list[dict]:
    out, offset = [], 0
    while len(out) < cap:
        page = await service_select(client, table, {**params, "limit": str(PAGE), "offset": str(offset)})
        out.extend(page)
        if len(page) < PAGE:
            break
        offset += PAGE
    return out[:cap]


async def fetch_real_data(client: httpx.AsyncClient) -> RealData:
    impressions = await _pages(client, IMPRESSIONS_TABLE, {
        "select": "request_id,user_id,product_id,rank,features,model_version",
        "order": "created_at.desc"}, MAX_IMPRESSIONS)
    feedback = await _pages(client, "user_feedback", {
        "select": "user_id,product_id,feedback_type",
        "feedback_type": "in.(loved_fit,disliked)", "order": "created_at.asc"}, MAX_IMPRESSIONS)
    return build_groups(impressions, feedback)


async def count_new_reactions(client: httpx.AsyncClient, since: str | None) -> int:
    filters = {"feedback_type": "in.(loved_fit,disliked)"}
    if since:
        filters["created_at"] = f"gt.{since}"
    return await service_count(client, "user_feedback", filters)


async def log_impressions(client: httpx.AsyncClient, user_id: str, rows: list[tuple[str, int, list[float]]],
                          model_version: str) -> None:
    """One row per shown product (product id, rank, model inputs). The caller
    makes this best effort; it never affects the user's response."""
    request_id = str(uuid.uuid4())
    payload = [{"request_id": request_id, "user_id": user_id, "product_id": pid, "rank": rank,
                "features": [round(float(v), 4) for v in feats],
                "model_version": f"{model_version}:{feature_set_id()}"} for pid, rank, feats in rows]
    if payload:
        await service_insert(client, IMPRESSIONS_TABLE, payload)  # PostgREST takes a list as a bulk insert
