"""Download the CV service's extra pretrained models into services/cv_analysis/models/.

  python scripts/download_cv_models.py            # from backend/, in .venv-cpu

1. MediaPipe Face Landmarker (478 face landmarks, Apache-2.0, 3.7 MB):
   face_landmarker.task, checksum-pinned.
2. HRNet-W32 (COCO 17 keypoints, 256x192 top-down; Sun et al., CVPR 2019).
   Weights: OpenMMLab's mmpose checkpoint hrnet_w32_coco_256x192 (Apache-2.0,
   trained on COCO), checksum-pinned. The network below is the official
   HRNet design (MIT, leoxiaobin/deep-high-resolution-net.pytorch) with the
   checkpoint's own layer names; it is loaded strictly and exported to ONNX.

Torch is only needed here (backend/.venv-cpu has it). The checkpoint is
loaded with torch.load(weights_only=True) (tensors only, no pickled code) and
deleted after export; the ONNX file (~115 MB) is gitignored.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

MODELS_DIR = Path(__file__).resolve().parents[1] / "services" / "cv_analysis" / "models"

FACE_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
FACE_SHA256 = "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"

HRNET_URL = "https://download.openmmlab.com/mmpose/top_down/hrnet/hrnet_w32_coco_256x192-c78dce93_20200708.pth"
HRNET_SHA256 = "c78dce9314145e6fb162b091111a55df2c34bffbcd69399e9d766694bd3acdfb"
HRNET_INPUT_W = 192
HRNET_INPUT_H = 256


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: Path, expected_sha256: str) -> None:
    if dest.exists() and sha256(dest) == expected_sha256:
        print(f"ok        {dest.name} (already downloaded)")
        return
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"download  {dest.name} <- {url}")
    with urllib.request.urlopen(url, timeout=60) as resp, tmp.open("wb") as out:  # noqa: S310 (pinned https URLs)
        while chunk := resp.read(1 << 20):
            out.write(chunk)
    actual = sha256(tmp)
    if actual != expected_sha256:
        tmp.unlink()
        sys.exit(f"checksum mismatch for {dest.name}: expected {expected_sha256}, got {actual}")
    tmp.replace(dest)
    print(f"ok        {dest.name} ({dest.stat().st_size / 1e6:.1f} MB, sha256 verified)")


def build_hrnet_w32(num_joints: int = 17):
    """HRNet-W32 (official design: a stem, a bottleneck layer, then stages of
    2, 3 and 4 parallel resolutions with repeated multi-scale fusion), module
    names matching mmpose's checkpoint ('backbone.*' / 'keypoint_head.*')."""
    from torch import nn

    def bn(c: int) -> nn.BatchNorm2d:
        return nn.BatchNorm2d(c)

    class BasicBlock(nn.Module):
        def __init__(self, c: int) -> None:
            super().__init__()
            self.conv1, self.bn1 = nn.Conv2d(c, c, 3, 1, 1, bias=False), bn(c)
            self.conv2, self.bn2 = nn.Conv2d(c, c, 3, 1, 1, bias=False), bn(c)
            self.relu = nn.ReLU(inplace=True)

        def forward(self, x):
            out = self.relu(self.bn1(self.conv1(x)))
            return self.relu(self.bn2(self.conv2(out)) + x)

    class Bottleneck(nn.Module):
        def __init__(self, cin: int, planes: int, downsample: nn.Module | None = None) -> None:
            super().__init__()
            self.conv1, self.bn1 = nn.Conv2d(cin, planes, 1, bias=False), bn(planes)
            self.conv2, self.bn2 = nn.Conv2d(planes, planes, 3, 1, 1, bias=False), bn(planes)
            self.conv3, self.bn3 = nn.Conv2d(planes, planes * 4, 1, bias=False), bn(planes * 4)
            self.relu = nn.ReLU(inplace=True)
            self.downsample = downsample

        def forward(self, x):
            out = self.relu(self.bn1(self.conv1(x)))
            out = self.relu(self.bn2(self.conv2(out)))
            out = self.bn3(self.conv3(out))
            return self.relu(out + (self.downsample(x) if self.downsample is not None else x))

    class HRModule(nn.Module):
        def __init__(self, channels: list[int], multiscale_output: bool) -> None:
            super().__init__()
            n = len(channels)
            self.branches = nn.ModuleList(
                nn.Sequential(*[BasicBlock(c) for _ in range(4)]) for c in channels
            )
            fuse = []
            for i in range(n if multiscale_output else 1):
                row: list[nn.Module | None] = []
                for j in range(n):
                    if j > i:
                        row.append(nn.Sequential(
                            nn.Conv2d(channels[j], channels[i], 1, bias=False), bn(channels[i]),
                            nn.Upsample(scale_factor=2 ** (j - i), mode="nearest"),
                        ))
                    elif j == i:
                        row.append(None)
                    else:
                        steps = []
                        for k in range(i - j):
                            if k == i - j - 1:
                                steps.append(nn.Sequential(
                                    nn.Conv2d(channels[j], channels[i], 3, 2, 1, bias=False), bn(channels[i])))
                            else:
                                steps.append(nn.Sequential(
                                    nn.Conv2d(channels[j], channels[j], 3, 2, 1, bias=False), bn(channels[j]),
                                    nn.ReLU(inplace=True)))
                        row.append(nn.Sequential(*steps))
                fuse.append(nn.ModuleList(row))
            self.fuse_layers = nn.ModuleList(fuse)
            self.relu = nn.ReLU(inplace=True)

        def forward(self, xs):
            xs = [branch(x) for branch, x in zip(self.branches, xs)]
            out = []
            for i, row in enumerate(self.fuse_layers):
                y = xs[0] if i == 0 else row[0](xs[0])
                for j in range(1, len(xs)):
                    y = y + (xs[j] if i == j else row[j](xs[j]))
                out.append(self.relu(y))
            return out

    def transition(cin: list[int], cout: list[int]) -> nn.ModuleList:
        layers: list[nn.Module | None] = []
        for i, c in enumerate(cout):
            if i < len(cin):
                layers.append(None if cin[i] == c else nn.Sequential(
                    nn.Conv2d(cin[i], c, 3, 1, 1, bias=False), bn(c), nn.ReLU(inplace=True)))
            else:
                layers.append(nn.Sequential(nn.Sequential(
                    nn.Conv2d(cin[-1], c, 3, 2, 1, bias=False), bn(c), nn.ReLU(inplace=True))))
        return nn.ModuleList(layers)

    class Backbone(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.conv1, self.bn1 = nn.Conv2d(3, 64, 3, 2, 1, bias=False), bn(64)
            self.conv2, self.bn2 = nn.Conv2d(64, 64, 3, 2, 1, bias=False), bn(64)
            self.relu = nn.ReLU(inplace=True)
            down = nn.Sequential(nn.Conv2d(64, 256, 1, bias=False), bn(256))
            self.layer1 = nn.Sequential(Bottleneck(64, 64, down), *[Bottleneck(256, 64) for _ in range(3)])
            c2, c3, c4 = [32, 64], [32, 64, 128], [32, 64, 128, 256]
            self.transition1 = transition([256], c2)
            self.stage2 = nn.Sequential(HRModule(c2, True))
            self.transition2 = transition(c2, c3)
            self.stage3 = nn.Sequential(*[HRModule(c3, True) for _ in range(4)])
            self.transition3 = transition(c3, c4)
            self.stage4 = nn.Sequential(*[HRModule(c4, i < 2) for i in range(3)])

        @staticmethod
        def _next(trans: nn.ModuleList, ys: list) -> list:
            return [ys[i] if t is None else t(ys[i] if i < len(ys) else ys[-1]) for i, t in enumerate(trans)]

        def forward(self, x):
            x = self.relu(self.bn1(self.conv1(x)))
            x = self.relu(self.bn2(self.conv2(x)))
            x = self.layer1(x)
            ys = [t(x) for t in self.transition1]
            ys = self.stage2(ys)
            ys = self.stage3(self._next(self.transition2, ys))
            ys = self.stage4(self._next(self.transition3, ys))
            return ys[0]

    class Head(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.final_layer = nn.Conv2d(32, num_joints, 1)

        def forward(self, x):
            return self.final_layer(x)

    class HRNetPose(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.backbone = Backbone()
            self.keypoint_head = Head()

        def forward(self, x):
            return self.keypoint_head(self.backbone(x))

    return HRNetPose()


def load_hrnet_weights(model, pth: Path) -> None:
    """Strict load: any missing, extra or mis-shaped tensor fails."""
    import torch

    checkpoint = torch.load(pth, map_location="cpu", weights_only=True)
    state = checkpoint.get("state_dict", checkpoint)
    model.load_state_dict(state, strict=True)


def export_hrnet(work_pth: Path, onnx_path: Path) -> None:
    import numpy as np
    import torch

    model = build_hrnet_w32().eval()
    load_hrnet_weights(model, work_pth)
    dummy = torch.randn(1, 3, HRNET_INPUT_H, HRNET_INPUT_W)
    tmp = onnx_path.with_suffix(".onnx.part")
    torch.onnx.export(
        model, dummy, str(tmp), input_names=["image"], output_names=["heatmaps"],
        opset_version=13, do_constant_folding=True, dynamo=False,
    )
    import cv2

    net = cv2.dnn.readNetFromONNX(str(tmp))
    net.setInput(dummy.numpy())
    out_cv = net.forward("heatmaps")
    with torch.no_grad():
        out_pt = model(dummy).numpy()
    err = float(np.abs(out_cv - out_pt).max())
    if err > 1e-3:
        tmp.unlink()
        sys.exit(f"HRNet ONNX export doesn't match PyTorch in OpenCV (max abs diff {err:.2e})")
    tmp.replace(onnx_path)
    print(f"ok        {onnx_path.name} ({onnx_path.stat().st_size / 1e6:.1f} MB, OpenCV matches PyTorch: {err:.1e})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-hrnet", action="store_true", help="skip the HRNet export")
    parser.add_argument("--hrnet-pth", type=Path, help="an already-downloaded HRNet checkpoint (checksum still verified)")
    args = parser.parse_args()
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    download(FACE_URL, MODELS_DIR / "face_landmarker.task", FACE_SHA256)
    if not args.skip_hrnet:
        hrnet_onnx = MODELS_DIR / "hrnet_w32_coco_256x192.onnx"
        if hrnet_onnx.exists():
            print(f"ok        {hrnet_onnx.name} (already exported)")
        else:
            pth = args.hrnet_pth or MODELS_DIR / "hrnet_w32_coco_256x192.pth"
            if args.hrnet_pth and sha256(pth) != HRNET_SHA256:
                sys.exit(f"checksum mismatch for {pth}")
            if not args.hrnet_pth:
                download(HRNET_URL, pth, HRNET_SHA256)
            export_hrnet(pth, hrnet_onnx)
            if not args.hrnet_pth:
                pth.unlink()


if __name__ == "__main__":
    main()
