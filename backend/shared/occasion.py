"""Does a garment suit an occasion? Shared by the recommendation ranker and the
look score so both judge "right for mehndi" the same way."""

from __future__ import annotations

import re

from shared.taxonomy import EVENT_GARMENTS

EASTERN_WORDS = re.compile(
    r"\b(kurtas?|kurtis?|kameez|shalwar|salwar|lawn|khaddar|unstitched|[23] ?-?(pc|piece)|frocks?|lehe?ngas?|"
    r"anarkalis?|ghararas?|shararas?|sherwanis?|waistcoats?|dupattas?|eastern|ethnic|pret)\b"
)
WESTERN_WORDS = re.compile(
    r"\b(jeans?|denims?|tees?|t-?shirts?|polos?|hoodies?|sweatshirts?|jackets?|blazers?|chinos?|joggers?|"
    r"skirts?|shorts|tops?|cardigans?|western)\b"
)

EASTERN_EVENTS = {"mehndi", "mayun", "nikah", "baraat", "eid", "friday", "funeral", "wedding"}
WESTERN_EVENTS = {"office", "casual", "party", "date", "interview", "walima"}


def find_occasion(text: str) -> str | None:
    text = text.lower()
    for event in EVENT_GARMENTS:
        if re.search(rf"\b{event}\b", text):
            return event
    return None


def _words(pattern: str) -> re.Pattern[str]:
    return re.compile(rf"\b({pattern})\b")


_SPORTY = r"hoodies?|sweatshirts?|joggers?|tracksuits?|trousers? jogger|shorts|graphic|gym|sports?|athletic|crop"
_FESTIVE_BRIDAL = r"bridal|bride|dulhan|lehe?ngas?|sherwanis?|gowns?|tuxedos?"
_SPARKLE = r"sequins?|sequinn?ed|glitter|shimmer|metallic|embellished|party|neon|gota|mirror work"
_LOUD_COLOURS = r"red|maroon|pink|fuchsia|magenta|yellow|mustard|orange|neon|gold|golden"

# Wrong for the occasion even when the garment family matches (hoodie at the
# office, sequins at a funeral, bridal wear on a casual day): scored 0.
CLASHES: dict[str, re.Pattern[str]] = {
    "office": _words(_SPORTY + r"|" + _FESTIVE_BRIDAL + r"|" + _SPARKLE),
    "interview": _words(_SPORTY + r"|" + _FESTIVE_BRIDAL + r"|" + _SPARKLE),
    "nikah": _words(_SPORTY),
    "baraat": _words(_SPORTY),
    "walima": _words(_SPORTY),
    "wedding": _words(_SPORTY),
    "mehndi": _words(_SPORTY),
    "eid": _words(r"joggers?|tracksuits?|gym|shorts"),
    "friday": _words(r"shorts|gym|crop|" + _SPARKLE),
    "funeral": _words(_SPARKLE + r"|" + _FESTIVE_BRIDAL + r"|" + _LOUD_COLOURS + r"|graphic|crop|shorts"),
    "casual": _words(_FESTIVE_BRIDAL),
}

# Also right for the occasion (the garment lists in taxonomy.EVENT_GARMENTS are
# mostly menswear): scored 1.
ALSO_RIGHT: dict[str, re.Pattern[str]] = {
    "casual": _words(r"t-?shirts?|tees?|jeans|denims?|hoodies?|sweatshirts?|polos?|chinos?|joggers?|casual|"
                     r"kurtis?|lawn|co-?ords?|tops?"),
    "office": _words(r"formal|dress shirts?|trousers?|blazers?|chinos?|cigarette pants?|straight pants?|"
                     r"waistcoats?|cotton kurtas?|kurtis?|2 ?-?(pc|piece) (stitched|pret)"),
    "interview": _words(r"formal|suits?|blazers?|dress shirts?|trousers?"),
    "mehndi": _words(r"mehndi|mayun|yellow|mustard|haldi|green|orange|embroidered"),
    "mayun": _words(r"mayun|yellow|mustard|haldi|green"),
    "nikah": _words(r"nikah|sherwanis?|prince coats?|waistcoats?|ivory|off ?-?white|formal|embroidered|chiffon|organza"),
    "baraat": _words(r"sherwanis?|prince coats?|lehe?ngas?|bridal|formal|embroidered|velvet"),
    "walima": _words(r"suits?|blazers?|formal|gowns?|maxis?|chiffon|organza|embroidered"),
    "wedding": _words(r"formal|embroidered|chiffon|organza|velvet|waistcoats?|sherwanis?|suits?"),
    "eid": _words(r"kurtas?|kurtis?|shalwar|kameez|lawn|embroidered|festive|eid|[23] ?-?(pc|piece)"),
    "party": _words(r"party|blazers?|dress(es)?|maxis?|gowns?|formal|velvet|sequin"),
    "date": _words(r"casual shirts?|chinos?|blazers?|dress(es)?|tops?|polos?"),
    "friday": _words(r"kurtas?|shalwar|kameez|white"),
    "funeral": _words(r"white|black|grey|gray|beige|cream|off ?-?white|plain"),
}


def occasion_match(text: str, occasion: str | None) -> float:
    """1 = made for it (named, one of its usual garments or colours), 0.5 =
    the right family (eastern for mehndi, western for office ...), 0 = neither
    or a clash (a hoodie at the office, sequins at a funeral). 0.5 when there
    is no occasion to judge.

    `text` is everything known about the product (title, tags, category,
    colours), lower or mixed case."""
    if not occasion:
        return 0.5
    occasion = occasion.lower().strip()
    text = text.lower()
    clash = CLASHES.get(occasion)
    if clash is not None and clash.search(text):
        return 0.0
    if re.search(rf"\b{re.escape(occasion)}\b", text):
        return 1.0
    if any(g in text for g in EVENT_GARMENTS.get(occasion, [])):
        return 1.0
    family = (occasion in EASTERN_EVENTS and EASTERN_WORDS.search(text)) or (
        occasion in WESTERN_EVENTS and WESTERN_WORDS.search(text))
    right = ALSO_RIGHT.get(occasion)
    if right is not None and right.search(text):
        # a colour/fabric hint alone (yellow, embroidered) needs the right family too
        return 1.0 if family or occasion in ("casual", "office", "interview", "party", "date") else 0.5
    if family:
        return 0.5
    return 0.0


def occasion_clash(text: str, occasion: str | None) -> str | None:
    """The word that makes a product wrong for the occasion ("hoodie", "sequin"), or None."""
    if not occasion:
        return None
    clash = CLASHES.get(occasion.lower().strip())
    m = clash.search(text.lower()) if clash is not None else None
    return m.group(0) if m else None


def usual_garments(occasion: str | None) -> list[str]:
    return list(EVENT_GARMENTS.get((occasion or "").lower().strip(), []))
