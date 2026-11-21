"""Cloth warping (21 Nov 2026): the garment photo fitted to the person's body outline."""

from __future__ import annotations

import numpy as np
from PIL import Image

from services.tryon import warping

W, H = warping.SIZE


def tee(colour=(200, 40, 60), backdrop=(235, 235, 235)) -> Image.Image:
    """A flat-lay T-shirt: torso plus two short sleeves sticking out, on a plain backdrop."""
    img = np.full((H, W, 3), backdrop, np.uint8)
    img[250:800, 230:540] = colour  # torso
    img[250:420, 130:230] = colour  # sleeve (image left)
    img[250:420, 540:640] = colour  # sleeve (image right)
    return Image.fromarray(img)


def trousers() -> Image.Image:
    img = np.full((H, W, 3), (230, 232, 236), np.uint8)
    img[150:300, 260:510] = (30, 40, 90)  # waistband + seat
    img[300:900, 260:375] = (30, 40, 90)  # legs
    img[300:900, 395:510] = (30, 40, 90)
    return Image.fromarray(img)


def keypoints(**over) -> list[dict]:
    """HRNet-style named keypoints (normalised) of a person standing facing the camera."""
    pts = {
        "left_shoulder": (0.62, 0.30), "right_shoulder": (0.38, 0.30),  # the wearer's left is the image's right
        "left_elbow": (0.66, 0.45), "right_elbow": (0.34, 0.45),
        "left_wrist": (0.67, 0.58), "right_wrist": (0.33, 0.58),
        "left_hip": (0.57, 0.58), "right_hip": (0.43, 0.58),
        "left_knee": (0.56, 0.76), "right_knee": (0.44, 0.76),
        "left_ankle": (0.56, 0.93), "right_ankle": (0.44, 0.93),
        **over,
    }
    return [{"name": n, "x": x, "y": y, "confidence": 0.9} for n, (x, y) in pts.items()]


def person() -> Image.Image:
    return Image.new("RGB", warping.SIZE, (120, 130, 140))


def test_the_garment_outline_is_found_and_holes_are_filled():
    img = np.asarray(tee()).copy()
    img[400:450, 350:420] = (235, 235, 235)  # a print the backdrop's colour, inside the garment
    mask = warping.garment_mask(Image.fromarray(img))
    assert mask is not None and mask[425, 385]  # filled
    assert not mask[50, 50] and not mask[900, 100]  # backdrop stays out


def test_a_faint_white_garment_on_pale_grey_is_found():
    mask = warping.garment_mask(tee(colour=(248, 248, 248), backdrop=(228, 230, 233)))
    assert mask is not None and mask[500, 380]


def test_an_empty_photo_has_no_garment():
    assert warping.garment_mask(Image.new("RGB", warping.SIZE, (235, 235, 235))) is None


def test_garment_landmarks_sit_where_a_top_has_them():
    marks = warping.garment_landmarks(warping.garment_mask(tee()), "upper")
    assert marks["neck"].y < marks["shoulder_l"].y < marks["armpit_l"].y < marks["hem_l"].y
    assert marks["shoulder_l"].x < marks["neck"].x < marks["shoulder_r"].x
    assert "sleeve_l" in marks and marks["sleeve_l"].x < marks["armpit_l"].x  # sleeves stick out


def test_body_landmarks_use_image_sides_not_the_wearers():
    g = warping.garment_landmarks(warping.garment_mask(tee()), "upper")
    b = warping.body_landmarks(keypoints(), "upper", g, long_sleeves=False)
    assert b["shoulder_l"].x < b["shoulder_r"].x  # image-left first, whatever HRNet calls it
    assert b["neck"].y < b["shoulder_l"].y < b["hem_l"].y


def test_no_shoulders_or_hips_means_no_landmarks():
    g = warping.garment_landmarks(warping.garment_mask(tee()), "upper")
    low = [k for k in keypoints() if "hip" not in k["name"]]
    assert warping.body_landmarks(low, "upper", g, long_sleeves=False) is None


def test_the_spline_reproduces_its_points():
    src = np.array([[100.0, 100.0], [600.0, 120.0], [120.0, 900.0], [650.0, 880.0], [380.0, 500.0]])
    dst = src * 0.8 + 40
    mx, my = warping.tps_map(src, dst, W, H)
    for (x, y), (tx, ty) in zip(src.astype(int), dst, strict=True):
        assert abs(mx[y, x] - tx) < 6 and abs(my[y, x] - ty) < 6


def test_a_fitting_preview_lays_the_garment_on_the_body():
    out = warping.fitting_preview(person(), tee(), keypoints(), "upper", "short sleeve t-shirt")
    assert out is not None and out.size == warping.SIZE
    px = np.asarray(out).astype(int)
    chest = px[int(0.42 * H), int(0.5 * W)]
    assert chest[0] > 150 and chest[1] < 100  # the red garment over the grey person
    assert tuple(px[20, 20]) == (120, 130, 140)  # far from the body: the photo as it was


def test_trousers_go_on_the_legs():
    out = warping.fitting_preview(person(), trousers(), keypoints(), "lower")
    assert out is not None
    px = np.asarray(out).astype(int)
    assert px[int(0.75 * H), int(0.44 * W)][2] > px[int(0.75 * H), int(0.44 * W)][0]  # navy on the leg
    assert tuple(px[int(0.25 * H), int(0.5 * W)]) == (120, 130, 140)  # the chest untouched


def test_without_legs_in_the_photo_trousers_get_no_preview():
    no_legs = [k for k in keypoints() if "knee" not in k["name"] and "ankle" not in k["name"]]
    assert warping.fitting_preview(person(), trousers(), no_legs, "lower") is None


def test_low_confidence_points_are_not_used():
    unsure = [{**k, "confidence": 0.1} for k in keypoints()]
    assert warping.fitting_preview(person(), tee(), unsure, "upper") is None
