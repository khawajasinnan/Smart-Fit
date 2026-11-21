"""IDM-VTON baseline runner (spec §8.1). Runs on Kaggle (or any CUDA box).

    python run_idmvton.py --repo /kaggle/working/IDM-VTON --out /kaggle/working/results/idmvton

Mirrors the repo's gradio_demo/app.py single-image path (fp16 SDXL try-on
UNet + garment "reference" UNet, IP-Adapter image prompt, DensePose), with
VITON-HD's precomputed DensePose and agnostic masks instead of running
OpenPose/parsing. Repo defaults: 30 steps, guidance 2.0, 1024x768.
Prompts: "model is wearing a <garment>" / "a photo of <garment>"
(inference.py's VITON-HD wording; the garment text comes from
vitonhd_test_tagged.json, built into the manifest).

Memory: the weights alone are ~14 GB in fp16 (measured on a T4), so on one
16 GB T4 generation runs out of memory. --placement auto:
  * two GPUs (Kaggle "T4 x2"): pipeline on cuda:0, garment UNet on cuda:1
    (its features are copied back to cuda:0 each step);
  * one GPU: everything on cuda:0;
  * if a job still runs out of memory: switch to model CPU offload (encoders,
    UNet and VAE move to the GPU only while used) and retry that job.
The placement used is recorded per job and in results.json; peak VRAM is
the sum over GPUs, with the per-GPU split alongside.

Weights: everything is safetensors except the try-on UNet, published only as
a 12 GB pickle .bin. It is read once with torch.load(weights_only=True),
which accepts tensor data only (Hugging Face's pickle scan lists just
FloatStorage, _rebuild_tensor_v2 and OrderedDict), saved to --weights-dir
as fp16 safetensors, and the .bin is deleted.
"""

from __future__ import annotations

import argparse
import gc
import sys
import tempfile
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import (  # noqa: E402
    JobTimer,
    environment,
    find_pack,
    load_manifest,
    paired_metrics,
    summarise,
    write_results,
)

NEGATIVE = "monochrome, lowres, bad anatomy, worst quality, low quality"
MAIN = "cuda:0"


def safetensors_unet(repo_id: str, root: Path) -> Path:
    """Folder holding the try-on UNet as fp16 safetensors (converted once)."""
    import torch
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


def load_pipeline(base: str, weights_root: Path):
    import torch
    from diffusers import AutoencoderKL, DDPMScheduler
    from src.tryon_pipeline import StableDiffusionXLInpaintPipeline as TryonPipeline
    from src.unet_hacked_garmnet import UNet2DConditionModel as UNet2DConditionModel_ref
    from src.unet_hacked_tryon import UNet2DConditionModel
    from transformers import (
        AutoTokenizer,
        CLIPImageProcessor,
        CLIPTextModel,
        CLIPTextModelWithProjection,
        CLIPVisionModelWithProjection,
    )

    fp16 = torch.float16
    unet = UNet2DConditionModel.from_pretrained(str(safetensors_unet(base, weights_root)), torch_dtype=fp16)
    tokenizer_one = AutoTokenizer.from_pretrained(base, subfolder="tokenizer", revision=None, use_fast=False)
    tokenizer_two = AutoTokenizer.from_pretrained(base, subfolder="tokenizer_2", revision=None, use_fast=False)
    scheduler = DDPMScheduler.from_pretrained(base, subfolder="scheduler")
    text_encoder_one = CLIPTextModel.from_pretrained(base, subfolder="text_encoder", torch_dtype=fp16)
    text_encoder_two = CLIPTextModelWithProjection.from_pretrained(base, subfolder="text_encoder_2", torch_dtype=fp16)
    image_encoder = CLIPVisionModelWithProjection.from_pretrained(base, subfolder="image_encoder", torch_dtype=fp16)
    vae = AutoencoderKL.from_pretrained(base, subfolder="vae", torch_dtype=fp16)
    unet_encoder = UNet2DConditionModel_ref.from_pretrained(base, subfolder="unet_encoder", torch_dtype=fp16)
    for m in (unet_encoder, image_encoder, vae, unet, text_encoder_one, text_encoder_two):
        m.requires_grad_(False)
    pipe = TryonPipeline.from_pretrained(
        base,
        unet=unet,
        vae=vae,
        feature_extractor=CLIPImageProcessor(),
        text_encoder=text_encoder_one,
        text_encoder_2=text_encoder_two,
        tokenizer=tokenizer_one,
        tokenizer_2=tokenizer_two,
        scheduler=scheduler,
        image_encoder=image_encoder,
        torch_dtype=fp16,
    )
    return pipe, unet_encoder


def on_device(module, device: str, home: str):
    """The garment UNet, run on `device`; its reference features come back to `home`.

    The pipeline calls it once per step as unet_encoder(cloth, t, text_embeds_cloth,
    return_dict=False) and uses only the returned feature list.
    """
    import torch

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


def free_gpu_memory() -> None:
    import torch

    gc.collect()
    for i in range(torch.cuda.device_count()):
        with torch.cuda.device(i):
            torch.cuda.empty_cache()


def place(pipe, unet_encoder, placement: str) -> None:
    """Put the pipeline on the GPU(s): "two_gpu", "one_gpu" or "offload"."""
    import torch

    # Attached only afterwards, so pipe.to() and the offload hooks never move it.
    pipe.unet_encoder = None
    if placement == "offload":
        pipe.enable_model_cpu_offload(gpu_id=0)
    else:
        pipe.to(MAIN)
    second = "cuda:1" if torch.cuda.device_count() > 1 and placement != "one_gpu" else MAIN
    pipe.unet_encoder = on_device(unet_encoder, second, MAIN)
    free_gpu_memory()


def generate(pipe, job: dict, pack: Path, size: tuple[int, int], seed: int, steps: int, guidance: float):
    import torch
    from PIL import Image
    from torchvision import transforms

    to_tensor = transforms.Compose([transforms.ToTensor(), transforms.Normalize([0.5], [0.5])])
    human = Image.open(pack / job["person"]).convert("RGB").resize(size)
    garment = Image.open(pack / job["garment"]).convert("RGB").resize(size)
    mask = Image.open(pack / job["mask"]).convert("L").resize(size)
    pose = Image.open(pack / job["densepose"]).convert("RGB").resize(size)
    caption = job.get("garment_caption") or "shirts"
    fp16 = torch.float16
    with torch.no_grad(), torch.autocast("cuda"):
        prompt_embeds, negative_prompt_embeds, pooled, negative_pooled = pipe.encode_prompt(
            f"model is wearing a {caption}",
            num_images_per_prompt=1,
            do_classifier_free_guidance=True,
            negative_prompt=NEGATIVE,
        )
        prompt_embeds_c, _, _, _ = pipe.encode_prompt(
            [f"a photo of {caption}"],
            num_images_per_prompt=1,
            do_classifier_free_guidance=False,
            negative_prompt=[NEGATIVE],
        )
        return pipe(
            prompt_embeds=prompt_embeds.to(MAIN, fp16),
            negative_prompt_embeds=negative_prompt_embeds.to(MAIN, fp16),
            pooled_prompt_embeds=pooled.to(MAIN, fp16),
            negative_pooled_prompt_embeds=negative_pooled.to(MAIN, fp16),
            num_inference_steps=steps,
            generator=torch.Generator(MAIN).manual_seed(seed),
            strength=1.0,
            pose_img=to_tensor(pose).unsqueeze(0).to(MAIN, fp16),
            text_embeds_cloth=prompt_embeds_c.to(MAIN, fp16),
            cloth=to_tensor(garment).unsqueeze(0).to(MAIN, fp16),
            mask_image=mask,
            image=human,
            height=size[1],
            width=size[0],
            ip_adapter_image=garment,
            guidance_scale=guidance,
        )[0][0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack")
    ap.add_argument("--repo", required=True, help="IDM-VTON git checkout")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default="yisol/IDM-VTON")
    ap.add_argument("--weights-dir", default=str(Path(tempfile.gettempdir()) / "smartfit-weights"))
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--guidance", type=float, default=2.0)
    ap.add_argument("--placement", default="auto", choices=["auto", "two_gpu", "one_gpu", "offload"])
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    import torch

    sys.path.insert(0, str(Path(args.repo).resolve()))
    pack = find_pack(args.pack)
    manifest = load_manifest(pack)
    size = (manifest["width"], manifest["height"])
    jobs = manifest["jobs"][: args.limit] if args.limit else manifest["jobs"]
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    placement = args.placement
    if placement == "auto":
        placement = "two_gpu" if torch.cuda.device_count() > 1 else "one_gpu"

    with JobTimer(torch) as load:
        pipe, unet_encoder = load_pipeline(args.base, Path(args.weights_dir) / args.base.replace("/", "--"))
        place(pipe, unet_encoder, placement)
    print(f"IDM-VTON loaded in {load.seconds}s ({placement}), peak {load.peak_reserved_gb} GB {load.by_gpu}")

    results = []
    for n, job in enumerate(jobs, 1):
        row = {"id": job["id"], "group": job["group"]}
        for attempt in (1, 2):
            try:
                with JobTimer(torch) as t:
                    image = generate(pipe, job, pack, size, manifest["seed"], args.steps, args.guidance)
                image.save(out / "images" / f"{job['id']}.png")
                row |= {"status": "ok", "seconds": t.seconds, "peak_alloc_gb": t.peak_alloc_gb,
                        "peak_reserved_gb": t.peak_reserved_gb, "peak_reserved_gb_by_gpu": t.by_gpu,
                        "placement": placement, "image": f"images/{job['id']}.png"}
            except torch.cuda.OutOfMemoryError:
                free_gpu_memory()
                if attempt == 1 and args.placement == "auto" and placement != "offload":
                    print(f"Out of memory with {placement}; switching to model CPU offload and retrying.")
                    placement = "offload"
                    place(pipe, unet_encoder, placement)
                    continue
                row |= {"status": "oom", "placement": placement}
            except Exception as exc:
                row |= {"status": "error", "error": f"{type(exc).__name__}: {exc}", "placement": placement}
                traceback.print_exc()
            break
        results.append(row)
        print(f"[{n}/{len(jobs)}] {job['id']}: {row['status']} {row.get('seconds', '')}s")

    metrics = paired_metrics(pack, out, jobs, results, "cpu")
    write_results(out, {
        "model": "idm-vton",
        "license": "CC BY-NC-SA 4.0 (non-commercial)",
        "settings": {"base": args.base, "precision": "fp16", "steps": args.steps, "guidance": args.guidance,
                     "height": size[1], "width": size[0], "seed": manifest["seed"],
                     "placement": args.placement, "placement_at_end": placement,
                     "unet_weights": "fp16 safetensors (converted from .bin, weights_only)"},
        "environment": environment(torch, ["diffusers", "transformers", "accelerate", "huggingface-hub", "numpy",
                                           "einops"]),
        "load_seconds": load.seconds,
        "load_peak_reserved_gb": load.peak_reserved_gb,
        "load_peak_reserved_gb_by_gpu": load.by_gpu,
        "summary": summarise(results),
        "metrics": metrics,
        "jobs": results,
    })
    return 0 if all(r["status"] == "ok" for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
