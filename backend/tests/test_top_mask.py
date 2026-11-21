"""top_mask.cover_old_sleeves: the old top's sleeves, parsed as trousers, are repainted too (20 Nov 2026)."""

from __future__ import annotations

import numpy as np
from PIL import Image

from services.tryon.top_mask import PANTS, UPPER, cover_old_sleeves

W, H = 384, 512


def scene(strip_label=PANTS, strip_colour=(15, 15, 15), pants_colour=(240, 240, 240), strip_touches=True):
    """A black top (rows 100-260) over white trousers (rows 260-500), with a black sleeve strip hanging
    over the trousers at the left (cols 60-80, rows 260-400). The repaint mask covers the top and,
    unless strip_touches is False, the arm down to the strip's left edge."""
    person = np.full((H, W, 3), 200, np.uint8)
    labels = np.zeros((H, W), np.uint8)
    person[100:260, 60:320] = 15
    labels[100:260, 60:320] = UPPER
    person[260:500, 90:290] = pants_colour
    labels[260:500, 90:290] = PANTS
    person[260:400, 60:90] = strip_colour  # the sleeve, over the trousers' edge
    labels[260:400, 60:90] = strip_label
    mask = np.zeros((H, W), np.uint8)
    mask[95:265, 55:325] = 255
    if strip_touches:
        mask[260:400, 40:60] = 255  # the arm line, right beside the strip
    return (Image.fromarray(mask, mode="L"), Image.fromarray(labels, mode="L"), Image.fromarray(person))


def repainted(mask: Image.Image) -> np.ndarray:
    return np.asarray(mask) > 127


def test_a_sleeve_parsed_as_trousers_is_repainted():
    mask, parse, person = scene()
    out = repainted(cover_old_sleeves(mask, parse, person))
    assert out[300:390, 62:88].all()  # the whole strip
    assert not out[300:490, 100:280].any()  # the white trousers stay
    assert (out | ~repainted(mask)).all()  # nothing that was repainted is dropped


def test_the_mask_keeps_its_size_and_type():
    mask, parse, person = scene()
    big = mask.resize((768, 1024), Image.NEAREST)
    out = cover_old_sleeves(big, parse, person)
    assert out.size == (768, 1024) and out.mode == "L"


def test_top_and_trousers_of_similar_colour_are_left_alone():
    mask, parse, person = scene(pants_colour=(40, 40, 40))  # black top, near-black trousers
    assert np.array_equal(np.asarray(cover_old_sleeves(mask, parse, person)), np.asarray(mask))


def test_a_dark_print_inside_the_trousers_is_left_alone():
    mask, parse, person = scene(strip_colour=(240, 240, 240), strip_touches=False)  # no sleeve this time
    pixels = np.asarray(person).copy()
    pixels[400:430, 150:220] = 15  # a black print on the trousers, away from the repaint area
    person = Image.fromarray(pixels)
    assert np.array_equal(np.asarray(cover_old_sleeves(mask, parse, person)), np.asarray(mask))


def test_trouser_coloured_pixels_never_join():
    mask, parse, person = scene(strip_colour=(235, 235, 235))  # the "strip" is just more trousers
    assert np.array_equal(np.asarray(cover_old_sleeves(mask, parse, person)), np.asarray(mask))


def test_no_trousers_in_the_photo_changes_nothing():
    mask, parse, person = scene()
    labels = np.asarray(parse).copy()
    labels[labels == PANTS] = 0
    parse = Image.fromarray(labels, mode="L")
    assert np.array_equal(np.asarray(cover_old_sleeves(mask, parse, person)), np.asarray(mask))
