"""SmartFit virtual try-on on a Modal GPU (SFR-026; spec §8, §23.8, §23.20).

The only diffusion model in the system (spec §0 principle 2). It runs
IDM-VTON + our DressCode LoRA adapter ("dresscode-v1") on one 24 GB GPU and
turns a user photo + a product photo into a 2D try-on image. Each view of the
app's 360° turntable is one call.

Runs on Modal only (needs `pip install modal` and `modal token new` on the
machine that deploys it). Nothing here is imported by the CPU services.

One-time setup, from the repository root:

    modal run backend/services/tryon/modal_app.py::download_weights   # ~22 GB into a Modal Volume (once)
    modal volume put smartfit-tryon-weights \\
        backend/data/lora-dresscode-results/lora_dresscode/adapter /lora/dresscode-v1
    modal deploy backend/services/tryon/modal_app.py

Smoke test with any full-body photo + garment photo:

    modal run backend/services/tryon/modal_app.py::smoke --person me.jpg --garment tee.jpg

Inputs per call (prepared by services/tryon/main.py): person and garment as
768x1024 JPEG bytes. Steps, as IDM-VTON's own demo (gradio_demo/app.py at
the pinned commit): human parsing + OpenPose -> garment mask
(utils_mask.get_mask_location), DensePose -> pose image, then the try-on
pipeline (30 steps, guidance 2.0, fixed seed). Licence: IDM-VTON and its
preprocessing weights are CC BY-NC-SA 4.0 / academic — fine for this FYP, not
for commercial use.
"""

from __future__ import annotations

import hashlib
import io
import os
import time
from contextlib import nullcontext
from pathlib import Path

import modal

APP_NAME = "smartfit-tryon"
IDM_REPO = "https://github.com/yisol/IDM-VTON.git"
IDM_COMMIT = "0d5f3ec2d737487a9bb24e4100936ad254780383"  # same code as the baseline and LoRA training
HF_REPO = "yisol/IDM-VTON"
HF_REVISION = "585a32e74aee241cbc0d0cc3ab21392ca58c916a"  # pinned weights (checked 13 Nov 2026)

WEIGHTS = "/weights"  # Modal Volume
IDM_DIR = f"{WEIGHTS}/idm"  # diffusers folders + preprocessing checkpoints
LORA_DIR = f"{WEIGHTS}/lora/dresscode-v1"
LORA_SHA256 = "c383b0a9728c0c363a35a51b112e9036309eb7671d73ef6a843c069008ca544a"  # spec §23.20

# Read when deploying (on the deploying machine), not inside the container.
GPU = os.environ.get("SMARTFIT_TRYON_GPU", "A10G")  # 24 GB; IDM-VTON peaks ~19 GB (spec §23.8)
MAX_CONTAINERS = int(os.environ.get("SMARTFIT_TRYON_MAX_CONTAINERS", "2"))

HF_PATTERNS = [
    "model_index.json", "scheduler/*", "unet/*", "unet_encoder/*", "vae/*", "text_encoder/*", "text_encoder_2/*",
    "tokenizer/*", "tokenizer_2/*", "image_encoder/*", "densepose/*", "humanparsing/*", "openpose/*",
]

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("git", "libgl1", "libglib2.0-0")
    .pip_install("torch==2.5.1", "torchvision==0.20.1", index_url="https://download.pytorch.org/whl/cu121")
    .pip_install(
        # the LoRA training/evaluation pins (lora/requirements-lora.txt) ...
        "diffusers==0.25.0", "transformers==4.36.2", "accelerate==0.25.0", "huggingface_hub==0.25.2",
        "safetensors==0.4.5", "peft==0.10.0", "numpy==1.26.4", "pillow==10.4.0", "einops==0.7.0", "tqdm==4.66.5",
        # ... plus what IDM-VTON's preprocessing needs (its environment.yaml; detectron2 is vendored in the repo)
        "opencv-python-headless==4.10.0.84", "onnxruntime==1.19.2", "scipy==1.11.4", "scikit-image==0.24.0",
        "fvcore==0.1.5.post20221221", "iopath==0.1.9", "omegaconf==2.3.0", "cloudpickle==3.0.0",
        "pycocotools==2.0.8", "av==12.3.0", "matplotlib==3.8.4", "termcolor==2.4.0", "tabulate==0.9.0", "yacs==0.1.8",
    )
    .run_commands(f"git clone {IDM_REPO} /opt/idm && git -C /opt/idm checkout {IDM_COMMIT}")
    .env({"HF_HOME": f"{WEIGHTS}/hf_home", "PYTHONUNBUFFERED": "1"})
    .add_local_file(Path(__file__).parent / "lora" / "idm.py", "/opt/smartfit/idm.py")
    .add_local_file(Path(__file__).parent / "hair_keep.py", "/opt/smartfit/hair_keep.py")
    .add_local_file(Path(__file__).parent / "top_mask.py", "/opt/smartfit/top_mask.py")
)

# What the model must never invent on the user's own skin, added to IDM-VTON's negative prompt
# when serving (evaluation keeps the original): 20 Nov 2026, once the old long sleeves were
# repainted (top_mask.py), a forearm it had to paint came out with a tattoo sleeve and a watch.
SERVE_NEGATIVE_EXTRA = "tattoo, tattoos, body art, wristwatch, watch, bracelet"

volume = modal.Volume.from_name("smartfit-tryon-weights", create_if_missing=True)
app = modal.App(APP_NAME, image=image)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ── one-time weight download ─────────────────────────────────────────────────


@app.function(volumes={WEIGHTS: volume}, timeout=4 * 3600, cpu=4, memory=32768)
def download_weights() -> dict:
    """Pinned IDM-VTON weights into the Volume. The try-on UNet is published
    only as a pickle .bin: it is read once with torch.load(weights_only=True)
    (tensor data only), saved as fp16 safetensors and the .bin deleted — the
    same conversion as the LoRA training (lora/idm.py, spec §23.8)."""
    import torch
    from huggingface_hub import snapshot_download
    from safetensors.torch import save_file

    root = Path(IDM_DIR)
    unet_st = root / "unet" / "diffusion_pytorch_model.safetensors"
    patterns = HF_PATTERNS if not unet_st.exists() else [p for p in HF_PATTERNS if p != "unet/*"] + ["unet/config.json"]
    snapshot_download(HF_REPO, revision=HF_REVISION, local_dir=str(root), allow_patterns=patterns)
    pickle_path = root / "unet" / "diffusion_pytorch_model.bin"
    if not unet_st.exists():
        print("Converting the try-on UNet to fp16 safetensors (weights_only load)...")
        try:
            state = torch.load(pickle_path, map_location="cpu", weights_only=True, mmap=True)
        except RuntimeError:
            state = torch.load(pickle_path, map_location="cpu", weights_only=True)
        half = {k: v.to(torch.float16).contiguous() for k, v in state.items()}
        del state
        partial = unet_st.with_suffix(".part")
        save_file(half, str(partial))
        partial.rename(unet_st)
    if pickle_path.exists():
        pickle_path.unlink()
    volume.commit()
    files = sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and "/.cache" not in str(p))
    lora = Path(LORA_DIR) / "adapter_model.safetensors"
    result = {"files": len(files), "lora_uploaded": lora.exists()}
    print(result)
    return result


# ── the try-on model ─────────────────────────────────────────────────────────


class NoPerson(Exception):
    pass


@app.cls(gpu=GPU, volumes={WEIGHTS: volume}, timeout=600, scaledown_window=120, max_containers=MAX_CONTAINERS)
class TryOn:
    @modal.enter()
    def load(self) -> None:
        import sys

        import torch

        started = time.time()
        os.environ["HF_HUB_OFFLINE"] = "1"  # everything comes from the Volume
        # Every torch.load (OpenPose's .pth) reads tensors only, never code.
        os.environ["TORCH_FORCE_WEIGHTS_ONLY_LOAD"] = "1"
        sys.path[:0] = ["/opt/idm", "/opt/idm/gradio_demo", "/opt/smartfit"]
        self._link_preprocess_weights()

        import idm  # backend/services/tryon/lora/idm.py, shipped with the image
        from diffusers import AutoencoderKL, DDPMScheduler
        from src.unet_hacked_garmnet import UNet2DConditionModel as GarmentUNet
        from src.unet_hacked_tryon import UNet2DConditionModel as TryonUNet
        from transformers import (
            AutoTokenizer,
            CLIPTextModel,
            CLIPTextModelWithProjection,
            CLIPVisionModelWithProjection,
        )

        fp16 = torch.float16
        d = IDM_DIR
        c = idm.Components(
            unet=TryonUNet.from_pretrained(f"{d}/unet", torch_dtype=fp16),
            unet_encoder=GarmentUNet.from_pretrained(f"{d}/unet_encoder", torch_dtype=fp16),
            vae=AutoencoderKL.from_pretrained(f"{d}/vae", torch_dtype=fp16),
            text_encoder=CLIPTextModel.from_pretrained(f"{d}/text_encoder", torch_dtype=fp16),
            text_encoder_2=CLIPTextModelWithProjection.from_pretrained(f"{d}/text_encoder_2", torch_dtype=fp16),
            tokenizer=AutoTokenizer.from_pretrained(f"{d}/tokenizer", use_fast=False),
            tokenizer_2=AutoTokenizer.from_pretrained(f"{d}/tokenizer_2", use_fast=False),
            image_encoder=CLIPVisionModelWithProjection.from_pretrained(f"{d}/image_encoder", torch_dtype=fp16),
            scheduler=DDPMScheduler.from_pretrained(f"{d}/scheduler"),
        )
        for m in (c.unet, c.unet_encoder, c.vae, c.text_encoder, c.text_encoder_2, c.image_encoder):
            m.requires_grad_(False)
            m.eval()

        # DressCode LoRA (spec §23.20): applied in place; switched off per call
        # with disable_adapter() for categories that don't use it.
        self.lora = None
        adapter = Path(LORA_DIR) / "adapter_model.safetensors"
        if adapter.exists():
            if _sha256(adapter) != LORA_SHA256:
                raise RuntimeError("LoRA adapter checksum mismatch: re-upload dresscode-v1")
            from peft import PeftModel

            self.lora = PeftModel.from_pretrained(c.unet, LORA_DIR)
            self.lora.eval()
            unet = self.lora.get_base_model()
        else:
            print("LoRA adapter not found in the Volume: running the base model only.")
            unet = c.unet
        self.pipe = idm.build_pipeline(c, d, unet)
        self.idm = idm
        import hair_keep  # backend/services/tryon/hair_keep.py, shipped with the image
        import top_mask  # backend/services/tryon/top_mask.py, shipped with the image

        self.hair_keep = hair_keep
        self.top_mask = top_mask

        # Preprocessing for arbitrary user photos, as gradio_demo/app.py.
        import apply_net
        from detectron2.data.detection_utils import _apply_exif_orientation, convert_PIL_to_numpy
        from detectron2.engine.defaults import DefaultPredictor
        from preprocess.humanparsing.run_parsing import Parsing
        from preprocess.openpose.run_openpose import OpenPose
        from utils_mask import get_mask_location

        self.parsing = Parsing(0)
        self.openpose = OpenPose(0)
        self.openpose.preprocessor.body_estimation.model.to("cuda:0")
        args = apply_net.create_argument_parser().parse_args((
            "show", "/opt/idm/configs/densepose_rcnn_R_50_FPN_s1x.yaml", f"{d}/densepose/model_final_162be9.pkl",
            "dp_segm", "-v", "--opts", "MODEL.DEVICE", "cuda",
        ))
        cfg = apply_net.ShowAction.setup_config(args.cfg, args.model, args, [])
        self.dp_predictor = DefaultPredictor(cfg)  # built once, not per photo
        self.dp_context = apply_net.ShowAction.create_context(args, cfg)
        self.dp_show = apply_net.ShowAction
        self.to_bgr = lambda img: convert_PIL_to_numpy(_apply_exif_orientation(img), format="BGR")
        self.get_mask_location = get_mask_location
        torch.backends.cudnn.benchmark = True
        print(f"TryOn ready in {time.time() - started:.0f} s (LoRA: {'on' if self.lora else 'off'})")

    @staticmethod
    def _link_preprocess_weights() -> None:
        """The repo's ckpt/ files are placeholders; point them at the Volume."""
        for rel in ("humanparsing/parsing_atr.onnx", "humanparsing/parsing_lip.onnx",
                    "openpose/ckpts/body_pose_model.pth", "densepose/model_final_162be9.pkl"):
            target = Path(IDM_DIR) / rel
            link = Path("/opt/idm/ckpt") / rel
            if not target.exists():
                raise RuntimeError(f"missing {target}: run download_weights first")
            link.parent.mkdir(parents=True, exist_ok=True)
            if link.exists() or link.is_symlink():
                link.unlink()
            link.symlink_to(target)

    def _masks(self, person, category: str):
        import numpy as np
        import torch
        from PIL import Image

        small = person.resize((384, 512))
        try:
            keypoints = self.openpose(small)
        except (IndexError, AssertionError, ValueError) as exc:  # no body found
            raise NoPerson from exc
        pts = np.array(keypoints["pose_keypoints_2d"]).reshape(-1, 2)
        if category != "lower_body" and (not pts[2].any() or not pts[5].any()):  # both shoulders needed
            raise NoPerson
        parse, _ = self.parsing(small)
        model_type = "hd" if category == "upper_body" else "dc"  # VITON-HD vs DressCode arm width
        mask, _ = self.get_mask_location(model_type, category, parse, keypoints)
        mask = self.hair_keep.mask_without_hair(mask, parse)  # long hair is never repainted
        if category == "upper_body":  # a sleeve over the trousers, parsed as trousers, is repainted too
            mask = self.top_mask.cover_old_sleeves(mask, parse, small)
        img_bgr = self.to_bgr(small)
        with torch.no_grad():
            instances = self.dp_predictor(img_bgr)["instances"]
        if len(instances) == 0:
            raise NoPerson
        vis = self.dp_show.execute_on_outputs(self.dp_context, {"image": img_bgr}, instances)
        pose = Image.fromarray(vis[:, :, ::-1]).resize((768, 1024))
        return mask.resize((768, 1024)), pose, parse

    @modal.method()
    def generate(self, person_jpeg: bytes, garment_jpeg: bytes, category: str, caption: str,
                 use_lora: bool = True, seed: int = 42, steps: int = 30) -> dict:
        from PIL import Image

        if category not in ("upper_body", "lower_body", "dresses"):
            return {"ok": False, "error_code": "BAD_REQUEST", "message": f"unknown category {category!r}"}
        started = time.time()
        person = Image.open(io.BytesIO(person_jpeg)).convert("RGB").resize((768, 1024))
        garment = Image.open(io.BytesIO(garment_jpeg)).convert("RGB").resize((768, 1024))
        try:
            mask, pose, parse = self._masks(person, category)
        except NoPerson:
            return {"ok": False, "error_code": "NO_PERSON", "message": "No full body found in the photo."}
        prep = time.time() - started
        lora_on = bool(self.lora) and use_lora
        ctx = self.lora.disable_adapter() if (self.lora and not use_lora) else nullcontext()
        with ctx:
            out = self.idm.generate(self.pipe, person, garment, mask, pose, caption, seed, steps,
                                    negative=f"{self.idm.NEGATIVE}, {SERVE_NEGATIVE_EXTRA}")
        out = self.hair_keep.paste_hair_back(person, out, parse)  # the user's own hair, pixel for pixel
        buf = io.BytesIO()
        out.convert("RGB").save(buf, "JPEG", quality=95, subsampling=0)  # full colour detail for fabric
        return {"ok": True, "image": buf.getvalue(), "lora": lora_on,
                "seconds": {"preprocess": round(prep, 1), "total": round(time.time() - started, 1)}}


@app.local_entrypoint()
def smoke(person: str, garment: str, category: str = "upper_body", caption: str = "t-shirt",
          out: str = "tryon_smoke.jpg", lora: bool = True) -> None:
    """Quick check from your PC: one try-on with local image files."""
    from PIL import Image

    def framed(path: str) -> bytes:
        buf = io.BytesIO()
        Image.open(path).convert("RGB").resize((768, 1024)).save(buf, "JPEG", quality=95)
        return buf.getvalue()

    started = time.time()
    res = TryOn().generate.remote(framed(person), framed(garment), category, caption, lora)
    if not res["ok"]:
        print("FAILED:", res)
        return
    Path(out).write_bytes(res["image"])
    print(f"saved {out} in {time.time() - started:.0f} s (LoRA {res['lora']}, {res['seconds']})")
