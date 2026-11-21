"""LoRA settings for IDM-VTON (spec §8.4, §23.9).

Standalone (no SmartFit imports): this file runs inside the Kaggle training
environment. Values are the spec's starting point; change them only after a
full run has been observed (spec §8.4).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

# The try-on UNet's transformer attention only: self-attention (attn1, where
# the garment UNet's features are fused) and cross-attention (attn2). The
# plain names "to_q"... would also match the IP-Adapter Resampler's to_q.
TARGET_MODULES = r".*(down_blocks|mid_block|up_blocks)\..*\.attn[12]\.(to_q|to_k|to_v|to_out\.0)"


@dataclass
class TrainConfig:
    # LoRA (spec §8.4)
    rank: int = 16
    alpha: int = 32
    dropout: float = 0.1
    # optimisation (spec §8.4; batch 1 + accumulation, spec §23.9)
    learning_rate: float = 1e-4
    batch_size: int = 1
    grad_accum: int = 16
    warmup_steps: int = 500
    max_steps: int = 5000
    max_grad_norm: float = 1.0
    weight_decay: float = 1e-2
    # data
    height: int = 1024
    width: int = 768
    augment: str = "repo"  # "repo" (IDM-VTON's train_xl.py augmentations) or "none"
    num_workers: int = 2
    # bookkeeping
    save_every: int = 1000
    keep_checkpoints: int = 2
    log_every: int = 10
    seed: int = 42

    def as_dict(self) -> dict:
        return asdict(self) | {"target_modules": TARGET_MODULES}


def peft_config(cfg: TrainConfig):
    from peft import LoraConfig

    return LoraConfig(
        r=cfg.rank,
        lora_alpha=cfg.alpha,
        lora_dropout=cfg.dropout,
        target_modules=TARGET_MODULES,
        bias="none",
    )
