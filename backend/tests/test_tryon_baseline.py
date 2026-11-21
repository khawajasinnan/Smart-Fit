"""Try-on baseline kit (spec §8.1): pack-building helpers and result summaries."""

import json

from PIL import Image, ImageDraw

from services.tryon.baseline.build_pack import idm_captions, looks_like_flatlay, pad_to_garment
from services.tryon.baseline.common import summarise, write_results


def test_idm_captions_follow_idm_vton_template_order():
    tags = {"data": [
        {"file_name": "a.jpg", "tag_info": [
            {"tag_name": "item", "tag_category": "T-shirts"},
            {"tag_name": "colors", "tag_category": "Navy"},
            {"tag_name": "neckLine", "tag_category": "Round Neck"},
            {"tag_name": "sleeveLength", "tag_category": "Short Sleeve"},
        ]},
        {"file_name": "b.jpg", "tag_info": [
            {"tag_name": "item", "tag_category": "Blouses"},
            {"tag_name": "neckLine", "tag_category": None},
        ]},
        {"file_name": "c.jpg", "tag_info": []},
    ]}
    captions = idm_captions(tags)
    assert captions["a.jpg"] == "Short Sleeve Round Neck T-shirts"  # sleeveLength, neckLine, item
    assert captions["b.jpg"] == "Blouses"
    assert captions["c.jpg"] == ""  # the pack then falls back to "shirts", like IDM-VTON


def test_pad_to_garment_is_768x1024_with_background_padding():
    wide = Image.new("RGB", (1000, 500), (240, 240, 240))
    ImageDraw.Draw(wide).rectangle((400, 150, 600, 350), fill=(200, 0, 0))
    out = pad_to_garment(wide)
    assert out.size == (768, 1024)
    assert out.getpixel((384, 20)) == (240, 240, 240)  # padding takes the photo's background, not white
    assert out.getpixel((384, 512))[0] > 150  # garment stays centred


def _garment(size, box, bg=(238, 238, 238)):
    img = Image.new("RGB", size, bg)
    ImageDraw.Draw(img).rectangle(box, fill=(60, 60, 140))
    return img


def test_flatlay_whole_garment_on_plain_background():
    assert looks_like_flatlay(_garment((900, 1200), (200, 250, 700, 950)))


def test_flatlay_rejects_close_up_touching_edges():
    assert not looks_like_flatlay(_garment((900, 1200), (0, 300, 900, 1200)))


def test_flatlay_rejects_dark_or_busy_background_and_tiny_items():
    assert not looks_like_flatlay(_garment((900, 1200), (200, 250, 700, 950), bg=(30, 30, 30)))
    assert not looks_like_flatlay(_garment((900, 1200), (430, 580, 470, 620)))


def test_idm_garment_unet_wrapper_moves_inputs_and_returns_features_home():
    import torch

    from services.tryon.baseline.run_idmvton import on_device

    seen = {}

    class FakeGarmentUNet(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.w = torch.nn.Parameter(torch.ones(1, dtype=torch.float16))

        @property
        def dtype(self):
            return self.w.dtype

        def forward(self, sample, timestep, encoder_hidden_states, return_dict=True):
            seen.update(sample=sample.device, t=timestep.device, return_dict=return_dict)
            return (sample,), [sample * 2, encoder_hidden_states]

    wrapped = on_device(FakeGarmentUNet(), "cpu", "cpu")
    out, features = wrapped(torch.ones(1, 4), torch.tensor(5), torch.zeros(1, 2), return_dict=False)
    assert seen == {"sample": torch.device("cpu"), "t": torch.device("cpu"), "return_dict": False}
    assert isinstance(features, list) and len(features) == 2
    assert torch.equal(features[0], torch.full((1, 4), 2.0))
    assert wrapped.device == torch.device("cpu") and wrapped.dtype == torch.float16


def test_summarise_skips_warmup_and_failures(tmp_path):
    jobs = [
        {"id": "a", "status": "ok", "seconds": 40.0, "peak_reserved_gb": 9.0},
        {"id": "b", "status": "ok", "seconds": 10.0, "peak_reserved_gb": 9.5},
        {"id": "c", "status": "ok", "seconds": 12.0, "peak_reserved_gb": 9.2},
        {"id": "d", "status": "oom"},
    ]
    s = summarise(jobs)
    assert s == {"jobs_ok": 3, "jobs_failed": 1, "median_seconds_per_image": 11.0,
                 "max_seconds_per_image": 12.0, "peak_vram_reserved_gb": 9.5}
    write_results(tmp_path, {"summary": s, "jobs": jobs})
    assert json.loads((tmp_path / "results.json").read_text())["summary"]["jobs_ok"] == 3
