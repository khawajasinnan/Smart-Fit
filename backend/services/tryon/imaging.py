"""Image checks and framing for the try-on service (SFR-026, SFR-027).

Every photo is decoded and re-encoded here before it goes anywhere: that
validates it server-side (rules.md §5), applies the phone's EXIF rotation and
drops all metadata (location etc.). IDM-VTON works on 768x1024 (3:4) frames,
the size it was trained on, so person and garment are framed to exactly that.
"""

from __future__ import annotations

import base64
import binascii
import io
import re

from PIL import Image, ImageOps, UnidentifiedImageError

from shared.schemas.errors import AppError

SIZE = (768, 1024)  # IDM-VTON's training resolution (W, H)
MIN_SIDE = 384  # smaller photos of the person can't give a usable 768x1024 try-on
MIN_GARMENT_SIDE = 256  # a garment photo is only used for its look, so it may be smaller
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "MPO"}  # MPO: some phone cameras' JPEG variant

_DATA_URL = re.compile(r"^data:image/[a-z+.-]+;base64,", re.IGNORECASE)


def _photo_error(code: str, message: str, angle: str | None) -> AppError:
    return AppError(422, code, message, {"angle": angle} if angle else None)


def decode_photo(image_base64: str, *, max_bytes: int, angle: str | None = None, min_side: int = MIN_SIDE,
                 person: bool = False) -> Image.Image:
    """Base64 user photo -> upright RGB image, or a clear 422 the app can show.
    `angle` names the photo in the error ("front", ..., or "garment").
    `person`: a photo of the person, judged by the size it has once framed (see open_image)."""
    raw_b64 = _DATA_URL.sub("", image_base64.strip())
    try:
        data = base64.b64decode(raw_b64, validate=False)
    except (binascii.Error, ValueError) as exc:
        raise _photo_error("INVALID_IMAGE", "That photo couldn't be read. Please take it again.", angle) from exc
    if len(data) > max_bytes:
        raise _photo_error(
            "IMAGE_TOO_LARGE", f"That photo is too large (max {max_bytes // 1_000_000} MB). Please use a smaller one.", angle
        )
    return open_image(data, angle=angle, min_side=min_side, person=person)


def open_image(data: bytes, *, angle: str | None = None, min_side: int = MIN_SIDE, person: bool = False) -> Image.Image:
    """`person`: frame_person always makes a person photo 3:4 from its HEIGHT (a
    tall photo is padded at the sides, a wide one cropped), so what matters is
    that framed size, 0.75 x height wide (20 Nov 2026: a sharp, tightly cropped
    330 x 1200 full-body photo was refused by the shortest-side rule, and a wide
    800 x 400 one passed although it only gives a 300 x 400 frame)."""
    try:
        img = Image.open(io.BytesIO(data))
        fmt = img.format
        img.load()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise _photo_error("INVALID_IMAGE", "That file isn't a photo we can use. Please use a JPG or PNG.", angle) from exc
    if fmt not in ALLOWED_FORMATS:
        raise _photo_error("INVALID_IMAGE", "Please use a JPG, PNG or WebP photo.", angle)
    img = ImageOps.exif_transpose(img).convert("RGB")
    short_side = img.height * 3 / 4 if person else min(img.size)
    if short_side < min_side:
        raise _photo_error(
            "IMAGE_TOO_SMALL",
            "That photo is too small for a try-on. Please use your phone camera at normal quality.",
            angle,
        )
    return img


def border_colour(img: Image.Image) -> tuple[int, int, int]:
    """Median colour of a thin frame around the image (the photo's backdrop)."""
    small = img.convert("RGB").resize((64, 64))
    px = small.load()
    edge = [px[x, y] for x in range(64) for y in (0, 1, 62, 63)] + [px[x, y] for y in range(64) for x in (0, 1, 62, 63)]
    return tuple(sorted(c[i] for c in edge)[len(edge) // 2] for i in range(3))  # type: ignore[return-value]


def frame_person(img: Image.Image) -> Image.Image:
    """Person photo -> 768x1024 without cutting off the head or feet.

    A taller-than-3:4 photo (e.g. a 9:16 phone shot) is padded at the sides
    with its own backdrop colour; a wider one is cropped at the sides (the
    camera guides keep the person centred)."""
    w, h = img.size
    if w * 4 < h * 3:  # too tall: pad width
        cw = round(h * 3 / 4)
        canvas = Image.new("RGB", (cw, h), border_colour(img))
        canvas.paste(img, ((cw - w) // 2, 0))
        img = canvas
    elif w * 4 > h * 3:  # too wide: crop width around the centre
        cw = round(h * 3 / 4)
        left = (w - cw) // 2
        img = img.crop((left, 0, left + cw, h))
    return img.resize(SIZE, Image.LANCZOS)


def frame_garment(img: Image.Image) -> Image.Image:
    """Garment photo centred on a 3:4 canvas of its own background colour —
    the same framing as the baseline evaluation (baseline/build_pack.py)."""
    w, h = img.size
    if w * 4 > h * 3:
        cw, ch = w, round(w * 4 / 3)
    else:
        cw, ch = round(h * 3 / 4), h
    canvas = Image.new("RGB", (cw, ch), border_colour(img))
    canvas.paste(img, ((cw - w) // 2, (ch - h) // 2))
    return canvas.resize(SIZE, Image.LANCZOS)


def _backdrop_stats(img: Image.Image) -> tuple[int, float, float]:
    """(darkest backdrop channel, share of the edge strip that isn't backdrop, share of the photo that isn't)."""
    import numpy as np

    a = np.asarray(img.convert("RGB").resize((192, 256))).astype(np.int16)
    bg = np.array(border_colour(img), dtype=np.int16)
    fg = np.abs(a - bg).max(axis=2) > 30
    edge = np.concatenate([fg[:4].ravel(), fg[-4:].ravel(), fg[:, :4].ravel(), fg[:, -4:].ravel()])
    return int(min(bg)), float(edge.mean()), float(fg.mean())


def looks_like_flatlay(img: Image.Image) -> bool:
    """Whole garment on a plain light background (IDM-VTON's best input):
    uniform border, garment not touching the edges, neither tiny nor huge.
    Same rule as baseline/build_pack.py, which picked the evaluation garments."""
    darkest, edge, share = _backdrop_stats(img)
    return darkest >= 200 and edge < 0.02 and 0.15 < share < 0.85


def plain_backdrop(img: Image.Image) -> bool:
    """A studio shot: light, even backdrop all round and nothing touching the edges.

    Weaker than `looks_like_flatlay`, which also needs the garment to stand out:
    a white garment on a pale grey backdrop differs from it by under 30 levels
    (20 Nov 2026, Outfitters: 1-6 % of the photo "seen"), so only this test
    passes. Models photographed on the same backdrop pass it too: callers
    must also know that nobody is in the photo."""
    darkest, edge, _ = _backdrop_stats(img)
    return darkest >= 200 and edge < 0.02


def to_jpeg(img: Image.Image, quality: int = 92) -> bytes:
    """Re-encode (this also strips every bit of metadata)."""
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=quality, optimize=True)
    return buf.getvalue()


_NOISE = re.compile(r"[^a-z0-9 ]+")


# Sleeve length in IDM-VTON's caption words, read from a product / garment name.
_SLEEVE_NAMES = (
    ("sleeveless", re.compile(r"\bsleeve ?less\b", re.I)),
    ("long sleeve", re.compile(r"\b(full|long)[ -]?sleeves?\b", re.I)),
    ("short sleeve", re.compile(r"\b(half|short)[ -]?sleeves?\b", re.I)),
    ("cropped sleeve", re.compile(r"\b3/4\b|\bthree[ -]quarter\b", re.I)),
)


def sleeve_from_name(name: str) -> str | None:
    """"Full Sleeve Kurta" -> "long sleeve"; None when the name doesn't say (or says two things)."""
    hits = [word for word, rx in _SLEEVE_NAMES if rx.search(name or "")]
    return hits[0] if len(hits) == 1 else None


_SLEEVE_PHRASE = re.compile(r"\b(?:(?:full|long|half|short)[ -]?sleeves?|sleeve ?less|three[ -]quarter sleeves?|sleeves?)\b",
                            re.I)


def canonical_sleeve(caption: str, sleeve: str) -> str:
    """The name's own sleeve words swapped for IDM-VTON's ("half sleeve tee" -> "short sleeve tee")."""
    rest = " ".join(_SLEEVE_PHRASE.sub(" ", caption).split())
    return f"{sleeve} {rest}".strip()[:96]


def with_sleeve(caption: str, sleeve: str | None) -> str:
    """Put the sleeve length in front of the caption, as in IDM-VTON's training captions
    ("long sleeve button up shirt"). Without it the model guesses and tends to keep the
    person's own sleeve length (20 Nov 2026: a long-sleeved shirt came out elbow-length)."""
    if not sleeve or "sleeve" in caption.lower():
        return caption
    return f"{sleeve} {caption}"[:96]


def garment_caption(name: str, category: str | None = None) -> str:
    """Product name -> IDM-VTON garment text ("model is wearing <caption>").

    Keeps the descriptive words of the retailer's own product name and drops
    codes and symbols, e.g. "Relaxed Fit Hoodie - F0123/24" -> "relaxed fit hoodie"."""
    words = [w for w in _NOISE.sub(" ", name.lower()).split() if not any(ch.isdigit() for ch in w)]
    caption = " ".join(words)[:80].strip()
    if not caption:
        caption = (category or "clothes").replace("-", " ")
    return caption
