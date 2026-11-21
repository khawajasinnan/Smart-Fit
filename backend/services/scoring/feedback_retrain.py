"""Feedback learning for the look score (SFR-034, spec §12, §23.25, §23.26).

    python -m services.scoring.feedback_retrain --auto      # what the schedule runs
    python -m services.scoring.feedback_retrain --force     # retrain now, whatever the count
    python -m services.scoring.feedback_retrain --rollback
    python -m services.scoring.feedback_retrain --status
    python -m services.scoring.feedback_retrain --weak-only # first training, no users yet
    python -m services.scoring.feedback_retrain --ratings r.jsonl   # + ratings from a file

Real ratings are the rows POST /feedback stores in public.user_feedback
(feedback_type "rating", product_id "look:<id>", feedback_data.kind "look")
with the component scores the user was shown. One run:

1. --auto: counts look ratings since the live model was trained; fewer than
   AUTO_RETRAIN_MIN_LOOK_RATINGS -> nothing to do.
2. A fifth of the real ratings is held out for the safety gate.
3. Formula weights (weights.json): non-negative Ridge regression of rating on
   component scores (spec §12), only with >= MIN_RATINGS training ratings,
   shrunk halfway to equal weights; kept only if they predict the held-out
   ratings at least as well as the current weights.
4. The Random Forest look validator: generated looks (weak labels) + every
   real rating weighted REAL_WEIGHT times; replaces the live one only if its
   error on the held-out real ratings is no worse than the live one's
   (+ GATE_TOLERANCE points). Promotion is versioned and atomic; the scoring
   service reloads it by itself. Every attempt goes to models/history.json.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import random
import shutil
import sys
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

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
from services.scoring.formula import COMPONENTS, WEIGHTS_FILE, load_weights
from services.scoring.look_model import FEATURES, MODEL_DIR, generate_looks, train

logger = logging.getLogger("smartfit.scoring.retrain")

MIN_RATINGS = 30
REAL_WEIGHT = 5.0
SHRINK = 0.5  # 0 = trust the regression fully, 1 = keep equal weights
GATE_TOLERANCE = 0.5  # points of mean absolute error
MIN_HOLDOUT = 10
MODEL_FILES = ["look_rf.joblib"]
CARD = "look_card.json"
SYNTHETIC_LOOKS = 6000


def rating_rows(records: list[dict]) -> tuple[list[list[float]], list[float]]:
    """Stored look feedback -> (model rows, 0..100 labels). Rows missing their
    component snapshot are skipped (nothing to learn from)."""
    rows, labels = [], []
    for r in records:
        data = r.get("feedback_data") if "feedback_data" in r else r
        if not isinstance(data, dict) or data.get("kind") != "look":
            continue
        rating, row = data.get("rating"), data.get("features")
        if not isinstance(rating, (int, float)) or not 1 <= rating <= 5:
            continue
        if not isinstance(row, list) or len(row) != len(FEATURES):
            continue
        rows.append([float(v) for v in row])
        labels.append((float(rating) - 1) * 25.0)  # 1..5 stars -> 0..100
    return rows, labels


def fit_weights(rows: list[list[float]], labels: list[float]) -> dict[str, float] | None:
    if len(rows) < MIN_RATINGS:
        return None
    from sklearn.linear_model import Ridge

    X = np.asarray(rows)[:, : len(COMPONENTS)]
    model = Ridge(alpha=1.0, positive=True, fit_intercept=True).fit(X, np.asarray(labels))
    raw = np.clip(model.coef_, 0, None)
    if raw.sum() <= 0:
        return None
    learned = raw / raw.sum()
    equal = np.full(len(COMPONENTS), 1 / len(COMPONENTS))
    mixed = SHRINK * equal + (1 - SHRINK) * learned
    return {k: round(float(w), 4) for k, w in zip(COMPONENTS, mixed)}


def formula_from_row(row: list[float], weights: dict[str, float]) -> float:
    """The look score the formula gives for a stored row (the hairstyle counts
    only when the look had one: its "known" flag)."""
    hair_index = COMPONENTS.index("hairstyle")
    present = [k for i, k in enumerate(COMPONENTS) if k != "hairstyle" or row[len(COMPONENTS) + hair_index] >= 1]
    total = sum(weights[k] for k in present) or 1.0
    return sum(weights[k] / total * row[COMPONENTS.index(k)] for k in present)


def mae(pred: list[float], labels: list[float]) -> float:
    return float(np.mean(np.abs(np.asarray(pred) - np.asarray(labels)))) if labels else float("nan")


def split(rows: list[list[float]], labels: list[float], seed: int):
    idx = list(range(len(rows)))
    random.Random(seed).shuffle(idx)
    n_hold = len(idx) // 5 if len(idx) >= MIN_HOLDOUT else 0
    hold, keep = set(idx[:n_hold]), idx[n_hold:]
    return ([rows[i] for i in keep], [labels[i] for i in keep],
            [rows[i] for i in sorted(hold)], [labels[i] for i in sorted(hold)])


def _forest_mae(model_dir: Path, rows: list[list[float]], labels: list[float]) -> float | None:
    if not rows or not (model_dir / CARD).exists():
        return None
    import joblib

    forest = joblib.load(model_dir / "look_rf.joblib")
    return mae(list(forest.predict(np.asarray(rows))), labels)


def _card(model_dir: Path) -> dict | None:
    try:
        return json.loads((model_dir / CARD).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _write_weights(weights: dict[str, float], source: str) -> None:
    tmp = WEIGHTS_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"weights": weights, "source": source,
                               "updated_at": datetime.now(UTC).isoformat(timespec="seconds")}, indent=2),
                   encoding="utf-8")
    os.replace(tmp, WEIGHTS_FILE)


@dataclass
class Outcome:
    status: str  # "skipped" | "promoted" | "rejected" | "busy"
    reason: str
    version: str | None = None


def retrain(records: list[dict], catalog: list[dict], model_dir: Path = MODEL_DIR, *, seed: int = 42,
            looks: int = SYNTHETIC_LOOKS) -> Outcome:
    """One gated retraining from stored rating records (+ generated looks)."""
    real_rows, real_labels = rating_rows(records)
    tr_rows, tr_labels, ho_rows, ho_labels = split(real_rows, real_labels, seed)
    notes = []

    # 1. formula weights (spec §12 Ridge), kept only if not worse on the holdout
    current = load_weights()
    learned = fit_weights(tr_rows, tr_labels)
    if learned:
        if ho_rows:
            old_err = mae([formula_from_row(r, current) for r in ho_rows], ho_labels)
            new_err = mae([formula_from_row(r, learned) for r in ho_rows], ho_labels)
            if new_err <= old_err + GATE_TOLERANCE:
                _write_weights(learned, f"ridge on {len(tr_rows)} ratings; holdout MAE {new_err:.1f} vs {old_err:.1f}")
                notes.append(f"weights updated (holdout MAE {new_err:.1f} vs {old_err:.1f})")
            else:
                notes.append(f"weights kept (new ones worse: {new_err:.1f} vs {old_err:.1f})")
        else:
            notes.append("weights kept (too few ratings to check new ones)")
    else:
        notes.append(f"weights kept (<{MIN_RATINGS} ratings)")

    # 2. the Random Forest validator
    rows, labels = generate_looks(catalog, looks, seed)
    weight = [1.0] * len(rows) + [REAL_WEIGHT] * len(tr_rows)
    version = new_version()
    staging = Path(tempfile.mkdtemp(prefix="smartfit-look-"))
    try:
        source = "weak (formula + stylist cap rules)" + (f" + {len(real_rows)} real ratings" if real_rows else "")
        card = train(rows + tr_rows, labels + tr_labels, staging, seed, source, weight, version, len(real_rows))
        champion = _card(model_dir)
        old_err, new_err = _forest_mae(model_dir, ho_rows, ho_labels), _forest_mae(staging, ho_rows, ho_labels)
        card["real_holdout"] = {"ratings": len(ho_rows), "mae": new_err, "live_model_mae": old_err}
        (staging / CARD).write_text(json.dumps(card, indent=2), encoding="utf-8")
        if champion is None:
            ok, why = True, "no live model yet"
        elif old_err is not None and new_err is not None:
            ok = new_err <= old_err + GATE_TOLERANCE
            why = f"real-rating MAE {new_err:.1f} vs live {old_err:.1f}"
        else:
            old_v = (champion.get("metrics") or {}).get("valid_mae", float("inf"))
            ok = card["metrics"]["valid_mae"] <= old_v + GATE_TOLERANCE
            why = f"too few real ratings to judge; validation MAE {card['metrics']['valid_mae']:.1f} vs live {old_v:.1f}"
        if ok:
            promote(staging, model_dir, MODEL_FILES, CARD, version)
        status = "promoted" if ok else "rejected"
        append_history(model_dir, {"version": version, "status": status, "reason": why, "notes": notes,
                                   "real_ratings": len(real_rows), "metrics": card["metrics"]})
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return Outcome(status, f"{why}; " + "; ".join(notes), version)


async def _supabase_ratings() -> list[dict]:
    import httpx

    from shared.supabase_client import service_select

    params = {"select": "feedback_data,created_at", "feedback_type": "eq.rating",
              "product_id": "like.look:*", "order": "created_at.asc"}
    out, offset = [], 0
    async with httpx.AsyncClient(timeout=30) as client:
        while True:
            page = await service_select(client, "user_feedback", {**params, "limit": "1000", "offset": str(offset)})
            out.extend(page)
            if len(page) < 1000:
                break
            offset += 1000
    return out


async def _count_since(since: str | None) -> int:
    import httpx

    from shared.supabase_client import service_count

    filters = {"feedback_type": "eq.rating", "product_id": "like.look:*"}
    if since:
        filters["created_at"] = f"gt.{since}"
    async with httpx.AsyncClient(timeout=30) as client:
        return await service_count(client, "user_feedback", filters)


async def _catalog() -> list[dict]:
    import httpx

    from shared.catalog_store import load_products

    async with httpx.AsyncClient(timeout=60) as client:
        products = await load_products(client)
    return [{"id": p.product_id, "title": p.name, "brand": p.retailer, "category": p.category,
             "colors": [c.lower() for c in p.colors], "tags": [p.gender, p.category],
             "price_pkr": p.price} for p in products]


def auto(model_dir: Path = MODEL_DIR, *, force: bool = False) -> Outcome:
    if not (settings.supabase_url and settings.supabase_service_key):
        return Outcome("skipped", "Supabase isn't configured: no real ratings to learn from")
    try:
        with retrain_lock(model_dir):
            champion = _card(model_dir)
            since = champion.get("trained_at") if champion else None
            new = asyncio.run(_count_since(since))
            if not force and new < settings.auto_retrain_min_look_ratings:
                return Outcome("skipped", f"{new} new look ratings since the last training "
                                          f"(need {settings.auto_retrain_min_look_ratings})")
            return retrain(asyncio.run(_supabase_ratings()), asyncio.run(_catalog()), model_dir)
    except RetrainBusy as exc:
        return Outcome("busy", str(exc))


def main() -> int:
    ap = argparse.ArgumentParser(description="Self-learning for the look score (weights + Random Forest).")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--auto", action="store_true", help="retrain only if there are enough new ratings")
    mode.add_argument("--force", action="store_true", help="retrain now from all real ratings")
    mode.add_argument("--rollback", action="store_true", help="make the previous look model live again")
    mode.add_argument("--status", action="store_true", help="show the live model and recent attempts")
    mode.add_argument("--weak-only", action="store_true", help="train on generated looks only (no users yet)")
    ap.add_argument("--ratings", type=Path, help="JSONL of stored look feedback rows (with --weak-only)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    for noisy in ("httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    if args.status:
        print(json.dumps({"live": _card(MODEL_DIR), "weights": load_weights(), "history": read_history(MODEL_DIR)},
                         indent=2))
        return 0
    if args.rollback:
        version = rollback(MODEL_DIR, MODEL_FILES, CARD)
        if version:
            append_history(MODEL_DIR, {"version": version, "status": "rolled_back", "reason": "manual rollback"})
        print(f"rolled back to {version}" if version else "no earlier version to roll back to")
        return 0 if version else 1
    if args.auto or args.force:
        outcome = auto(force=args.force)
    else:  # --weak-only (also the default): no database reads
        records = []
        if args.ratings:
            records = [json.loads(line) for line in args.ratings.read_text(encoding="utf-8").splitlines()
                       if line.strip()]
        with retrain_lock(MODEL_DIR):
            outcome = retrain(records, asyncio.run(_catalog()))
    print(f"{outcome.status}: {outcome.reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
