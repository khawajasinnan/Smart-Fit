"""LoRA training data: TryOnSample manifests -> IDM-VTON training tensors.

Standalone (runs on Kaggle). Produces exactly the tensors IDM-VTON's
train_xl.py VitonHDDataset produces, from manifest records (spec §5.6)
instead of VITON-HD folder conventions:

  image        person, [-1, 1]
  cloth_pure   garment, [-1, 1]            -> VAE -> garment UNet
  cloth        garment, CLIP pixel values  -> image encoder -> IP-Adapter
  pose_img     DensePose, [-1, 1]
  inpaint_mask 1 = garment region to repaint (binarised)
  im_mask      person with the garment region zeroed
  caption / caption_cloth   "model is wearing …" / "a photo of …"

Augmentation "repo" follows train_xl.py: each with p=0.5, horizontal flip
(all inputs), colour jitter (person and garment alike), scale 0.8-1.2 and
shift +-20 % (person, mask, pose). One correction: the jitter runs on [0, 1]
images; train_xl.py applies it to the already-normalised [-1, 1] person.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

import torch
import torchvision.transforms.functional as TF
from PIL import Image
from torch.utils.data import Dataset
from torchvision import transforms

REQUIRED_FIELDS = (
    "person_image_path", "cloth_image_path", "agnostic_mask_path", "densepose_path",
    "category", "source_dataset", "sample_id", "garment_caption",
)


class PassSampler(torch.utils.data.Sampler):
    """Endless sample order: a fresh seeded shuffle per pass over the data.

    `start` is how many samples were already drawn (from a checkpoint), so a
    resumed run continues the same order exactly: no pair is repeated or
    skipped because a Kaggle session ended mid-pass.
    """

    def __init__(self, size: int, seed: int, start: int = 0) -> None:
        if size <= 0:
            raise ValueError("empty dataset")
        self.size, self.seed, self.start = size, seed, start

    def order(self, pass_index: int) -> list[int]:
        return torch.randperm(self.size, generator=torch.Generator().manual_seed(self.seed + pass_index)).tolist()

    def __iter__(self):
        pass_index, offset = divmod(self.start, self.size)
        while True:
            yield from self.order(pass_index)[offset:]
            pass_index, offset = pass_index + 1, 0


def read_manifest(path: Path) -> list[dict]:
    records = []
    for n, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        record = json.loads(line)
        missing = [k for k in REQUIRED_FIELDS if k not in record]
        if missing:
            raise ValueError(f"{path}:{n}: missing {missing}")
        records.append(record)
    return records


class TryOnTrainDataset(Dataset):
    def __init__(self, records: list[dict], root: Path, height: int = 1024, width: int = 768,
                 augment: str = "repo") -> None:
        from transformers import CLIPImageProcessor

        if augment not in ("repo", "none"):
            raise ValueError(f"unknown augment {augment!r}")
        self.records, self.root = records, Path(root)
        self.size = (width, height)
        self.augment = augment
        self.clip = CLIPImageProcessor()
        self.jitter = transforms.ColorJitter(brightness=0.5, contrast=0.3, saturation=0.5, hue=0.5)

    def __len__(self) -> int:
        return len(self.records)

    def _open(self, rel: str, mode: str) -> Image.Image:
        with Image.open(self.root / rel) as img:
            return img.convert(mode).resize(self.size, Image.BICUBIC if mode == "RGB" else Image.NEAREST)

    def __getitem__(self, index: int) -> dict:
        r = self.records[index]
        image = TF.to_tensor(self._open(r["person_image_path"], "RGB"))
        cloth = TF.to_tensor(self._open(r["cloth_image_path"], "RGB"))
        mask = TF.to_tensor(self._open(r["agnostic_mask_path"], "L"))[:1]  # 1 = repaint
        pose = TF.to_tensor(self._open(r["densepose_path"], "RGB"))

        if self.augment == "repo":
            if random.random() > 0.5:
                image, cloth, mask, pose = (TF.hflip(t) for t in (image, cloth, mask, pose))
            if random.random() > 0.5:
                _, b, c, s, h = transforms.ColorJitter.get_params(
                    self.jitter.brightness, self.jitter.contrast, self.jitter.saturation, self.jitter.hue)
                image, cloth = (self._jitter(t, b, c, s, h) for t in (image, cloth))
            if random.random() > 0.5:
                scale = random.uniform(0.8, 1.2)
                image, mask, pose = self._affine(image, mask, pose, scale=scale, translate=(0, 0))
            if random.random() > 0.5:
                dx = random.uniform(-0.2, 0.2) * image.shape[-1]
                dy = random.uniform(-0.2, 0.2) * image.shape[-2]
                image, mask, pose = self._affine(image, mask, pose, scale=1.0, translate=(dx, dy))

        keep = 1 - mask
        keep = (keep >= 0.5).float()
        image_n = TF.normalize(image, [0.5], [0.5])
        caption = r["garment_caption"]
        return {
            "sample_id": r["sample_id"],
            "image": image_n,
            "cloth_pure": TF.normalize(cloth, [0.5], [0.5]),
            "cloth": self.clip(images=TF.to_pil_image(cloth), return_tensors="pt").pixel_values[0],
            "pose_img": TF.normalize(pose, [0.5], [0.5]),
            "inpaint_mask": 1 - keep,
            "im_mask": image_n * keep,
            "caption": "model is wearing " + caption,
            "caption_cloth": "a photo of " + caption,
        }

    @staticmethod
    def _jitter(t: torch.Tensor, b: float, c: float, s: float, h: float) -> torch.Tensor:
        # same order as train_xl.py: contrast, brightness, hue, saturation
        t = TF.adjust_contrast(t, c)
        t = TF.adjust_brightness(t, b)
        t = TF.adjust_hue(t, h)
        return TF.adjust_saturation(t, s).clamp(0, 1)

    @staticmethod
    def _affine(image, mask, pose, scale: float, translate: tuple[float, float]):
        # fills match train_xl.py: its person tensor is normalised, so 0 there is mid-grey (0.5 here)
        def move(t, fill):
            return TF.affine(t, angle=0.0, translate=list(translate), scale=scale, shear=[0.0], fill=fill)
        return move(image, [0.5] * 3), move(mask, [0.0]), move(pose, [0.0] * 3)
