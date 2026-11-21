"""LoRA trainer on tiny, randomly initialised copies of IDM-VTON's own UNet classes.

Exercises the real code paths on CPU: manifest -> dataset tensors (real
VITON-HD samples), LoRA injection, the train_xl.py loss, optimiser steps,
checkpoint/resume and the CLI. Needs the training environment (diffusers
0.25, transformers 4.36, peft) and IDM-VTON's source:

    IDM_VTON_REPO=/path/to/IDM-VTON python -m pytest tests/test_tryon_lora_train.py

Skipped when those are missing (e.g. in the API's own venv).
"""

import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

pytest.importorskip("diffusers")
pytest.importorskip("peft")
IDM_REPO = os.environ.get("IDM_VTON_REPO")
if not IDM_REPO or not (Path(IDM_REPO) / "src" / "unet_hacked_tryon.py").exists():
    pytest.skip("set IDM_VTON_REPO to an IDM-VTON checkout", allow_module_level=True)

REPO_ROOT = Path(__file__).resolve().parents[2]
VITON = REPO_ROOT / "datasets" / "viton-hd"
MANIFEST = REPO_ROOT / "datasets" / "manifests" / "vitonhd_train.jsonl"
if not MANIFEST.exists() or not VITON.exists():
    pytest.skip("needs datasets/viton-hd and datasets/manifests (build_tryon_manifest.py)", allow_module_level=True)

LORA_DIR = Path(__file__).resolve().parents[1] / "services" / "tryon" / "lora"
sys.path.insert(0, IDM_REPO)
sys.path.insert(0, str(LORA_DIR))

import torch  # noqa: E402
import train_lora  # noqa: E402
from data import TryOnTrainDataset, read_manifest  # noqa: E402
from idm import Components  # noqa: E402
from lora_config import TrainConfig  # noqa: E402

H, W = 64, 48  # VAE /8 -> 8x6 latents


class FakeTokenizer:
    model_max_length = 77

    def __call__(self, texts, max_length, padding, truncation, return_tensors):
        ids = torch.zeros(len(texts), max_length, dtype=torch.long)
        for i, text in enumerate(texts):
            words = [3 + sum(map(ord, w)) % 90 for w in text.split()][: max_length - 1]
            ids[i, : len(words)] = torch.tensor(words)
            ids[i, len(words)] = 2  # end token
        return SimpleNamespace(input_ids=ids)


def tiny_components() -> Components:
    from diffusers import AutoencoderKL, DDPMScheduler
    from src.unet_hacked_garmnet import UNet2DConditionModel as GarmentUNet
    from src.unet_hacked_tryon import UNet2DConditionModel as TryonUNet
    from transformers import (
        CLIPTextConfig,
        CLIPTextModel,
        CLIPTextModelWithProjection,
        CLIPVisionConfig,
        CLIPVisionModelWithProjection,
    )

    torch.manual_seed(0)
    blocks = dict(block_out_channels=(32, 64), down_block_types=("DownBlock2D", "CrossAttnDownBlock2D"),
                  up_block_types=("CrossAttnUpBlock2D", "UpBlock2D"), layers_per_block=1,
                  attention_head_dim=(2, 4), cross_attention_dim=32, sample_size=8)
    text = dict(vocab_size=100, hidden_size=16, intermediate_size=32, num_hidden_layers=2,
                num_attention_heads=2, max_position_embeddings=77, projection_dim=16)
    c = Components(
        unet=TryonUNet(in_channels=13, out_channels=4, addition_embed_type="text_time", addition_time_embed_dim=8,
                       projection_class_embeddings_input_dim=16 + 6 * 8, encoder_hid_dim=32,
                       encoder_hid_dim_type="ip_image_proj", **blocks),
        unet_encoder=GarmentUNet(in_channels=4, out_channels=4, **blocks),
        vae=AutoencoderKL(down_block_types=("DownEncoderBlock2D",) * 4, up_block_types=("UpDecoderBlock2D",) * 4,
                          block_out_channels=(8, 8, 8, 8), norm_num_groups=4, layers_per_block=1, latent_channels=4),
        text_encoder=CLIPTextModel(CLIPTextConfig(**text)),
        text_encoder_2=CLIPTextModelWithProjection(CLIPTextConfig(**text)),
        tokenizer=FakeTokenizer(),
        tokenizer_2=FakeTokenizer(),
        image_encoder=CLIPVisionModelWithProjection(CLIPVisionConfig(
            hidden_size=32, intermediate_size=64, num_hidden_layers=2, num_attention_heads=2,
            image_size=224, patch_size=32, projection_dim=16)),
        scheduler=DDPMScheduler(rescale_betas_zero_snr=True),
    )
    for m in (c.unet, c.unet_encoder, c.vae, c.text_encoder, c.text_encoder_2, c.image_encoder):
        m.requires_grad_(False)
        m.eval()
    return c


def batch_of(n: int, augment: str = "none") -> dict:
    ds = TryOnTrainDataset(read_manifest(MANIFEST)[:n], VITON, H, W, augment)
    return next(iter(torch.utils.data.DataLoader(ds, batch_size=n, shuffle=False)))


def test_dataset_tensors_match_idm_conventions():
    torch.manual_seed(1)
    for augment in ("none", "repo"):
        b = batch_of(2, augment)
        assert b["image"].shape == (2, 3, H, W) and b["cloth_pure"].shape == (2, 3, H, W)
        assert b["pose_img"].shape == (2, 3, H, W) and b["cloth"].shape == (2, 3, 224, 224)
        assert b["image"].min() >= -1 and b["image"].max() <= 1
        assert set(b["inpaint_mask"].unique().tolist()) <= {0.0, 1.0}
        # the garment region is blanked in the masked person
        assert torch.all(b["im_mask"][b["inpaint_mask"].expand_as(b["im_mask"]) == 1] == 0)
        assert b["caption"][0].startswith("model is wearing ") and b["caption_cloth"][0].startswith("a photo of ")


def test_lora_targets_only_the_unets_transformer_attention():
    unet = train_lora.add_lora(tiny_components().unet, TrainConfig(rank=4, alpha=8))
    lora_names = [n for n, _ in unet.named_parameters() if "lora_" in n]
    assert lora_names
    assert all((".attn1." in n or ".attn2." in n) and "encoder_hid_proj" not in n for n in lora_names)
    assert {n.split(".attn")[1][:1] for n in lora_names} == {"1", "2"}  # self- and cross-attention
    trainable = [(n, p) for n, p in unet.named_parameters() if p.requires_grad]
    assert all("lora_" in n and p.dtype == torch.float32 for n, p in trainable)


def test_loss_backprops_into_every_lora_weight_and_learns(tmp_path):
    c = tiny_components()
    unet = train_lora.add_lora(c.unet, TrainConfig(rank=4, alpha=8))
    unet.train()
    params = train_lora.trainable(unet)
    opt = torch.optim.AdamW(params, lr=1e-3)
    batch = batch_of(1)
    losses = []
    for i in range(40):
        torch.manual_seed(123)  # same noise and timestep each step: the loss must go down
        loss = train_lora.compute_loss(c, unet, batch, H, "cpu", "cpu")
        loss.backward()
        if i == 0:
            missing = [n for n, p in unet.named_parameters() if p.requires_grad and p.grad is None]
            assert not missing, f"no gradient reached {missing[:3]} (gradient checkpointing?)"
        opt.step()
        opt.zero_grad()
        losses.append(loss.item())
    assert losses[-1] < 0.9 * losses[0], losses[::10]  # LoRA B starts at zero, so the first steps are small


def test_checkpoint_roundtrip_and_pruning(tmp_path):
    from diffusers.optimization import get_cosine_schedule_with_warmup

    c = tiny_components()
    unet = train_lora.add_lora(c.unet, TrainConfig(rank=4, alpha=8))
    params = train_lora.trainable(unet)
    opt = torch.optim.AdamW(params, lr=1e-3)
    sched = get_cosine_schedule_with_warmup(opt, 2, 10)
    scaler = torch.amp.GradScaler("cuda", enabled=False)
    train_lora.compute_loss(c, unet, batch_of(1), H, "cpu", "cpu").backward()
    opt.step()
    sched.step()
    saved = {n: p.detach().clone() for n, p in unet.named_parameters() if p.requires_grad}
    for step in (1, 2, 3):
        train_lora.save_checkpoint(tmp_path, step, unet, opt, sched, scaler, keep=2)
    assert sorted(p.name for p in (tmp_path / "checkpoints").iterdir()) == ["step-000002", "step-000003"]

    with torch.no_grad():
        for p in params:
            p.add_(1.0)
    step = train_lora.load_checkpoint(train_lora.latest_checkpoint(tmp_path), unet, opt, sched, scaler)
    assert step == 3
    for n, p in unet.named_parameters():
        if p.requires_grad:
            assert p.dtype == torch.float32 and torch.equal(p, saved[n]), n


def test_cli_overfit_run_then_resume(tmp_path, monkeypatch):
    monkeypatch.setattr(train_lora, "load_components", lambda base, root: tiny_components())
    common = ["--repo", IDM_REPO, "--manifest", str(MANIFEST), "--data-root", str(VITON), "--out", str(tmp_path),
              "--overfit", "2", "--height", str(H), "--width", str(W), "--rank", "4", "--alpha", "8",
              "--log-every", "1", "--save-every", "2", "--warmup-steps", "1"]
    assert train_lora.main(common + ["--max-steps", "4"]) == 0
    run = json.loads((tmp_path / "run.json").read_text())
    assert run["status"] == "completed" and run["final_step"] == 4
    assert (tmp_path / "adapter" / "adapter_model.safetensors").exists()
    rows = [json.loads(line) for line in (tmp_path / "metrics.jsonl").read_text().splitlines()]
    assert [r["step"] for r in rows] == [1, 2, 3, 4] and all(r["loss"] > 0 for r in rows)

    assert train_lora.main(common + ["--max-steps", "6", "--resume", "auto"]) == 0
    run = json.loads((tmp_path / "run.json").read_text())
    assert run["resumed_from"].endswith("step-000004") and run["final_step"] == 6
    rows = [json.loads(line) for line in (tmp_path / "metrics.jsonl").read_text().splitlines()]
    assert [r["step"] for r in rows][-2:] == [5, 6]
    assert [r["samples_seen"] for r in rows] == [1, 2, 3, 4, 5, 6]  # the order continued, no restart


def test_cli_time_budget_pauses_with_a_checkpoint_then_resumes(tmp_path, monkeypatch):
    """The Kaggle flow: session 1 hits --max-minutes, checkpoints and exits 0;
    session 2 resumes from that checkpoint and finishes the planned steps."""
    monkeypatch.setattr(train_lora, "load_components", lambda base, root: tiny_components())
    common = ["--repo", IDM_REPO, "--manifest", str(MANIFEST), "--data-root", str(VITON), "--out", str(tmp_path),
              "--overfit", "3", "--height", str(H), "--width", str(W), "--rank", "4", "--alpha", "8",
              "--log-every", "1", "--save-every", "100", "--warmup-steps", "1", "--grad-accum", "2",
              "--max-steps", "4"]
    assert train_lora.main(common + ["--max-minutes", "0.00001"]) == 0  # budget gone after the first step
    run = json.loads((tmp_path / "run.json").read_text())
    assert run["status"].startswith("paused") and run["final_step"] == 1
    assert not (tmp_path / "adapter").exists()  # no final adapter until the run completes
    assert train_lora.latest_checkpoint(tmp_path).name == "step-000001"

    assert train_lora.main(common + ["--resume", "auto"]) == 0
    run = json.loads((tmp_path / "run.json").read_text())
    assert run["status"] == "completed" and run["final_step"] == 4
    rows = [json.loads(line) for line in (tmp_path / "metrics.jsonl").read_text().splitlines()]
    assert [r["samples_seen"] for r in rows] == [2, 4, 6, 8]  # 2 per update, continuing across the pause


def test_saved_adapter_reloads_and_disable_adapter_gives_the_base_model(tmp_path):
    """What eval_lora.py relies on: PeftModel.from_pretrained restores the trained
    adapter exactly, and disable_adapter() gives back the pretrained UNet."""
    from peft import PeftModel

    class Spy(torch.nn.Module):  # records the exact UNet inputs compute_loss builds
        def __init__(self, inner):
            super().__init__()
            self.inner, self.inputs = inner, None

        def get_base_model(self):
            return self.inner.get_base_model()

        def forward(self, *args, **kwargs):
            self.inputs = (args, kwargs)
            return self.inner(*args, **kwargs)

    def unet_output(unet, inputs):
        with torch.no_grad():
            return unet(*inputs[0], **inputs[1]).sample

    c = tiny_components()
    trained = train_lora.add_lora(c.unet, TrainConfig(rank=4, alpha=8))
    with torch.no_grad():
        for n, p in trained.named_parameters():
            if "lora_B" in n:
                p.normal_(0, 0.5)  # a non-zero adapter, as after training
    trained.eval()
    spy = Spy(trained)
    train_lora.compute_loss(c, spy, batch_of(1), H, "cpu", "cpu")
    with_lora = unet_output(trained, spy.inputs)
    trained.save_pretrained(str(tmp_path / "adapter"))

    reloaded = PeftModel.from_pretrained(tiny_components().unet, str(tmp_path / "adapter"))  # same seed, same base
    reloaded.eval()
    assert torch.allclose(unet_output(reloaded, spy.inputs), with_lora, atol=1e-5)
    with reloaded.disable_adapter():
        base_out = unet_output(reloaded, spy.inputs)
    plain = tiny_components().unet
    assert torch.allclose(base_out, unet_output(plain, spy.inputs), atol=1e-5)
    assert not torch.allclose(base_out, with_lora, atol=1e-3)


DRESSCODE = REPO_ROOT / "datasets" / "DressCode" / "DressCode"


@pytest.mark.skipif(not (DRESSCODE / "upper_body" / "train_pairs.txt").exists(), reason="needs datasets/DressCode")
def test_dresscode_pack_trains_on_all_three_categories(tmp_path, monkeypatch):
    """The DressCode pack (masks + DensePose made by build_dresscode_pack.py) goes
    through the real dataset, loss and optimiser for tops, bottoms and dresses."""
    import subprocess

    pack = tmp_path / "pack"
    subprocess.run([sys.executable, str(LORA_DIR / "build_dresscode_pack.py"), str(pack), "--root", str(DRESSCODE),
                    "--per-category", "1", "--eval-per-category", "1", "--workers", "1"], check=True,
                   capture_output=True)
    records = read_manifest(pack / "manifests" / "dresscode_train.jsonl")
    assert sorted(r["category"] for r in records) == ["dress", "lower", "upper"]
    ds = TryOnTrainDataset(records, pack / "data", H, W, "repo")
    for i, r in enumerate(records):
        b = ds[i]
        repaint = b["inpaint_mask"].mean().item()
        assert 0.02 < repaint < 0.8, (r["sample_id"], repaint)  # a garment-sized region, not empty or everything
        assert b["pose_img"].abs().sum() > 0  # DensePose rendered

    monkeypatch.setattr(train_lora, "load_components", lambda base, root: tiny_components())
    out = tmp_path / "run"
    assert train_lora.main(["--repo", IDM_REPO, "--manifest", str(pack / "manifests" / "dresscode_train.jsonl"),
                            "--data-root", str(pack / "data"), "--out", str(out), "--height", str(H), "--width", str(W),
                            "--rank", "4", "--alpha", "8", "--max-steps", "3", "--grad-accum", "1",
                            "--warmup-steps", "1", "--log-every", "1", "--save-every", "3", "--num-workers", "0"]) == 0
    rows = [json.loads(line) for line in (out / "metrics.jsonl").read_text().splitlines()]
    assert [r["samples_seen"] for r in rows] == [1, 2, 3] and all(r["loss"] > 0 for r in rows)
