"""LoRA fine-tuning of IDM-VTON's try-on UNet (spec §8.4, §23.9).

Runs on Kaggle (GPU T4 x2), not in the API container:

    python train_lora.py --repo /tmp/IDM-VTON --manifest vitonhd_train.jsonl --out /kaggle/working/lora
    python train_lora.py ... --overfit 8        # memory + learning sanity check on 8 samples

The training step is IDM-VTON's train_xl.py with everything frozen except a
LoRA adapter on the try-on UNet's attention (see lora_config.py). fp16 with
loss scaling; LoRA weights in fp32.

Outputs in --out:
  metrics.jsonl                      one line per --log-every optimiser steps
  checkpoints/step-NNNNNN/adapter/   peft adapter (save_pretrained)
  checkpoints/step-NNNNNN/state.pt   optimiser, LR schedule, loss scaler, step, RNG
  adapter/                           final adapter (not merged into the base, spec §8.4)
  run.json                           settings, environment, data, result

Resume (Kaggle sessions end after 9-12 h): --resume auto continues from the
newest checkpoint in --out, or --resume PATH from a checkpoint folder (e.g. a
previous session's output attached as input). The step count, optimiser, LR
schedule and the data order (a seeded shuffle per pass, data.PassSampler)
continue exactly, so a pass over the data is never repeated or cut short.
"""

from __future__ import annotations

import argparse
import json
import platform
import random
import shutil
import sys
import time
from pathlib import Path

import torch
import torch.nn.functional as F

sys.path.insert(0, str(Path(__file__).resolve().parent))

from data import PassSampler, TryOnTrainDataset, read_manifest  # noqa: E402
from idm import (  # noqa: E402
    BASE,
    Components,
    devices,
    encode_text,
    free_memory,
    gpu_peaks_gb,
    load_components,
    place_frozen,
    reset_gpu_peaks,
    time_ids,
    vae_latents,
)
from lora_config import TARGET_MODULES, TrainConfig, peft_config  # noqa: E402

NAN_PATIENCE = 20  # consecutive non-finite losses before giving up


def base_unet(unet):
    """The UNet module inside a peft wrapper (LoRA layers are injected in place)."""
    return unet.get_base_model() if hasattr(unet, "get_base_model") else unet


def compute_loss(c: Components, unet, batch: dict, height: int, main: str, helper: str) -> torch.Tensor:
    """One train_xl.py training step's loss (before backward)."""
    dtype = c.vae.dtype
    with torch.no_grad():
        model_input = vae_latents(c, batch["image"]).to(main)
        masked_latents = vae_latents(c, batch["im_mask"]).to(main)
        pose_latents = vae_latents(c, batch["pose_img"]).to(main)
        cloth_latents = vae_latents(c, batch["cloth_pure"])  # stays on the helper GPU
        lat_h, lat_w = model_input.shape[-2:]
        mask = F.interpolate(batch["inpaint_mask"].to(main, dtype), size=(lat_h, lat_w))

        hidden, pooled = encode_text(c, list(batch["caption"]), helper)
        hidden_cloth, _ = encode_text(c, list(batch["caption_cloth"]), helper)
        image_hidden = c.image_encoder(batch["cloth"].to(helper, dtype), output_hidden_states=True).hidden_states[-2]

        bsz = model_input.shape[0]
        noise = torch.randn_like(model_input)
        timesteps = torch.randint(0, c.scheduler.config.num_train_timesteps, (bsz,), device=main).long()
        noisy = c.scheduler.add_noise(model_input, noise, timesteps)
        latent_in = torch.cat([noisy, mask, masked_latents, pose_latents], dim=1).to(dtype)

        _, garment_features = c.unet_encoder(cloth_latents, timesteps.to(helper), hidden_cloth, return_dict=False)
        garment_features = [f.to(main) for f in garment_features]

        pred_type = c.scheduler.config.prediction_type
        if pred_type == "epsilon":
            target = noise
        elif pred_type == "v_prediction":
            target = c.scheduler.get_velocity(model_input, noise, timesteps)
        else:
            raise ValueError(f"unsupported prediction type {pred_type}")

    use_amp = main.startswith("cuda")
    with torch.autocast("cuda", dtype=torch.float16, enabled=use_amp):
        ip_tokens = base_unet(unet).encoder_hid_proj(image_hidden.to(main))
        added = {"text_embeds": pooled.to(main), "time_ids": time_ids(height, bsz, main), "image_embeds": ip_tokens}
        noise_pred = unet(latent_in, timesteps, hidden.to(main), added_cond_kwargs=added,
                          garment_features=garment_features).sample
    return F.mse_loss(noise_pred.float(), target.float(), reduction="mean")


def add_lora(unet, cfg: TrainConfig):
    from peft import get_peft_model

    unet.enable_gradient_checkpointing()
    unet = get_peft_model(unet, peft_config(cfg))
    for p in unet.parameters():
        if p.requires_grad:
            p.data = p.data.float()  # LoRA weights in fp32 (loss scaling needs fp32 grads)
    return unet


def trainable(unet) -> list[torch.nn.Parameter]:
    return [p for p in unet.parameters() if p.requires_grad]


def save_checkpoint(out: Path, step: int, unet, optimizer, lr_sched, scaler, keep: int,
                    samples_seen: int | None = None) -> Path:
    folder = out / "checkpoints" / f"step-{step:06d}"
    partial = folder.with_name(folder.name + ".partial")
    shutil.rmtree(partial, ignore_errors=True)
    unet.save_pretrained(str(partial / "adapter"))
    torch.save({
        "step": step,
        "samples_seen": samples_seen,
        "optimizer": optimizer.state_dict(),
        "lr_scheduler": lr_sched.state_dict(),
        "scaler": scaler.state_dict(),
        "rng_python": random.getstate(),
        "rng_torch": torch.get_rng_state(),
        "rng_cuda": torch.cuda.get_rng_state_all() if torch.cuda.is_available() else [],
    }, partial / "state.pt")
    shutil.rmtree(folder, ignore_errors=True)
    partial.rename(folder)  # a checkpoint folder is complete or absent
    done = sorted(p for p in (out / "checkpoints").glob("step-*") if not p.name.endswith(".partial"))
    for old in done[:-keep]:
        shutil.rmtree(old, ignore_errors=True)
    return folder


def latest_checkpoint(out: Path) -> Path | None:
    done = sorted(p for p in (out / "checkpoints").glob("step-*")
                  if not p.name.endswith(".partial") and (p / "state.pt").exists())
    return done[-1] if done else None


def load_checkpoint(folder: Path, unet, optimizer, lr_sched, scaler) -> int:
    from peft import set_peft_model_state_dict
    from safetensors.torch import load_file

    weights = load_file(str(folder / "adapter" / "adapter_model.safetensors"))
    result = set_peft_model_state_dict(unet, weights)
    if getattr(result, "unexpected_keys", None):
        raise RuntimeError(f"adapter checkpoint does not match the model: {result.unexpected_keys[:5]}")
    for p in unet.parameters():
        if p.requires_grad:
            p.data = p.data.float()
    state = torch.load(folder / "state.pt", map_location="cpu", weights_only=True)
    optimizer.load_state_dict(state["optimizer"])
    lr_sched.load_state_dict(state["lr_scheduler"])
    scaler.load_state_dict(state["scaler"])
    random.setstate(_as_rng_tuple(state["rng_python"]))
    torch.set_rng_state(state["rng_torch"])
    if torch.cuda.is_available() and state["rng_cuda"]:
        torch.cuda.set_rng_state_all(state["rng_cuda"])
    return int(state["step"])


def samples_seen_in(folder: Path, step: int, per_step: int) -> int:
    """Samples drawn before this checkpoint (older checkpoints: step x samples per step)."""
    state = torch.load(folder / "state.pt", map_location="cpu", weights_only=True)
    seen = state.get("samples_seen")
    return int(seen) if seen is not None else step * per_step


def _as_rng_tuple(value):
    # random.getstate() is (version, tuple_of_ints, gauss); torch.save keeps the tuples
    version, internal, gauss = value
    return version, tuple(internal), gauss


def find_data_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    hits = sorted(Path("/kaggle/input").glob("**/train_pairs.txt"))
    if not hits:
        sys.exit("VITON-HD not found under /kaggle/input (no train_pairs.txt). Pass --data-root.")
    return hits[0].parent


def environment() -> dict:
    import importlib.metadata as md

    versions = {}
    for name in ("diffusers", "transformers", "accelerate", "peft", "huggingface-hub", "numpy"):
        try:
            versions[name] = md.version(name)
        except md.PackageNotFoundError:
            versions[name] = None
    gpus = [torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())] if torch.cuda.is_available() else []
    return {"python": platform.python_version(), "torch": torch.__version__, "cuda": torch.version.cuda,
            "gpus": gpus, "packages": versions}


def parse_args(argv=None):
    d = TrainConfig()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", required=True, help="IDM-VTON checkout at the pinned commit")
    ap.add_argument("--manifest", required=True, help="TryOnSample JSON Lines (paths relative to --data-root)")
    ap.add_argument("--data-root", help="dataset root (default: the folder with train_pairs.txt under /kaggle/input)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--weights-dir", default="/tmp/smartfit-weights")
    ap.add_argument("--overfit", type=int, default=0, help="train on the first N samples only, no augmentation")
    ap.add_argument("--resume", default="", help='"auto" (newest checkpoint in --out) or a checkpoint folder')
    ap.add_argument("--max-minutes", type=float, default=0, help="stop and checkpoint after this long (0 = no limit)")
    for name, value in vars(d).items():
        ap.add_argument("--" + name.replace("_", "-"), type=type(value), default=None,
                        help=f"default {value} (overfit mode changes some defaults)")
    return ap.parse_args(argv)


def build_config(args) -> TrainConfig:
    cfg = TrainConfig()
    if args.overfit:  # small, fast, deterministic data: should be memorised
        cfg.augment, cfg.max_steps, cfg.warmup_steps, cfg.grad_accum = "none", 300, 20, 1
        cfg.save_every, cfg.log_every, cfg.num_workers = 300, 5, 0
    for name in vars(cfg):
        value = getattr(args, name)
        if value is not None:
            setattr(cfg, name, value)
    return cfg


def main(argv=None) -> int:
    args = parse_args(argv)
    cfg = build_config(args)
    sys.path.insert(0, str(Path(args.repo).resolve()))
    from diffusers.optimization import get_cosine_schedule_with_warmup

    random.seed(cfg.seed)
    torch.manual_seed(cfg.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    root = find_data_root(args.data_root)
    records = read_manifest(Path(args.manifest))
    if args.overfit:
        records = records[: args.overfit]
    dataset = TryOnTrainDataset(records, root, cfg.height, cfg.width, cfg.augment)
    print(f"data: {len(dataset)} samples from {root} ({args.manifest})")

    main_dev, helper = devices()
    started = time.time()
    c = load_components(args.base, Path(args.weights_dir) / args.base.replace("/", "--"))
    place_frozen(c, helper)
    unet = add_lora(c.unet, cfg).to(main_dev)
    unet.train()
    params = trainable(unet)
    n_train = sum(p.numel() for p in params)
    print(f"LoRA: {n_train / 1e6:.2f}M trainable parameters; UNet on {main_dev}, frozen parts on {helper}; "
          f"loaded in {time.time() - started:.0f}s")

    optimizer = torch.optim.AdamW(params, lr=cfg.learning_rate, weight_decay=cfg.weight_decay)
    lr_sched = get_cosine_schedule_with_warmup(optimizer, cfg.warmup_steps, cfg.max_steps)
    scaler = torch.amp.GradScaler("cuda", enabled=main_dev.startswith("cuda"))

    step, samples_seen = 0, 0
    per_step = cfg.batch_size * cfg.grad_accum
    resume_from = latest_checkpoint(out) if args.resume == "auto" else (Path(args.resume) if args.resume else None)
    if resume_from:
        step = load_checkpoint(resume_from, unet, optimizer, lr_sched, scaler)
        samples_seen = samples_seen_in(resume_from, step, per_step)
        print(f"resumed from {resume_from} at step {step} ({samples_seen} samples seen)")
    # Seeded order that continues where the checkpoint stopped (no reshuffle on resume).
    loader = torch.utils.data.DataLoader(
        dataset, batch_size=cfg.batch_size, sampler=PassSampler(len(dataset), cfg.seed, start=samples_seen),
        num_workers=cfg.num_workers, pin_memory=torch.cuda.is_available())

    run = {"settings": cfg.as_dict() | {"base": args.base, "overfit": args.overfit, "manifest": args.manifest},
           "environment": environment(), "data": {"samples": len(dataset), "root": str(root)},
           "trainable_parameters": n_train, "resumed_from": str(resume_from) if resume_from else None}
    (out / "run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")

    metrics = (out / "metrics.jsonl").open("a", encoding="utf-8")
    batches = iter(loader)
    window, nonfinite, status = [], 0, "completed"
    reset_gpu_peaks()
    t0 = time.time()
    while step < cfg.max_steps:
        backward_passes = 0
        for _ in range(cfg.grad_accum):
            batch = next(batches)
            samples_seen += cfg.batch_size
            loss = compute_loss(c, unet, batch, cfg.height, main_dev, helper)
            if not torch.isfinite(loss):
                nonfinite += 1
                if nonfinite >= NAN_PATIENCE:
                    status = "stopped: non-finite loss"
                    break
                continue
            nonfinite = 0
            window.append(loss.item())
            scaler.scale(loss / cfg.grad_accum).backward()
            backward_passes += 1
        if status != "completed":
            break
        if backward_passes == 0:  # every micro-batch was skipped: no gradients to apply
            optimizer.zero_grad(set_to_none=True)
            continue
        scaler.unscale_(optimizer)
        torch.nn.utils.clip_grad_norm_(params, cfg.max_grad_norm)
        scaler.step(optimizer)
        scaler.update()
        optimizer.zero_grad(set_to_none=True)
        lr_sched.step()
        step += 1

        if step % cfg.log_every == 0 or step == cfg.max_steps:
            elapsed = time.time() - t0
            row = {"step": step, "samples_seen": samples_seen, "loss": round(sum(window) / max(len(window), 1), 6),
                   "lr": lr_sched.get_last_lr()[0], "sec_per_step": round(elapsed / cfg.log_every, 3),
                   "loss_scale": scaler.get_scale() if scaler.is_enabled() else None,
                   "peak_reserved_gb_by_gpu": gpu_peaks_gb()}
            metrics.write(json.dumps(row) + "\n")
            metrics.flush()
            print(json.dumps(row))
            window, t0 = [], time.time()
        if step % cfg.save_every == 0 or step == cfg.max_steps:
            print("checkpoint:", save_checkpoint(out, step, unet, optimizer, lr_sched, scaler, cfg.keep_checkpoints, samples_seen))
        if args.max_minutes and (time.time() - started) / 60 >= args.max_minutes:
            print("checkpoint:", save_checkpoint(out, step, unet, optimizer, lr_sched, scaler, cfg.keep_checkpoints, samples_seen))
            status = "paused: time budget reached (resume with --resume auto)"
            break
    metrics.close()

    if status == "completed":
        unet.save_pretrained(str(out / "adapter"))
    run |= {"status": status, "final_step": step, "peak_reserved_gb_by_gpu": gpu_peaks_gb(),
            "minutes": round((time.time() - started) / 60, 1), "target_modules": TARGET_MODULES}
    (out / "run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
    print(json.dumps({k: run[k] for k in ("status", "final_step", "peak_reserved_gb_by_gpu", "minutes")}))
    free_memory()
    return 0 if status == "completed" or status.startswith("paused") else 1



if __name__ == "__main__":
    raise SystemExit(main())
