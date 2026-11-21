"""Where try-on images are generated.

* ModalRunner: the real thing. Each view is one call to the deployed Modal
  class (services/tryon/modal_app.py: IDM-VTON + the DressCode LoRA on a
  24 GB GPU). Calls are spawned, so this service never holds a request open
  for the ~30-60 s a view takes (rules.md §2.3, spec §8.6).
* MockRunner: TEST MODE ONLY (TRYON_BACKEND=mock). Returns the user's own
  photo with the garment pasted in a corner and a "TEST MODE" banner, after a
  short delay, so the app's screens can be built and tested without a GPU.
  Its output is labelled everywhere (rules.md §4: no unlabelled mock data).

Both are synchronous; the service calls them in a thread pool.
"""

from __future__ import annotations

import io
import logging
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Literal, Protocol

from PIL import Image, ImageDraw, ImageFont

from shared.config import settings

logger = logging.getLogger("smartfit.tryon.runner")

Outcome = Literal["pending", "done", "failed"]


@dataclass
class ViewOutcome:
    state: Outcome
    image_jpeg: bytes | None = None
    error_code: str | None = None
    message: str | None = None


@dataclass
class ViewTask:
    person_jpeg: bytes  # 768x1024, already framed
    garment_jpeg: bytes  # 768x1024, already framed
    category: str  # IDM-VTON's: upper_body | lower_body | dresses
    caption: str
    use_lora: bool
    seed: int
    steps: int
    angle: str


class Runner(Protocol):
    mode: Literal["modal", "mock"]

    def submit(self, task: ViewTask) -> str: ...

    def poll(self, call_id: str) -> ViewOutcome: ...


# ── Modal (real try-on) ──────────────────────────────────────────────────────


class ModalRunner:
    mode: Literal["modal", "mock"] = "modal"

    def __init__(self, app_name: str, class_name: str) -> None:
        import modal  # only needed when the real GPU backend is on

        self._modal = modal
        self._cls = modal.Cls.from_name(app_name, class_name)

    def warm(self) -> None:
        """Look the deployed app up and connect now, not on the first try-on."""
        self._cls.hydrate()

    def submit(self, task: ViewTask) -> str:
        call = self._cls().generate.spawn(
            person_jpeg=task.person_jpeg,
            garment_jpeg=task.garment_jpeg,
            category=task.category,
            caption=task.caption,
            use_lora=task.use_lora,
            seed=task.seed,
            steps=task.steps,
        )
        return call.object_id

    def poll(self, call_id: str) -> ViewOutcome:
        modal = self._modal
        try:
            out = modal.FunctionCall.from_id(call_id).get(timeout=0)
        except TimeoutError:
            return ViewOutcome("pending")
        except Exception as exc:  # noqa: BLE001 — any Modal-side failure becomes a clear view error
            if type(exc).__name__ == "TimeoutError":  # modal.exception.TimeoutError (older SDKs)
                return ViewOutcome("pending")
            logger.warning("try-on call %s failed: %s", call_id, type(exc).__name__)
            return ViewOutcome("failed", error_code="GPU_ERROR",
                               message="The try-on generator had a problem with this photo. Please try again.")
        if not out.get("ok"):
            return ViewOutcome("failed", error_code=out.get("error_code") or "GPU_ERROR", message=out.get("message"))
        return ViewOutcome("done", image_jpeg=out["image"])


# ── Mock (TEST MODE) ─────────────────────────────────────────────────────────


class MockRunner:
    mode: Literal["modal", "mock"] = "mock"

    def __init__(self, delay_seconds: float) -> None:
        self._delay = delay_seconds
        self._calls: dict[str, tuple[float, bytes]] = {}
        self._lock = threading.Lock()

    def submit(self, task: ViewTask) -> str:
        call_id = f"mock-{uuid.uuid4().hex}"
        image = _mock_image(task)
        with self._lock:
            self._calls[call_id] = (time.monotonic() + self._delay, image)
        return call_id

    def poll(self, call_id: str) -> ViewOutcome:
        with self._lock:
            entry = self._calls.get(call_id)
        if entry is None:
            return ViewOutcome("failed", error_code="GPU_ERROR", message="This test-mode result has expired.")
        ready_at, image = entry
        if time.monotonic() < ready_at:
            return ViewOutcome("pending")
        return ViewOutcome("done", image_jpeg=image)


def _font(size: int):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def _mock_image(task: ViewTask) -> bytes:
    """The user's photo + garment thumbnail + an unmistakable TEST MODE label."""
    person = Image.open(io.BytesIO(task.person_jpeg)).convert("RGB")
    garment = Image.open(io.BytesIO(task.garment_jpeg)).convert("RGB")
    w, h = person.size
    thumb = garment.resize((w // 3, h // 3))
    person.paste(thumb, (w - thumb.width - 16, h - thumb.height - 16))
    draw = ImageDraw.Draw(person, "RGBA")
    draw.rectangle((0, 0, w, 120), fill=(20, 18, 31, 200))
    draw.text((24, 18), "TEST MODE - not a real try-on", fill=(255, 79, 163, 255), font=_font(40))
    draw.text((24, 70), f"{task.angle} view  |  {task.category}  |  {task.caption[:40]}", fill="white", font=_font(28))
    buf = io.BytesIO()
    person.save(buf, "JPEG", quality=85)
    return buf.getvalue()


# ── selection ────────────────────────────────────────────────────────────────

_runner: Runner | None = None
_runner_error: str | None = None


def get_runner() -> Runner | None:
    """The configured runner, or None while try-on isn't connected
    (TRYON_BACKEND empty, or Modal not reachable/logged in)."""
    global _runner, _runner_error
    if _runner is not None:
        return _runner
    backend = settings.tryon_backend
    if backend == "mock":
        _runner = MockRunner(settings.tryon_mock_delay_seconds)
    elif backend == "modal":
        try:
            _runner = ModalRunner(settings.tryon_modal_app, settings.tryon_modal_class)
            _runner_error = None
        except Exception as exc:  # noqa: BLE001 — reported in /health, never crashes the service
            _runner_error = f"{type(exc).__name__}: {exc}"[:300]
            logger.warning("Modal try-on backend unavailable: %s", _runner_error)
            return None
    return _runner


def runner_error() -> str | None:
    return _runner_error


def reset_runner() -> None:
    """Tests: forget the cached runner after changing settings."""
    global _runner, _runner_error
    _runner, _runner_error = None, None
