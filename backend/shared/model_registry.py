"""Versioned model files for the self-learning loop (spec §23.26).

A service's model folder holds the *live* files (what the service loads), a
`versions/<version>/` copy of each promoted model (the last KEEP_VERSIONS, for
rollback), `history.json` (every retraining attempt: promoted or not, and
why) and a lock so two retrains never run at once.

Promotion replaces each live file atomically (write a temp file, then
os.replace) and writes the model card last, so a service that notices the
new card always finds the matching model files next to it.
"""

from __future__ import annotations

import json
import os
import shutil
import time
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path

KEEP_VERSIONS = 3
LOCK_STALE_SECONDS = 3 * 3600
HISTORY_LIMIT = 200


class RetrainBusy(RuntimeError):
    """Another retraining is already running."""


def new_version() -> str:
    return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")


@contextmanager
def retrain_lock(model_dir: Path) -> Iterator[None]:
    model_dir.mkdir(parents=True, exist_ok=True)
    lock = model_dir / ".retrain.lock"
    if lock.exists() and time.time() - lock.stat().st_mtime > LOCK_STALE_SECONDS:
        lock.unlink(missing_ok=True)  # a crashed run left it behind
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise RetrainBusy(f"a retraining is already running ({lock})") from exc
    try:
        os.write(fd, str(os.getpid()).encode())
        os.close(fd)
        yield
    finally:
        lock.unlink(missing_ok=True)


def promote(staging: Path, live: Path, files: list[str], card_name: str, version: str) -> None:
    """Copy a trained model from `staging` into versions/<version>/ and make it
    live. `files` are the model files; `card_name` (written last) is the card."""
    archive = live / "versions" / version
    archive.mkdir(parents=True, exist_ok=True)
    for name in [*files, card_name]:
        shutil.copy2(staging / name, archive / name)
    for name in [*files, card_name]:  # the card last: it is what services watch
        tmp = live / f".{name}.tmp"
        shutil.copy2(staging / name, tmp)
        os.replace(tmp, live / name)
    prune_versions(live)


def prune_versions(live: Path, keep: int = KEEP_VERSIONS) -> None:
    root = live / "versions"
    if not root.exists():
        return
    versions = sorted((d for d in root.iterdir() if d.is_dir()), key=lambda d: d.name)
    for old in versions[:-keep]:
        shutil.rmtree(old, ignore_errors=True)


def rollback(live: Path, files: list[str], card_name: str) -> str | None:
    """Make the previous archived version live again; returns its version."""
    root = live / "versions"
    versions = sorted((d for d in root.iterdir() if d.is_dir()), key=lambda d: d.name) if root.exists() else []
    if len(versions) < 2:
        return None
    previous = versions[-2]
    for name in [*files, card_name]:
        tmp = live / f".{name}.tmp"
        shutil.copy2(previous / name, tmp)
        os.replace(tmp, live / name)
    shutil.rmtree(versions[-1], ignore_errors=True)
    return previous.name


def append_history(live: Path, entry: dict) -> None:
    path = live / "history.json"
    try:
        history = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(history, list):
            history = []
    except (OSError, ValueError):
        history = []
    history.append({"at": datetime.now(UTC).isoformat(timespec="seconds"), **entry})
    tmp = live / ".history.json.tmp"
    tmp.write_text(json.dumps(history[-HISTORY_LIMIT:], indent=2), encoding="utf-8")
    os.replace(tmp, path)


def read_history(live: Path, last: int = 10) -> list[dict]:
    try:
        history = json.loads((live / "history.json").read_text(encoding="utf-8"))
        return history[-last:] if isinstance(history, list) else []
    except (OSError, ValueError):
        return []


def file_stamp(path: Path) -> float | None:
    """Modification time, or None when missing: services reload when it changes."""
    try:
        return path.stat().st_mtime
    except OSError:
        return None
