"""Clothing advice for a skin tone and undertone: the skin tone analyzer's result screen
(21 Nov 2026, the user's request: "analyze the skin tone of the user closely and suggest
them according to their things").

The colours are ranked with the SAME score the recommendations use
(shared/color_harmony.py: contrast with the skin, stylists' flattering / wash-out lists
per depth, the undertone nudge), so the advice never contradicts what the app then
recommends. The outfit ideas are written for Pakistani wardrobes.

Guidance gathered 21 Nov 2026 from stylist sources (SheKnows "How to dress for your skin
tone", Aje "What are my colours", MR PORTER "What colour clothes look best with dark skin",
Tamil Culture "The best colours for South Asian men", L'Oreal "How to determine
undertones"): deep skin carries white and jewel tones beautifully (strong contrast);
warm undertones suit earthy and golden shades and gold jewellery, cool undertones
blue-based jewel tones and silver; colours closest to the skin's own (beige, khaki, camel
on medium skin; brown on deep skin) blend in near the face. Sources disagree in places
(pastels, brown), so these are suggestions, never rules.
"""

from __future__ import annotations

from shared.color_harmony import _HEX, _skin_color_score, skin_bucket, undertone_key

# Spelling twins and near-duplicates kept out of the lists (one of each is enough).
_SKIP = {"gray", "rose pink", "off white", "denim", "bronze", "copper", "wine", "ruby"}
_GROUP = {"fair": "light", "light": "light", "medium": "medium", "tan": "medium", "brown": "deep", "deep": "deep"}

_WHITE = {  # which white
    "deep": "Crisp, bright white: the contrast glows on deep skin. An all-white suit is a classic for you.",
    ("light", "warm"): "Ivory or cream rather than stark white, which can look harsh on warm, light skin.",
    ("medium", "warm"): "Off-white, ivory or cream: softer than stark white on warm skin.",
    "cool": "Crisp white: it sharpens cool undertones.",
    "neutral": "Soft white or off-white both work.",
}
_METAL = {"warm": "Gold", "cool": "Silver", "neutral": "Gold and silver both"}

_IDEAS = {
    "deep": {
        "all": ["An all-white kurta shalwar or white lawn suit: the strong contrast looks striking on deep skin",
                "A plain suit with a jewel-tone dupatta (emerald, royal blue or magenta)"],
        "warm": ["Mustard, orange or golden yellow for mehndi and festive wear",
                 "Gold embroidery or gold jewellery"],
        "cool": ["Fuchsia, cobalt or emerald for weddings and formal events",
                 "Silver embroidery or silver jewellery"],
        "neutral": ["Emerald, royal blue or deep red for formal wear",
                    "Gold or silver details: both suit you"],
        "avoid": "Head-to-toe brown, camel or charcoal close to your own tone blends in: add white or a bright dupatta.",
    },
    "medium": {
        "all": ["An off-white or cream kurta with a coloured dupatta or waistcoat"],
        "warm": ["Maroon, rust or mustard for festive wear; olive or teal for every day",
                 "Gold embroidery, and earthy prints like ajrak or block prints"],
        "cool": ["Royal blue, plum or emerald for formal wear",
                 "A white kurta with a jewel-tone dupatta, silver details"],
        "neutral": ["Teal, maroon or emerald for formal wear",
                    "Both pastels and rich shades work: try dusty pink or jade"],
        "avoid": "Beige, khaki or camel very close to your skin tone can wash you out near the face.",
    },
    "light": {
        "all": ["Navy, emerald or burgundy give you contrast without being harsh"],
        "warm": ["Peach, coral, warm cream and olive; camel for western wear",
                 "Gold details and warm prints"],
        "cool": ["Soft pastels like lavender, mint or powder blue for day wear",
                 "Berry, plum and navy for evenings, silver details"],
        "neutral": ["Dusty pink, jade and soft white",
                    "Navy or burgundy for formal wear"],
        "avoid": "Very pale beige or nude head-to-toe can make light skin look washed out.",
    },
}


def _ranked(bucket: str, undertone: str | None) -> list[tuple[str, float]]:
    names = [n for n in _HEX if n not in _SKIP]
    scored = [(n, _skin_color_score(n, bucket, undertone)) for n in names]
    return sorted(scored, key=lambda t: (-t[1], t[0]))


def palette(skin_tone: str | None, undertone: str | None = None) -> dict | None:
    """Advice for a skin tone label (the app's swatches or the analyzer's bucket) and an
    undertone (warm / cool / neutral / None); None when the skin tone isn't known."""
    bucket = skin_bucket(skin_tone)
    if bucket is None:
        return None
    tone = undertone_key(undertone)
    group = _GROUP[bucket]
    ranked = _ranked(bucket, tone)
    best = [n for n, s in ranked if s >= 0.7][:8] or [n for n, _ in ranked[:6]]
    avoid = [n for n, s in reversed(ranked) if s <= 0.45][:5]
    ideas = _IDEAS[group]
    white = _WHITE["deep"] if group == "deep" else _WHITE.get((group, tone or ""), _WHITE.get(tone or "neutral"))
    depth_word = {"light": "Light", "medium": "Medium", "deep": "Deep"}[group]
    tone_word = f" with a {tone} undertone" if tone else ""
    summary = {
        "warm": "earthy, golden and rich colours flatter you most",
        "cool": "blue-based jewel tones and crisp shades flatter you most",
        "neutral": "you can wear both warm and cool shades",
        None: "answer two quick questions to find your undertone for sharper advice",
    }[tone]
    return {
        "skin_tone": (skin_tone or bucket).strip().title(),
        "bucket": bucket,
        "undertone": tone,
        "summary": f"{depth_word} skin{tone_word}: {summary}.",
        "best": [{"name": n, "hex": _HEX[n]} for n in best],
        "avoid": [{"name": n, "hex": _HEX[n]} for n in avoid],
        "white": white,
        "metal": _METAL.get(tone or "neutral"),
        "outfits": ideas["all"] + ideas[tone or "neutral"],
        "avoid_tip": ideas["avoid"],
    }
