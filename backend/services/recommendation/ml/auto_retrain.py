"""Self-learning for the recommendation models (spec §23.26).

    python -m services.recommendation.ml.auto_retrain --auto    # what the schedule runs
    python -m services.recommendation.ml.auto_retrain --force   # retrain now, whatever the count
    python -m services.recommendation.ml.auto_retrain --rollback
    python -m services.recommendation.ml.auto_retrain --status

One run:
1. Counts users' new reactions ("loved" / "not for me") since the live model
   was trained. Fewer than AUTO_RETRAIN_MIN_FEEDBACK: nothing to do.
2. Builds real training lists: what the ranker showed each user (impressions,
   with the exact model inputs) labelled by their reactions (real_feedback.py).
   A fifth of the real lists is held out for the safety gate.
3. Trains a challenger (LightGBM ranker + Random Forest validator) on the
   generated shoppers plus the real lists, repeated REAL_REPEAT times so real
   users weigh more than generated ones.
4. Safety gate: the challenger replaces the live model only if its NDCG@10 on
   the held-out REAL lists is at least the live model's minus GATE_TOLERANCE
   (with too few real lists to judge: if its validation NDCG is). Otherwise
   it is discarded and the live model stays.
5. Promotes (versioned, atomic; the service reloads it by itself), records
   the attempt in models/history.json, and deletes impressions older than
   IMPRESSION_RETENTION_DAYS.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import random
import shutil
import sys
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import numpy as np

from shared.config import settings
from shared.model_registry import (
    RetrainBusy,
    append_history,
    new_version,
    promote,
    read_history,
    retrain_lock,
    rollback,
)
from shared.supabase_client import service_delete
from services.recommendation.ml import real_feedback
from services.recommendation.ml.train import MODEL_DIR, Dataset, build_dataset, ndcg_at, train_models

logger = logging.getLogger("smartfit.recommendation.retrain")

MODEL_FILES = ["ranker.txt", "validator.joblib"]
CARD = "model_card.json"
REAL_REPEAT = 3
GATE_TOLERANCE = 0.005
MIN_HOLDOUT_LISTS = 10
SYNTHETIC_QUERIES = 600


@dataclass
class Outcome:
    status: str  # "skipped" | "promoted" | "rejected" | "busy" | "failed"
    reason: str
    version: str | None = None
    metrics: dict | None = None


def _card(model_dir: Path) -> dict | None:
    try:
        return json.loads((model_dir / CARD).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _split(real: real_feedback.RealData, seed: int) -> tuple[Dataset, Dataset]:
    """Real lists -> (train, holdout); the holdout is a fifth of the lists."""
    starts, at = [], 0
    for g in real.groups:
        starts.append(at)
        at += g
    order = list(range(len(real.groups)))
    random.Random(seed).shuffle(order)
    n_hold = len(order) // 5 if len(order) >= MIN_HOLDOUT_LISTS else 0
    hold_ids = set(order[:n_hold])
    train, hold = Dataset(), Dataset()
    for i, (start, size) in enumerate(zip(starts, real.groups)):
        target = hold if i in hold_ids else train
        target.rows += real.rows[start:start + size]
        target.grades += real.grades[start:start + size]
        target.groups.append(size)
    return train, hold


def _repeat(data: Dataset, times: int) -> Dataset:
    out = Dataset()
    for _ in range(times):
        out.rows += data.rows
        out.grades += data.grades
        out.groups += data.groups
    return out


def holdout_ndcg(model_dir: Path, hold: Dataset) -> float | None:
    """NDCG@10 of the model in `model_dir` on held-out real lists."""
    if not hold.groups or not (model_dir / CARD).exists():
        return None
    import lightgbm as lgb

    booster = lgb.Booster(model_file=str(model_dir / "ranker.txt"))
    scores = booster.predict(np.asarray(hold.rows, dtype=np.float64))
    return ndcg_at(scores, np.asarray(hold.grades), hold.groups)


def gate(champion_card: dict | None, challenger_card: dict, champion_real: float | None,
         challenger_real: float | None) -> tuple[bool, str]:
    """Should the challenger replace the live model?"""
    if champion_card is None:
        return True, "no live model yet"
    if champion_real is not None and challenger_real is not None:
        if challenger_real >= champion_real - GATE_TOLERANCE:
            return True, f"real-user NDCG@10 {challenger_real:.4f} vs live {champion_real:.4f}"
        return False, f"worse on real users: NDCG@10 {challenger_real:.4f} vs live {champion_real:.4f}"
    new = challenger_card["metrics"]["ndcg10_lightgbm"]
    old = (champion_card.get("metrics") or {}).get("ndcg10_lightgbm", 0.0)
    if new >= old - GATE_TOLERANCE:
        return True, f"too few real lists to judge; validation NDCG@10 {new:.4f} vs live {old:.4f}"
    return False, f"worse on validation: NDCG@10 {new:.4f} vs live {old:.4f}"


async def _load_catalog() -> list[dict]:
    from services.recommendation.ml.train import _load_catalog as load

    return await load()


async def run(model_dir: Path = MODEL_DIR, *, force: bool = False, seed: int = 42,
              synthetic_queries: int = SYNTHETIC_QUERIES, client: httpx.AsyncClient | None = None,
              catalog: list[dict] | None = None) -> Outcome:
    if not (settings.supabase_url and settings.supabase_service_key):
        return Outcome("skipped", "Supabase isn't configured: no real feedback to learn from")
    own_client = client is None
    client = client or httpx.AsyncClient(timeout=60)
    try:
        with retrain_lock(model_dir):
            return await _run_locked(model_dir, force, seed, synthetic_queries, client, catalog)
    except RetrainBusy as exc:
        return Outcome("busy", str(exc))
    finally:
        if own_client:
            await client.aclose()


async def _run_locked(model_dir: Path, force: bool, seed: int, synthetic_queries: int,
                      client: httpx.AsyncClient, catalog: list[dict] | None) -> Outcome:
    champion = _card(model_dir)
    since = champion.get("trained_at") if champion else None
    new = await real_feedback.count_new_reactions(client, since)
    if not force and new < settings.auto_retrain_min_feedback:
        outcome = Outcome("skipped", f"{new} new reactions since the last training "
                                     f"(need {settings.auto_retrain_min_feedback})")
        logger.info(outcome.reason)
        return outcome

    real = await real_feedback.fetch_real_data(client)
    if not real.groups and not force:
        outcome = Outcome("skipped", f"{new} new reactions, but none on products the learned ranker "
                                     "showed (no impressions to learn from yet)")
        append_history(model_dir, {"status": outcome.status, "reason": outcome.reason})
        return outcome
    real_train, hold = _split(real, seed)

    catalog = catalog if catalog is not None else await _load_catalog()
    synthetic = build_dataset(catalog, synthetic_queries, seed)
    version = new_version()
    staging = Path(tempfile.mkdtemp(prefix="smartfit-ranker-"))
    try:
        source = (f"weak (stylist rules + HSV colour harmony) + {real.reactions} real reactions "
                  f"in {len(real.groups)} real result lists")
        card = train_models(synthetic, staging, seed, source, extra_train=_repeat(real_train, REAL_REPEAT),
                            version=version)
        champion_real = holdout_ndcg(model_dir, hold)
        challenger_real = holdout_ndcg(staging, hold)
        card["real_holdout"] = {"lists": len(hold.groups), "ndcg10": challenger_real,
                                "live_model_ndcg10": champion_real}
        (staging / CARD).write_text(json.dumps(card, indent=2), encoding="utf-8")
        ok, why = gate(champion, card, champion_real, challenger_real)
        entry = {"version": version, "status": "promoted" if ok else "rejected", "reason": why,
                 "real_reactions": real.reactions, "real_lists": len(real.groups),
                 "holdout_lists": len(hold.groups), "metrics": card["metrics"]}
        if ok:
            promote(staging, model_dir, MODEL_FILES, CARD, version)
        append_history(model_dir, entry)
        logger.info("%s %s: %s", entry["status"], version, why)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    await _prune_impressions(client)
    return Outcome(entry["status"], why, version, card["metrics"])


async def _prune_impressions(client: httpx.AsyncClient) -> None:
    cutoff = datetime.now(UTC) - timedelta(days=settings.impression_retention_days)
    try:
        n = await service_delete(client, real_feedback.IMPRESSIONS_TABLE, {"created_at": f"lt.{cutoff.isoformat()}"})
        if n:
            logger.info("deleted %d impressions older than %d days", n, settings.impression_retention_days)
    except Exception as exc:  # retention is housekeeping: never fail the run for it
        logger.info("impression pruning skipped (%s)", exc)


def main() -> int:
    ap = argparse.ArgumentParser(description="Self-learning retraining of the recommendation models.")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--auto", action="store_true", help="retrain only if there is enough new feedback")
    mode.add_argument("--force", action="store_true", help="retrain now")
    mode.add_argument("--rollback", action="store_true", help="make the previous model live again")
    mode.add_argument("--status", action="store_true", help="show the live model and recent attempts")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    if args.status:
        print(json.dumps({"live": _card(MODEL_DIR), "history": read_history(MODEL_DIR)}, indent=2))
        return 0
    if args.rollback:
        version = rollback(MODEL_DIR, MODEL_FILES, CARD)
        if version:
            append_history(MODEL_DIR, {"version": version, "status": "rolled_back", "reason": "manual rollback"})
        print(f"rolled back to {version}" if version else "no earlier version to roll back to")
        return 0 if version else 1
    outcome = asyncio.run(run(force=args.force))
    print(f"{outcome.status}: {outcome.reason}")
    return 1 if outcome.status == "failed" else 0


if __name__ == "__main__":
    sys.exit(main())
