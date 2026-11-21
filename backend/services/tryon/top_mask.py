"""Repaint all of the old top when a top is tried on (20 Nov 2026).

IDM-VTON's garment mask (utils_mask.get_mask_location, "upper_body") never
repaints pixels the human parser calls trousers or a skirt, so the trousers stay
as they are. But where a sleeve hangs over the trousers, the parser often calls
that strip of sleeve "trousers" too. It is then kept, and the model reads it as
a long-sleeved layer under the new top: in the E2E run a short-sleeved white
shirt came out with black forearm sleeves on BOTH arms (the person's own black
long-sleeved top showed in a 2,277-pixel strip over her white jeans).

`cover_old_sleeves` adds those pixels to the repaint mask: parsed as trousers or
skirt, clearly the colour of the person's top rather than of the trousers, and
connected to the area already being repainted. If the top and the trousers are
similar colours, a sleeve can't be told from the trousers, and the mask is left
exactly as IDM-VTON made it.

Pure PIL / numpy: imported by the Modal app and tested on any machine.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageFilter

UPPER = 4  # ATR human-parsing labels used by IDM-VTON (utils_mask.label_map)
SKIRT, PANTS = 5, 6
MIN_PIXELS = 200  # less top or trousers than this (at 384x512): nothing to compare
MIN_COLOUR_GAP = 60.0  # RGB distance between the top's and the trousers' median colours
CLOSER = 0.5  # a pixel joins only if it is at least twice as close to the top's colour
MAX_SHARE = 0.03  # never add more than 3 % of the photo (something else is going on)


def _dilate(m: np.ndarray, size: int = 3) -> np.ndarray:
    img = Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(size))
    return np.asarray(img) > 127


def cover_old_sleeves(mask: Image.Image, parse: Image.Image, person: Image.Image) -> Image.Image:
    """The repaint mask (white = repaint) plus any of the old top that was parsed as trousers."""
    labels = np.asarray(parse)
    h, w = labels.shape
    top = labels == UPPER
    lower = np.isin(labels, (SKIRT, PANTS))
    if top.sum() < MIN_PIXELS or lower.sum() < MIN_PIXELS:
        return mask
    rgb = np.asarray(person.convert("RGB").resize((w, h))).astype(np.float32)
    top_colour = np.median(rgb[top], axis=0)
    lower_colour = np.median(rgb[lower], axis=0)
    if float(np.linalg.norm(top_colour - lower_colour)) < MIN_COLOUR_GAP:
        return mask
    repaint = np.asarray(mask.convert("L").resize((w, h), Image.NEAREST)) > 127
    to_top = np.linalg.norm(rgb - top_colour, axis=2)
    to_lower = np.linalg.norm(rgb - lower_colour, axis=2)
    candidate = lower & ~repaint & (to_top < CLOSER * to_lower)
    # grow from the repaint area's edge through candidate pixels only (connected strips)
    added = candidate & _dilate(repaint)
    for _ in range(max(h, w)):
        grown = added | (_dilate(added) & candidate)
        if grown.sum() == added.sum():
            break
        added = grown
    if not added.any() or added.mean() > MAX_SHARE:
        return mask
    added = _dilate(added, 5) & lower  # the strip's soft edge, still only where the trousers were
    out = np.asarray(mask.convert("L").resize((w, h), Image.NEAREST)).copy()
    out[added] = 255
    return Image.fromarray(out, mode="L").resize(mask.size, Image.NEAREST)
