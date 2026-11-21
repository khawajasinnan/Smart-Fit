"""IDM-VTON building blocks shared by train_lora.py and eval_lora.py.

Standalone (runs on Kaggle). Needs the IDM-VTON repo (pinned commit) on
sys.path for its src/ modules. Everything loads from safetensors; the try-on
UNet, published only as a pickle .bin, is converted once with
torch.load(weights_only=True) (spec §23.8).

Placement (spec §23.9): the try-on UNet on GPU 0; the garment UNet, VAE,
text encoders and image encoder (all frozen) on GPU 1 when there are two
GPUs, else on GPU 0 too.
"""

from __future__ import annotations

import gc
from dataclasses import dataclass
from pathlib import Path

import torch

BASE = "yisol/IDM-VTON"
IDM_COMMIT = "0d5f3ec2d737487a9bb24e4100936ad254780383"
NEGATIVE = "monochrome, lowres, bad anatomy, worst quality, low quality"


def devices() -> tuple[str, str]:
    """(device of the trained UNet, device of the frozen helpers)."""
    if not torch.cuda.is_available():
        return "cpu", "cpu"
    return "cuda:0", ("cuda:1" if torch.cuda.device_count() > 1 else "cuda:0")


def safetensors_unet(repo_id: str, root: Path) -> Path:
    """Folder with the try-on UNet as fp16 safetensors (converted once, .bin deleted)."""
    from huggingface_hub import hf_hub_download
    from safetensors.torch import save_file

    hf_hub_download(repo_id, "unet/config.json", local_dir=root)
    weights = root / "unet" / "diffusion_pytorch_model.safetensors"
    if weights.exists():
        return weights.parent
    pickle_path = Path(hf_hub_download(repo_id, "unet/diffusion_pytorch_model.bin", local_dir=root))
    print("Converting the try-on UNet .bin to fp16 safetensors (weights_only load)...")
    try:
        state = torch.load(pickle_path, map_location="cpu", weights_only=True, mmap=True)
    except RuntimeError:  # legacy (non-zip) format cannot be memory-mapped
        state = torch.load(pickle_path, map_location="cpu", weights_only=True)
    half = {k: v.to(torch.float16).contiguous() for k, v in state.items()}
    del state
    partial = weights.with_suffix(".part")
    save_file(half, str(partial))
    partial.rename(weights)
    del half
    gc.collect()
    pickle_path.unlink()
    return weights.parent


@dataclass
class Components:
    unet: torch.nn.Module           # try-on UNet (gets the LoRA)
    unet_encoder: torch.nn.Module   # garment UNet (frozen)
    vae: torch.nn.Module
    text_encoder: torch.nn.Module
    text_encoder_2: torch.nn.Module
    tokenizer: object
    tokenizer_2: object
    image_encoder: torch.nn.Module
    scheduler: object               # DDPMScheduler (training noise)


def load_components(base: str, weights_root: Path) -> Components:
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
    c = Components(
        unet=TryonUNet.from_pretrained(str(safetensors_unet(base, weights_root)), torch_dtype=fp16),
        unet_encoder=GarmentUNet.from_pretrained(base, subfolder="unet_encoder", torch_dtype=fp16),
        vae=AutoencoderKL.from_pretrained(base, subfolder="vae", torch_dtype=fp16),  # sdxl-vae-fp16-fix
        text_encoder=CLIPTextModel.from_pretrained(base, subfolder="text_encoder", torch_dtype=fp16),
        text_encoder_2=CLIPTextModelWithProjection.from_pretrained(base, subfolder="text_encoder_2", torch_dtype=fp16),
        tokenizer=AutoTokenizer.from_pretrained(base, subfolder="tokenizer", use_fast=False),
        tokenizer_2=AutoTokenizer.from_pretrained(base, subfolder="tokenizer_2", use_fast=False),
        image_encoder=CLIPVisionModelWithProjection.from_pretrained(base, subfolder="image_encoder", torch_dtype=fp16),
        scheduler=DDPMScheduler.from_pretrained(base, subfolder="scheduler", rescale_betas_zero_snr=True),
    )
    for m in (c.unet, c.unet_encoder, c.vae, c.text_encoder, c.text_encoder_2, c.image_encoder):
        m.requires_grad_(False)
        m.eval()
    return c


def place_frozen(c: Components, helper: str) -> None:
    for m in (c.unet_encoder, c.vae, c.text_encoder, c.text_encoder_2, c.image_encoder):
        m.to(helper)


# ── conditioning, written as in train_xl.py ─────────────────────────────────


def encode_text(c: Components, captions: list[str], device: str) -> tuple[torch.Tensor, torch.Tensor]:
    """(hidden states [B, 77, 2048], pooled [B, 1280]) like train_xl.py: penultimate
    layers of both CLIP text encoders concatenated; pooled from encoder 2."""
    ids = c.tokenizer(captions, max_length=c.tokenizer.model_max_length, padding="max_length",
                      truncation=True, return_tensors="pt").input_ids.to(device)
    ids_2 = c.tokenizer_2(captions, max_length=c.tokenizer_2.model_max_length, padding="max_length",
                          truncation=True, return_tensors="pt").input_ids.to(device)
    out = c.text_encoder(ids, output_hidden_states=True)
    out_2 = c.text_encoder_2(ids_2, output_hidden_states=True)
    hidden = torch.cat([out.hidden_states[-2], out_2.hidden_states[-2]], dim=-1)
    return hidden, out_2[0]


def vae_latents(c: Components, pixels: torch.Tensor) -> torch.Tensor:
    vae = c.vae
    return vae.encode(pixels.to(vae.device, vae.dtype)).latent_dist.sample() * vae.config.scaling_factor


def time_ids(height: int, batch: int, device) -> torch.Tensor:
    # train_xl.py: original size and target size are both (height, height), crop (0, 0)
    return torch.tensor([[height, height, 0, 0, height, height]] * batch, device=device)


# ── generation (eval_lora.py) ───────────────────────────────────────────────


def on_device(module, device: str, home: str):
    """The garment UNet run on `device`, its reference features returned to `home`."""

    def move(x):
        return x.to(device) if torch.is_tensor(x) else x

    class OnDevice(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.inner = module.to(device)

        @property
        def device(self):  # diffusers reads .device/.dtype from pipeline components
            return torch.device(home)

        @property
        def dtype(self):
            return self.inner.dtype

        def forward(self, sample, timestep, encoder_hidden_states, **kwargs):
            out, features = self.inner(move(sample), move(timestep), move(encoder_hidden_states), **kwargs)
            return out, [f.to(home) for f in features]

    return OnDevice()


def build_pipeline(c: Components, base: str, unet):
    """IDM-VTON's TryonPipeline (gradio_demo/app.py) around `unet`; pipeline on GPU 0,
    garment UNet on GPU 1 when there are two."""
    from diffusers import DDPMScheduler
    from src.tryon_pipeline import StableDiffusionXLInpaintPipeline as TryonPipeline
    from transformers import CLIPImageProcessor

    main, helper = devices()
    pipe = TryonPipeline.from_pretrained(
        base, unet=unet, vae=c.vae, feature_extractor=CLIPImageProcessor(),
        text_encoder=c.text_encoder, text_encoder_2=c.text_encoder_2,
        tokenizer=c.tokenizer, tokenizer_2=c.tokenizer_2,
        scheduler=DDPMScheduler.from_pretrained(base, subfolder="scheduler"),
        image_encoder=c.image_encoder, torch_dtype=torch.float16,
    )
    pipe.unet_encoder = None  # attached after .to() so it is never moved back
    pipe.to(main)
    pipe.unet_encoder = on_device(c.unet_encoder, helper, main)
    free_memory()
    return pipe


def generate(pipe, person, garment, mask, pose, caption: str, seed: int, steps: int = 30, guidance: float = 2.0,
             size: tuple[int, int] = (768, 1024), negative: str = NEGATIVE):
    """One try-on image, as gradio_demo/app.py; PIL inputs, mask white = repaint.
    `negative`: IDM-VTON's own negative prompt unless the caller (serving) adds to it."""
    from torchvision import transforms

    main = devices()[0]
    to_tensor = transforms.Compose([transforms.ToTensor(), transforms.Normalize([0.5], [0.5])])
    person, garment = person.convert("RGB").resize(size), garment.convert("RGB").resize(size)
    mask, pose = mask.convert("L").resize(size), pose.convert("RGB").resize(size)
    fp16 = torch.float16
    with torch.no_grad(), torch.autocast("cuda"):
        prompt_embeds, negative_prompt_embeds, pooled, negative_pooled = pipe.encode_prompt(
            "model is wearing " + caption, num_images_per_prompt=1, do_classifier_free_guidance=True,
            negative_prompt=negative)
        prompt_embeds_c, _, _, _ = pipe.encode_prompt(
            ["a photo of " + caption], num_images_per_prompt=1, do_classifier_free_guidance=False,
            negative_prompt=[negative])
        return pipe(
            prompt_embeds=prompt_embeds.to(main, fp16), negative_prompt_embeds=negative_prompt_embeds.to(main, fp16),
            pooled_prompt_embeds=pooled.to(main, fp16), negative_pooled_prompt_embeds=negative_pooled.to(main, fp16),
            num_inference_steps=steps, generator=torch.Generator(main).manual_seed(seed), strength=1.0,
            pose_img=to_tensor(pose).unsqueeze(0).to(main, fp16), text_embeds_cloth=prompt_embeds_c.to(main, fp16),
            cloth=to_tensor(garment).unsqueeze(0).to(main, fp16), mask_image=mask, image=person,
            height=size[1], width=size[0], ip_adapter_image=garment, guidance_scale=guidance,
        )[0][0]


def free_memory() -> None:
    gc.collect()
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            with torch.cuda.device(i):
                torch.cuda.empty_cache()


def gpu_peaks_gb() -> list[float]:
    if not torch.cuda.is_available():
        return []
    return [round(torch.cuda.max_memory_reserved(i) / 1e9, 2) for i in range(torch.cuda.device_count())]


def reset_gpu_peaks() -> None:
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            torch.cuda.reset_peak_memory_stats(i)
