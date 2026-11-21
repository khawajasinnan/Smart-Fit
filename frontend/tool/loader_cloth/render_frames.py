"""Render the loader's spinning 3D tee (cloth.html) into assets/loader/cloth_NN.png.

    python tool/loader_cloth/render_frames.py            # from frontend/; needs Chrome + Pillow

Each frame is rendered by headless Chrome at 600x600 (headless needs a wide
window), then shrunk to 160x160 so the loader stays small (~10 KB a frame).
"""

import subprocess
import sys
from pathlib import Path

from PIL import Image

FRAMES = 24
SIZE = 160
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

here = Path(__file__).resolve().parent
out = here.parents[1] / "assets" / "loader"
out.mkdir(parents=True, exist_ok=True)
page = (here / "cloth.html").as_uri()

for i in range(FRAMES):
    raw = out / f"_raw_{i:02d}.png"
    subprocess.run([CHROME, "--headless=new", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                    "--hide-scrollbars", "--allow-file-access-from-files", "--window-size=600,600",
                    "--default-background-color=00000000", "--virtual-time-budget=2000",
                    f"--screenshot={raw}", f"{page}?frame={i}&frames={FRAMES}"],
                   check=True, capture_output=True)
    Image.open(raw).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS).save(out / f"cloth_{i:02d}.png", optimize=True)
    raw.unlink()
    print(f"frame {i + 1}/{FRAMES}", file=sys.stderr)
print(f"{FRAMES} frames -> {out}")
