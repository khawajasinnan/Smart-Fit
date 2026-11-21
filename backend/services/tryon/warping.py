"""Cloth warping: the garment photo fitted to the person's body (21 Nov 2026).

The user asked for the cloth warping module of a classic try-on pipeline, shown in the
app. IDM-VTON (the diffusion model that makes the final image) has no separate warping
step, so this is the classic geometric one (VITON / CP-VTON's "geometric matching" with a
thin-plate spline), run on the CPU while the GPU works:

1. The garment's outline from its studio photo (the plain backdrop is removed).
2. Its landmarks from that outline: neckline, shoulders, armpits, hem corners, and
   the sleeve ends when the sleeves stick out; for bottoms the waistband and hem corners.
3. The same points on the person from the HRNet body keypoints the try-on's photo check
   already found (shoulders, hips, elbows, wrists, knees, ankles).
4. A thin-plate spline maps the person's image onto the garment photo; sampling the
   garment through it lays the garment over the body.

The app shows the result as "Fitting your garment" while the final image is made, and
then as "How it was fitted" (garment -> fitted -> final). It is an honest coarse step:
no folds, no occlusion by arms; the diffusion model does the realistic rendering.
Pure numpy / PIL (no OpenCV in the try-on service).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter

SIZE = (768, 1024)  # the try-on's framed size (width, height) for both photos
MIN_CONFIDENCE = 0.3  # HRNet keypoints below this are not used
GARMENT_DIFF = 14  # max channel difference from the backdrop that counts as garment
GARMENT_DIFF_STRICT = 30  # ... for garments that stand out clearly (shadows stay out)
MIN_GARMENT_SHARE = 0.04
GRID_STEP = 4  # the spline is solved on a 1/4 grid, then the map is enlarged
TPS_SMOOTHING = 0.02  # some smoothing: an exact fit through every point can fold the garment


@dataclass(frozen=True)
class Point:
    x: float
    y: float


def garment_mask(garment: Image.Image) -> np.ndarray | None:
    """Boolean garment pixels of a studio photo (backdrop = the border colour), holes filled;
    None when no clear garment stands out."""
    rgb = np.asarray(garment.convert("RGB").resize(SIZE)).astype(np.int16)
    border = np.concatenate([rgb[:6].reshape(-1, 3), rgb[-6:].reshape(-1, 3), rgb[:, :6].reshape(-1, 3),
                             rgb[:, -6:].reshape(-1, 3)])
    backdrop = np.median(border, axis=0)
    diff = np.abs(rgb - backdrop).max(axis=2)
    # a clear garment uses a strict threshold, so the soft shadow beside it in store photos is left
    # out (it showed as light strips once stretched); a faint one (white on pale grey) needs the low one
    fg = diff > GARMENT_DIFF_STRICT
    if fg.mean() < 2 * MIN_GARMENT_SHARE:
        fg = diff > GARMENT_DIFF
    # the outline: the full-size photo, small gaps closed (smooth sides, no backdrop halo)
    full = Image.fromarray(fg.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))
    outline = np.asarray(full) > 127
    # holes inside it (a print the backdrop's colour): filled on a 1/4 grid, shrunk by one cell
    # so the fill never reaches past the outline
    small = Image.fromarray(outline.astype(np.uint8) * 255).resize((SIZE[0] // 4, SIZE[1] // 4), Image.NEAREST)
    core = Image.fromarray(_fill_holes(np.asarray(small) > 127).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3))
    mask = outline | (np.asarray(core.resize(SIZE, Image.NEAREST)) > 127)
    return mask if mask.mean() >= MIN_GARMENT_SHARE else None


def _fill_holes(mask: np.ndarray) -> np.ndarray:
    """Everything not reachable from the border through the backdrop is garment."""
    outside = np.zeros_like(mask)
    outside[0, :], outside[-1, :], outside[:, 0], outside[:, -1] = ~mask[0, :], ~mask[-1, :], ~mask[:, 0], ~mask[:, -1]
    for _ in range(max(mask.shape)):
        grown = outside.copy()
        grown[1:] |= outside[:-1]
        grown[:-1] |= outside[1:]
        grown[:, 1:] |= outside[:, :-1]
        grown[:, :-1] |= outside[:, 1:]
        grown &= ~mask
        if np.array_equal(grown, outside):
            break
        outside = grown
    return ~outside


def _row_span(mask: np.ndarray, y: int) -> tuple[int, int] | None:
    xs = np.flatnonzero(mask[max(0, min(mask.shape[0] - 1, y))])
    return (int(xs[0]), int(xs[-1])) if len(xs) else None


def garment_landmarks(mask: np.ndarray, category: str) -> dict[str, Point] | None:
    """Named landmarks of a garment outline (image coordinates), or None."""
    ys = np.flatnonzero(mask.any(axis=1))
    if len(ys) < 20:
        return None
    top, bottom = int(ys[0]), int(ys[-1])
    h = bottom - top
    if category == "lower":
        waist, hem = _row_span(mask, top + int(0.02 * h)), _row_span(mask, bottom - int(0.02 * h))
        if not waist or not hem:
            return None
        return {"waist_l": Point(waist[0], top), "waist_r": Point(waist[1], top),
                "hem_l": Point(hem[0], bottom), "hem_r": Point(hem[1], bottom)}
    # the torso: the narrowest rows of the middle band (sleeves stick out above it)
    band = [s for y in range(top + int(0.45 * h), top + int(0.75 * h)) if (s := _row_span(mask, y))]
    if not band:
        return None
    widths = sorted(s[1] - s[0] for s in band)
    torso_w = float(np.median(widths[: max(1, len(widths) // 3)]))
    centre = float(np.median([(s[0] + s[1]) / 2 for s in band]))
    half = torso_w / 2
    hem = _row_span(mask, bottom - int(0.02 * h)) or (centre - half, centre + half)
    # the shoulder line: the outline's width just under the collar (sleeves start lower)
    sh_y = top + int(0.08 * h)
    sh = _row_span(mask, sh_y) or (centre - half, centre + half)
    sh_half = max(half, min((sh[1] - sh[0]) / 2, half * 1.35))
    marks = {
        "neck": Point(centre, top),
        "shoulder_l": Point(centre - sh_half, sh_y),
        "shoulder_r": Point(centre + sh_half, sh_y),
        "armpit_l": Point(centre - half, top + 0.33 * h),
        "armpit_r": Point(centre + half, top + 0.33 * h),
        "hem_l": Point(hem[0], bottom),
        "hem_r": Point(hem[1], bottom),
    }
    xs_on = np.flatnonzero(mask.any(axis=0))
    left, right = int(xs_on[0]), int(xs_on[-1])
    if centre - left > half * 1.25 and right - centre > half * 1.25:  # sleeves stick out
        ly = int(np.median(np.flatnonzero(mask[:, left])))
        ry = int(np.median(np.flatnonzero(mask[:, right])))
        marks["sleeve_l"], marks["sleeve_r"] = Point(left, ly), Point(right, ry)
    return marks


def body_landmarks(keypoints: list[dict], category: str, garment: dict[str, Point],
                   long_sleeves: bool) -> dict[str, Point] | None:
    """The same landmarks on the person (image coordinates of the framed photo), from HRNet's
    named keypoints {name, x, y, confidence} (x, y normalised). Left / right are the IMAGE's
    sides, as in the garment photo, never the wearer's."""
    k = {p["name"]: Point(p["x"] * SIZE[0], p["y"] * SIZE[1]) for p in keypoints
         if p.get("confidence", 0) >= MIN_CONFIDENCE and "x" in p and "y" in p}

    def pair(name: str) -> tuple[Point, Point] | None:
        a, b = k.get(f"left_{name}"), k.get(f"right_{name}")
        return (a, b) if a and b else None

    hips = pair("hip")
    if hips is None:
        return None
    hl, hr = sorted(hips, key=lambda p: p.x)
    hip_w = hr.x - hl.x
    if category == "lower":
        legs = pair("ankle") or pair("knee")
        if legs is None:
            return None
        al, ar = sorted(legs, key=lambda p: p.x)
        return {"waist_l": Point(hl.x - 0.18 * hip_w, hl.y - 0.06 * hip_w), "waist_r": Point(hr.x + 0.18 * hip_w,
                                                                                              hr.y - 0.06 * hip_w),
                "hem_l": Point(al.x - 0.25 * hip_w, al.y), "hem_r": Point(ar.x + 0.25 * hip_w, ar.y)}
    shoulders = pair("shoulder")
    if shoulders is None:
        return None
    sl, sr = sorted(shoulders, key=lambda p: p.x)
    sw = sr.x - sl.x
    if sw <= 0:
        return None
    hem_y = max(hl.y, hr.y) + 0.12 * sw
    g_h = garment["hem_l"].y - garment["neck"].y
    g_w = garment["armpit_r"].x - garment["armpit_l"].x
    if category == "dress" or (g_w > 0 and g_h / g_w > 2.0):  # a long kameez / dress reaches the knees
        knees = pair("knee")
        if knees:
            hem_y = max(knees[0].y, knees[1].y)
    flare = 0.18 * hip_w if category == "dress" else 0.12 * hip_w
    marks = {
        "neck": Point((sl.x + sr.x) / 2, min(sl.y, sr.y) - 0.18 * sw),
        "shoulder_l": Point(sl.x - 0.1 * sw, sl.y),
        "shoulder_r": Point(sr.x + 0.1 * sw, sr.y),
        "armpit_l": Point(sl.x + 0.05 * sw, sl.y + 0.35 * (hl.y - sl.y)),
        "armpit_r": Point(sr.x - 0.05 * sw, sr.y + 0.35 * (hr.y - sr.y)),
        "hem_l": Point(hl.x - flare, hem_y),
        "hem_r": Point(hr.x + flare, hem_y),
    }
    if "sleeve_l" in garment:
        ends = pair("wrist") if long_sleeves else pair("elbow")
        if ends:
            el, er = sorted(ends, key=lambda p: p.x)
            if long_sleeves:
                marks["sleeve_l"], marks["sleeve_r"] = el, er
            else:  # a short sleeve ends about halfway down the upper arm
                marks["sleeve_l"] = Point((sl.x + el.x) / 2, (sl.y + el.y) / 2)
                marks["sleeve_r"] = Point((sr.x + er.x) / 2, (sr.y + er.y) / 2)
    return marks


def _tps_kernel(r2: np.ndarray) -> np.ndarray:
    with np.errstate(divide="ignore", invalid="ignore"):
        k = r2 * np.log(r2)
    return np.nan_to_num(k)


def tps_map(src: np.ndarray, dst: np.ndarray, width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    """For every pixel of the person image, where to read the garment photo: the thin-plate
    spline that takes the body landmarks (src) to the garment landmarks (dst)."""
    n = len(src)
    scale = float(max(width, height))
    s, d = src / scale, dst / scale
    k = _tps_kernel(((s[:, None, :] - s[None, :, :]) ** 2).sum(-1)) + TPS_SMOOTHING * np.eye(n)
    p = np.hstack([np.ones((n, 1)), s])
    a = np.zeros((n + 3, n + 3))
    a[:n, :n], a[:n, n:], a[n:, :n] = k, p, p.T
    rhs = np.zeros((n + 3, 2))
    rhs[:n] = d
    w = np.linalg.solve(a, rhs)
    gx, gy = np.meshgrid(np.arange(0, width, GRID_STEP, dtype=np.float64),
                         np.arange(0, height, GRID_STEP, dtype=np.float64))
    grid = np.stack([gx.ravel(), gy.ravel()], axis=1) / scale
    u = _tps_kernel(((grid[:, None, :] - s[None, :, :]) ** 2).sum(-1))
    out = (u @ w[:n] + np.hstack([np.ones((len(grid), 1)), grid]) @ w[n:]) * scale
    mx = Image.fromarray(out[:, 0].reshape(gx.shape).astype(np.float32)).resize((width, height), Image.BILINEAR)
    my = Image.fromarray(out[:, 1].reshape(gx.shape).astype(np.float32)).resize((width, height), Image.BILINEAR)
    return np.asarray(mx), np.asarray(my)


def _sample(img: np.ndarray, mx: np.ndarray, my: np.ndarray) -> np.ndarray:
    """Bilinear sampling of img (H, W, C) at (mx, my); outside reads as 0."""
    h, w = img.shape[:2]
    x0, y0 = np.floor(mx).astype(int), np.floor(my).astype(int)
    fx, fy = (mx - x0)[..., None], (my - y0)[..., None]
    inside = (x0 >= 0) & (y0 >= 0) & (x0 < w - 1) & (y0 < h - 1)
    x0c, y0c = np.clip(x0, 0, w - 2), np.clip(y0, 0, h - 2)
    a, b = img[y0c, x0c], img[y0c, x0c + 1]
    c, d = img[y0c + 1, x0c], img[y0c + 1, x0c + 1]
    out = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    return out * inside[..., None]


def fitting_preview(person: Image.Image, garment: Image.Image, keypoints: list[dict], category: str,
                    caption: str = "") -> Image.Image | None:
    """The garment warped onto the person (the person's photo, the warped garment on top), or
    None when the garment outline or the body landmarks can't be found."""
    mask = garment_mask(garment)
    if mask is None:
        return None
    g_marks = garment_landmarks(mask, category)
    if g_marks is None:
        return None
    b_marks = body_landmarks(keypoints, category, g_marks, long_sleeves="long sleeve" in caption.lower())
    if b_marks is None:
        return None
    # sleeve ends are not pinned: pinning them to the wrists tore long sleeves into streaks
    # (21 Nov 2026); without them the sleeves follow the shoulders' warp
    names = [n for n in g_marks if n in b_marks and not n.startswith("sleeve")]
    if len(names) < 4:
        return None
    src = np.array([[b_marks[n].x, b_marks[n].y] for n in names])
    dst = np.array([[g_marks[n].x, g_marks[n].y] for n in names])
    mx, my = tps_map(src, dst, *SIZE)
    g_rgb = np.asarray(garment.convert("RGB").resize(SIZE)).astype(np.float32)
    # the edge pulled in 4 px and softened: the soft shadow next to a garment in store photos
    # counts as garment and showed as a light outline once stretched
    edge = Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(9)).filter(
        ImageFilter.GaussianBlur(1.2))
    rgba = np.dstack([g_rgb, np.asarray(edge).astype(np.float32)])
    warped = _sample(rgba, mx, my)
    alpha = (warped[..., 3:] / 255.0) * 0.92
    base = np.asarray(person.convert("RGB").resize(SIZE)).astype(np.float32)
    out = base * (1 - alpha) + warped[..., :3] * alpha
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
