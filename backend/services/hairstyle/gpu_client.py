"""Calls the HairFastGAN app on Modal (spec §23.27) from the CPU hairstyle service.

* render(): one call per request — the user's photo + the chosen style ids ->
  the aligned original and one realistic preview per style.
* warm(): started (fire and forget, at most every WARM_EVERY seconds) when the
  camera screen sends its first face-check, so the GPU is loaded by the time
  the user's photo arrives (a cold start loads ~8 GB of weights).

Never raises to the caller: any problem returns None and the service falls
back to the CPU overlay.
"""

from __future__ import annotations

import logging
import time

from shared.config import settings

logger = logging.getLogger("smartfit.hairstyle.gpu")

WARM_EVERY = 240.0  # the Modal container stays up 300 s after its last call

_cls = None
_error: str | None = None
_last_warm = 0.0


def _get():
    global _cls, _error
    if settings.hairstyle_backend != "modal":
        return None
    if _cls is None:
        try:
            import modal

            _cls = modal.Cls.from_name(settings.hairstyle_modal_app, settings.hairstyle_modal_class)
            _error = None
        except Exception as exc:  # noqa: BLE001 — reported in /health, never crashes the service
            _error = f"{type(exc).__name__}: {exc}"[:300]
            logger.warning("Modal hairstyle backend unavailable: %s", _error)
            return None
    return _cls


def enabled() -> bool:
    return _get() is not None


def error() -> str | None:
    return _error


def warm() -> None:
    global _last_warm
    cls = _get()
    if cls is None or time.monotonic() - _last_warm < WARM_EVERY:
        return
    _last_warm = time.monotonic()
    try:
        cls().warm.spawn()
    except Exception as exc:  # noqa: BLE001
        logger.info("hairstyle GPU warm-up not started (%s)", type(exc).__name__)


def render(face_jpeg: bytes, style_ids: list[str], timeout: float | None = None) -> dict | None:
    """{"original": jpeg, "previews": {id: jpeg}, "failed": {...}} or None (use the overlay)."""
    cls = _get()
    if cls is None:
        return None
    try:
        call = cls().render.spawn(face_jpeg, style_ids)
        out = call.get(timeout=timeout or settings.hairstyle_gpu_timeout_seconds)
    except Exception as exc:  # noqa: BLE001 — timeouts, GPU errors, network: fall back
        logger.warning("hairstyle GPU render failed: %s", type(exc).__name__)
        return None
    if not isinstance(out, dict) or not out.get("ok"):
        logger.warning("hairstyle GPU render gave nothing: %s", (out or {}).get("message"))
        return None
    if out.get("failed"):
        logger.info("hairstyle GPU: %d styles failed: %s", len(out["failed"]), list(out["failed"])[:3])
    return out


def reset() -> None:
    """Tests: forget the cached Modal handle."""
    global _cls, _error, _last_warm
    _cls, _error, _last_warm = None, None, 0.0
