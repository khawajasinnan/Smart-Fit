"""Keep the user's own hair in a try-on (20 Nov 2026).

IDM-VTON's garment mask (utils_mask.get_mask_location) keeps the face but not
the hair, so long hair lying over the shoulders, chest or back is repainted:
in the first 360° test a woman's long hair came back as a short bob. Two steps
fix it, both from the human-parsing map the mask is made from:

1. `mask_without_hair`: hair pixels are taken out of the repaint mask, so no
   garment is painted over them.
2. `paste_hair_back`: the generator still re-draws the whole image through its
   VAE, so the original hair pixels are put back on the result, with the
   edge pulled in a little and softened.

Known limit (tested 20 Nov 2026): where thin strands lie on a garment of nearly
the hair's colour (dark hair on a black top), the old garment between the
strands comes back with them as a darker edge. Four ways of recolouring that
edge were tried on real photos (colour matting, filling the gaps with the new
garment, fading the edge, filling the gaps with hair); every one looked worse
than this plain paste (speckles, blotches or an outline), so none is used.

Pure PIL / numpy: imported by the Modal app and tested on any machine.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageFilter

HAIR_LABEL = 2  # ATR human-parsing label used by IDM-VTON (utils_mask.label_map["hair"])
MIN_HAIR_SHARE = 0.002  # less hair than this (0.2 % of the photo): nothing to keep


def hair_map(parse: Image.Image) -> np.ndarray:
    """Boolean hair pixels of the parsing map (any size)."""
    return np.asarray(parse) == HAIR_LABEL


def mask_without_hair(mask: Image.Image, parse: Image.Image) -> Image.Image:
    """The repaint mask (white = repaint) with the hair taken out."""
    hair = hair_map(parse)
    if hair.mean() < MIN_HAIR_SHARE:
        return mask
    hair_img = Image.fromarray(hair.astype(np.uint8) * 255).resize(mask.size, Image.NEAREST)
    out = np.asarray(mask.convert("L")).copy()
    out[np.asarray(hair_img) > 127] = 0
    return Image.fromarray(out, mode="L")


def paste_hair_back(person: Image.Image, result: Image.Image, parse: Image.Image,
                    shrink_px: int = 5, soften_px: float = 2.0) -> Image.Image:
    """The result with the person's own hair pixels on top (same size as `person`)."""
    hair = hair_map(parse)
    result = result.convert("RGB").resize(person.size)
    if hair.mean() < MIN_HAIR_SHARE:
        return result
    alpha = Image.fromarray(hair.astype(np.uint8) * 255).resize(person.size, Image.NEAREST)
    if shrink_px > 1:
        alpha = alpha.filter(ImageFilter.MinFilter(shrink_px if shrink_px % 2 else shrink_px + 1))
    if soften_px > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(soften_px))
    return Image.composite(person.convert("RGB"), result, alpha)
