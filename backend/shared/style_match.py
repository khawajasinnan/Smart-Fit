"""Does a garment match a style preference? Shared by the recommendation
ranker and the look score.

Profile styles are words like "ethnic", "formal", "streetwear"; product titles
rarely contain them ("Embroidered Kurta Pajama" is ethnic wear without saying
so), so each style has the garment words that mean it.
"""

from __future__ import annotations

import re

from shared.occasion import EASTERN_WORDS

_STYLE_WORDS: dict[str, re.Pattern[str]] = {
    "ethnic": EASTERN_WORDS,
    "eastern": EASTERN_WORDS,
    "traditional": EASTERN_WORDS,
    "formal": re.compile(r"\b(formal|suits?|blazers?|sherwanis?|prince coat|tuxedo|dress shirts?|"
                         r"waistcoats?|business|office|cufflinks?|trousers?)\b"),
    "casual": re.compile(r"\b(casual|t-?shirts?|tees?|jeans?|polos?|hoodies?|shorts|chinos?|joggers?|"
                         r"sweatshirts?|everyday)\b"),
    "streetwear": re.compile(r"\b(street|oversized|graphic|hoodies?|cargos?|joggers?|bomber|sweatshirts?|"
                             r"drop shoulder)\b"),
    "sporty": re.compile(r"\b(sports?|active|athleisure|track|gym|joggers?|dri-?fit|running)\b"),
    "embroidered": re.compile(r"\bembroider(y|ed)?\b"),
    "printed": re.compile(r"\b(printed|prints?|digital)\b"),
    "minimalist": re.compile(r"\b(plain|solid|basic|minimal|essential|classic)\b"),
    "classic": re.compile(r"\b(classic|timeless|plain|solid|oxford|button down)\b"),
    "trendy": re.compile(r"\b(trendy|oversized|co-?ord|crop(ped)?|new arrivals?|statement)\b"),
    "bold": re.compile(r"\b(bold|statement|bright|neon|sequin(ned)?|printed)\b"),
    "luxury": re.compile(r"\b(luxury|luxe|couture|premium|silk|velvet|chiffon|organza|festive)\b"),
}


def style_hit(text: str, styles: list[str] | None) -> str | None:
    """The first of the user's styles this garment matches, or None."""
    text = text.lower()
    for style in styles or []:
        if not isinstance(style, str) or not style.strip():
            continue
        s = style.lower().strip()
        pattern = _STYLE_WORDS.get(s)
        if re.search(rf"\b{re.escape(s)}\b", text) or (pattern is not None and pattern.search(text)):
            return style.strip()
    return None
