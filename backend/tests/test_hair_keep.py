"""services/tryon/hair_keep.py: long hair is never repainted by the try-on."""

import numpy as np
from PIL import Image

from services.tryon.hair_keep import HAIR_LABEL, mask_without_hair, paste_hair_back


def parse_with_hair(size=(384, 512), box=(150, 50, 230, 400)):
    """A parsing map (label image) with a long strip of hair over the torso."""
    arr = np.zeros((size[1], size[0]), np.uint8)
    arr[100:450, 120:260] = 4  # upper clothes
    l, t, r, b = box
    arr[t:b, l:r] = HAIR_LABEL
    return Image.fromarray(arr, mode="L")


def test_hair_is_taken_out_of_the_repaint_mask():
    parse = parse_with_hair()
    mask = Image.new("L", (384, 512), 255)  # repaint everything
    out = np.asarray(mask_without_hair(mask, parse))
    assert out[200, 190] == 0  # hair over the chest: kept
    assert out[420, 140] == 255  # shirt without hair over it: still repainted
    assert out.shape == (512, 384)


def test_mask_of_another_size_is_handled():
    out = mask_without_hair(Image.new("L", (768, 1024), 255), parse_with_hair())
    assert out.size == (768, 1024) and np.asarray(out)[400, 380] == 0


def test_original_hair_pixels_come_back_with_a_soft_edge():
    person = Image.new("RGB", (768, 1024), (20, 15, 10))  # dark hair colour everywhere
    result = Image.new("RGB", (768, 1024), (200, 190, 180))  # the generated shirt
    out = np.asarray(paste_hair_back(person, result, parse_with_hair()))
    assert tuple(out[400, 380]) == (20, 15, 10)  # middle of the hair: exactly the person's pixels
    assert tuple(out[900, 260]) == (200, 190, 180)  # away from the hair: the try-on result
    edge = out[400, 300]  # the hair's left edge (x = 300 at 768 px): blended, not a hard cut
    assert (20, 15, 10) != tuple(edge) or (200, 190, 180) != tuple(edge)


def test_no_hair_changes_nothing():
    parse = Image.fromarray(np.zeros((512, 384), np.uint8), mode="L")
    mask = Image.new("L", (384, 512), 255)
    assert mask_without_hair(mask, parse) is mask
    result = Image.new("RGB", (768, 1024), (1, 2, 3))
    assert tuple(np.asarray(paste_hair_back(Image.new("RGB", (768, 1024)), result, parse))[10, 10]) == (1, 2, 3)


def test_palette_parsing_map_as_idm_vton_returns_it():
    parse = parse_with_hair().convert("P")  # IDM's Parsing() returns a palette ("P") label image
    out = np.asarray(mask_without_hair(Image.new("L", (384, 512), 255), parse))
    assert out[200, 190] == 0
