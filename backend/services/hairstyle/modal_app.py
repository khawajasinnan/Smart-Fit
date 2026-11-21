"""SmartFit hairstyle previews on a Modal GPU: HairFastGAN (spec §23.27).

Realistic hair transfer (AIRI, NeurIPS 2024; code MIT, weights built on
StyleGAN2/FFHQ: non-commercial research use — fine for this FYP). Given the
user's face photo and the photo a catalog hairstyle was taken from (a
CelebA-HQ image), it redraws the user's hair in that style: the user's own
hair is replaced, whatever its length, and face and background are kept.

Runs on Modal only (`pip install modal`, `modal token new`); nothing here is
imported by the CPU services. One-time setup, from the repository root:

    modal run backend/services/hairstyle/modal_app.py::download_weights      # ~7.8 GB into a Volume
    python backend/scripts/upload_hairstyle_refs.py                          # the 80 reference photos
    modal run backend/services/hairstyle/modal_app.py::prepare_refs          # align them once (FFHQ crop)
    modal deploy backend/services/hairstyle/modal_app.py

Smoke test:  modal run backend/services/hairstyle/modal_app.py::smoke --face me.jpg --style <catalog id>

Per call (services/hairstyle/main.py): the user's photo as JPEG + the catalog
ids to render. The face is aligned once (FFHQ-style 1024 crop, dlib), then each
style is one HairFast swap with the pre-aligned reference as both shape and
colour. Returns the aligned original (for before/after) and one JPEG per style.
"""

from __future__ import annotations

import io
import os
import sys
import time
from pathlib import Path

import modal

APP_NAME = "smartfit-hairstyle"
REPO = "https://github.com/AIRI-Institute/HairFastGAN.git"
REPO_COMMIT = "49e98019c9243d1991c19d45764fc3340a498de2"  # pinned 18 Nov 2026
HF_REPO = "AIRI-Institute/HairFastGAN"
HF_REVISION = "47855f8ea72b02294649385211a1ae1fd7dcb58e"  # pinned 18 Nov 2026

WEIGHTS = "/weights"  # Modal Volume
HF_DIR = f"{WEIGHTS}/hairfast"
REFS_RAW = f"{WEIGHTS}/refs_raw"  # uploaded CelebA-HQ photos, <style id>.jpg
REFS = f"{WEIGHTS}/refs"  # aligned 1024 PNGs, <style id>.png
CODE = "/opt/hairfast"

GPU = os.environ.get("SMARTFIT_HAIR_GPU", "A10G")
MAX_CONTAINERS = int(os.environ.get("SMARTFIT_HAIR_MAX_CONTAINERS", "2"))
JPEG_QUALITY = 92
OUT_SIZE = 768  # previews are sent at this size (the model works at 1024)

image = (
    modal.Image.from_registry("nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04", add_python="3.11")
    .apt_install("git", "cmake", "build-essential", "ninja-build", "libgl1", "libglib2.0-0")
    # Modal images need Python >= 3.11, so torch 2.0.1 (the README asks for 1.13.1+)
    .pip_install("torch==2.0.1+cu118", "torchvision==0.15.2+cu118",
                 extra_index_url="https://download.pytorch.org/whl/cu118")
    .run_commands(
        f"git clone {REPO} {CODE} && git -C {CODE} checkout {REPO_COMMIT}",
        # Pillow 10 removed Image.ANTIALIAS, which the aligner uses; headless OpenCV; no telemetry packages;
        # torch is installed above with CUDA
        f"sed -i -e 's/^Pillow==.*/Pillow==9.5.0/' -e 's/^opencv-python==/opencv-python-headless==/' "
        f"-e '/^wandb/d' -e '/^sentry-sdk/d' -e '/^torch==/d' -e '/^torchvision==/d' -e '/^clip @/d' -e '/^dlib==/d' "
        f"{CODE}/requirements.txt",
        # OpenAI CLIP's old setup.py needs pkg_resources (gone from new setuptools): build it on its own
        "pip install 'setuptools<70' wheel cmake==3.29.6",
        # dlib's setup needs the cmake Python package, which pip's isolated build can't see
        "pip install --no-build-isolation dlib==19.24.1",
        "pip install --no-build-isolation "
        "'clip @ git+https://github.com/openai/CLIP.git@a1d071733d7111c9c014f024669f959182114e33'",
        f"pip install -r {CODE}/requirements.txt",
        "pip install huggingface_hub==0.25.2 ninja==1.11.1.1",
    )
    .env({
        "PYTHONUNBUFFERED": "1",
        # StyleGAN2's CUDA ops are compiled on first use: cache them on the Volume
        "TORCH_EXTENSIONS_DIR": f"{WEIGHTS}/torch_extensions",
        "TORCH_CUDA_ARCH_LIST": "7.5;8.0;8.6",
    })
)

volume = modal.Volume.from_name("smartfit-hairstyle-weights", create_if_missing=True)
app = modal.App(APP_NAME, image=image)


def _enter_repo() -> None:
    """Run from the repo with its pretrained_models/ pointing at the Volume."""
    os.chdir(CODE)
    if CODE not in sys.path:
        sys.path.insert(0, CODE)
    link = Path(CODE) / "pretrained_models"
    if not link.exists():
        link.symlink_to(f"{HF_DIR}/pretrained_models")


@app.function(volumes={WEIGHTS: volume}, timeout=3 * 3600, cpu=4, memory=8192)
def download_weights() -> dict:
    from huggingface_hub import snapshot_download

    t0 = time.time()
    snapshot_download(HF_REPO, revision=HF_REVISION, local_dir=HF_DIR, allow_patterns=["pretrained_models/**"])
    volume.commit()
    files = sorted(str(p.relative_to(HF_DIR)) for p in Path(HF_DIR).rglob("*") if p.is_file())
    return {"files": files, "seconds": round(time.time() - t0)}


@app.function(volumes={WEIGHTS: volume}, timeout=3600, cpu=4, memory=8192)
def prepare_refs() -> dict:
    """Align every uploaded reference photo once (FFHQ crop, 1024)."""
    _enter_repo()
    from utils.shape_predictor import align_face
    from PIL import Image

    Path(REFS).mkdir(parents=True, exist_ok=True)
    done, failed = [], {}
    for raw in sorted(Path(REFS_RAW).glob("*.jpg")):
        try:
            aligned = align_face([Image.open(raw).convert("RGB")], return_tensors=False)[0]
            aligned.save(Path(REFS) / f"{raw.stem}.png")
            done.append(raw.stem)
        except Exception as exc:  # noqa: BLE001 — report per photo
            failed[raw.stem] = f"{type(exc).__name__}: {exc}"[:200]
    volume.commit()
    return {"aligned": len(done), "failed": failed}


@app.function(volumes={WEIGHTS: volume}, timeout=600)
def probe() -> dict:
    """Diagnostics: the aligner's and swap's real signatures."""
    _enter_repo()
    import inspect

    from utils import shape_predictor

    return {"align_face": inspect.getsource(shape_predictor.align_face)[:2500],
            "refs": len(list(Path(REFS).glob("*.png"))) if Path(REFS).exists() else 0}


@app.cls(gpu=GPU, volumes={WEIGHTS: volume}, timeout=600, scaledown_window=300, max_containers=MAX_CONTAINERS)
class HairFast:
    @modal.enter()
    def load(self) -> None:
        _enter_repo()
        import torch
        from hair_swap import HairFast as Model
        from hair_swap import get_parser

        t0 = time.time()
        self.torch = torch
        self.model = Model(get_parser().parse_args([]))
        volume.commit()  # first start writes the PCA file and compiled ops: keep them
        print(f"HairFast loaded in {time.time() - t0:.0f} s")

    @modal.method()
    def warm(self) -> str:
        return "ok"

    def _to_jpeg(self, tensor) -> bytes:
        from PIL import Image

        t = tensor.detach().float().cpu()
        while t.dim() > 3:
            t = t[0]
        if t.max() > 1.5:  # 0..255
            t = t / 255.0
        elif t.min() < -0.01:  # -1..1
            t = (t + 1) / 2
        arr = (t.clamp(0, 1).permute(1, 2, 0).numpy() * 255).round().astype("uint8")
        img = Image.fromarray(arr).resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=JPEG_QUALITY)
        return buf.getvalue()

    @modal.method()
    def render(self, face_jpeg: bytes, style_ids: list[str], keep_colour: bool = True) -> dict:
        """{"ok", "original": jpeg, "previews": {id: jpeg}, "failed": {id: reason}} or an error.

        keep_colour: the cut from the reference, the colour from the user's own hair
        (what a haircut decision needs); False = the reference's colour too."""
        from PIL import Image
        from torchvision.transforms.functional import to_tensor
        from utils.shape_predictor import align_face

        t0 = time.time()
        try:
            face = align_face([Image.open(io.BytesIO(face_jpeg)).convert("RGB")], return_tensors=False)[0]
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error_code": "NO_FACE", "message": f"{type(exc).__name__}: {exc}"[:200]}
        face_t = to_tensor(face)
        previews, failed = {}, {}
        for sid in style_ids:
            ref_path = Path(REFS) / f"{sid}.png"
            if not ref_path.exists():
                failed[sid] = "reference not prepared"
                continue
            try:
                ref_t = to_tensor(Image.open(ref_path).convert("RGB"))
                with self.torch.no_grad():
                    out = self.model.swap(face_t, ref_t, face_t if keep_colour else ref_t, align=False)
                if isinstance(out, (tuple, list)):
                    out = out[0]
                previews[sid] = self._to_jpeg(out)
            except Exception as exc:  # noqa: BLE001 — one bad style must not lose the others
                failed[sid] = f"{type(exc).__name__}: {exc}"[:200]
        return {"ok": bool(previews), "original": self._to_jpeg(face_t), "previews": previews, "failed": failed,
                "seconds": round(time.time() - t0, 1),
                **({} if previews else {"error_code": "GPU_ERROR", "message": "No preview could be made."})}


@app.local_entrypoint()
def smoke(face: str, style: str = "", out: str = "hairfast_smoke", reference_colour: bool = False) -> None:
    ids = [s for s in style.split(",") if s]
    t0 = time.time()
    result = HairFast().render.remote(Path(face).read_bytes(), ids, keep_colour=not reference_colour)
    print({k: v for k, v in result.items() if k not in ("original", "previews")}, f"{time.time() - t0:.0f} s")
    Path(out).mkdir(exist_ok=True)
    if result.get("original"):
        (Path(out) / "original.jpg").write_bytes(result["original"])
    for sid, jpeg in (result.get("previews") or {}).items():
        (Path(out) / f"{sid}.jpg").write_bytes(jpeg)
