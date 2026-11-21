"""Traditional outfits of Pakistan's cultures, for men and women (21 Nov 2026).

The user asked that a profile's culture shows that culture's clothes (Punjabi:
kurta, tehmat/dhoti, turban ...) for every culture, Gilgit-Baltistan included.
Our 67 stores sell almost none of the regional pieces (checked 21 Nov 2026 in
25,286 products: 0 khussa, 0 Peshawari chappal, 0 Sindhi topi, 0 Balochi dress,
0 turban), so the user chose: an outfit guide (shown on Home, used by Zayn)
plus real products that match (kurtas, waistcoats, ajrak, rilli, chunri ...).

Sources (checked 21 Nov 2026): Wikipedia "Pakistani clothing", "Saraiki shalwar
suits", "Saraiki ajrak", "Culture of Gilgit-Baltistan", "Khyber Pakhtunkhwa
clothing"; Pamir Times "My cap, my pride: the women's caps of Gilgit-Baltistan";
Dawn (Saraiki Culture Day, 2024); WorldAtlas "Traditional Pakistani clothing".
The guide names pieces people really wear; it never claims one look is the only one.

`catalog_words`: words that find real products for that culture in our catalog
(product titles and categories). They are shared base garments plus the
culture's own prints and pieces, so a Punjabi user is shown kurtas and
phulkari, a Sindhi user ajrak and rilli, and so on.
"""

from __future__ import annotations

from typing import TypedDict


class Outfit(TypedDict):
    name: str
    pieces: list[str]
    when: str
    search: str  # what "Find on stores" searches for


class CultureLook(TypedDict):
    label: str
    region: str
    intro: str
    colours: list[str]
    men: list[Outfit]
    women: list[Outfit]
    catalog_words: dict[str, list[str]]  # "men" / "women" -> title words of real products


CULTURES: dict[str, CultureLook] = {
    "punjabi": {
        "label": "Punjabi",
        "region": "Punjab",
        "intro": "Bright, festive and proud: white or pastel kurtas, colourful pagg and phulkari, khussa on the feet.",
        "colours": ["white", "mustard", "orange", "green", "pink", "maroon"],
        "men": [
            {"name": "Mela look", "pieces": ["Kurta", "Tehmat (lacha / dhoti wrap)", "Pagg (turban)", "Khussa"],
             "when": "Melas, Basant, cultural days", "search": "white cotton kurta"},
            {"name": "Everyday Punjabi suit", "pieces": ["Kurta shalwar", "Waistcoat", "Khussa or Peshawari chappal"],
             "when": "Daily wear, Jummah", "search": "kurta shalwar"},
            {"name": "Wedding (shaadi) look", "pieces": ["Embroidered kurta", "Waistcoat", "Pagg / turla", "Gold khussa"],
             "when": "Mehndi, baraat", "search": "embroidered kurta waistcoat"},
        ],
        "women": [
            {"name": "Phulkari look", "pieces": ["Kurti", "Patiala shalwar", "Phulkari dupatta", "Paranda", "Khussa"],
             "when": "Melas, Basant, cultural days", "search": "embroidered kurti patiala"},
            {"name": "Everyday Punjabi suit", "pieces": ["Straight-cut kameez", "Shalwar", "Printed dupatta"],
             "when": "Daily wear", "search": "lawn shalwar kameez"},
            {"name": "Mehndi look", "pieces": ["Yellow or green kurta", "Gharara or Patiala", "Paranda", "Bangles"],
             "when": "Mehndi, dholki", "search": "mehndi yellow suit"},
        ],
        "catalog_words": {
            "men": ["kurta", "kameez shalwar", "shalwar kameez", "waistcoat", "khussa"],
            "women": ["phulkari", "patiala", "paranda", "kurti", "khussa", "shalwar kameez"],
        },
    },
    "sindhi": {
        "label": "Sindhi",
        "region": "Sindh",
        "intro": "Ajrak's deep indigo and crimson, mirror work (sheesha) and ralli patchwork.",
        "colours": ["indigo", "crimson", "maroon", "black", "white"],
        "men": [
            {"name": "Ajrak and topi", "pieces": ["White kurta shalwar", "Ajrak (shoulder shawl)", "Sindhi topi", "Khussa"],
             "when": "Sindhi Culture Day, weddings, guests", "search": "ajrak"},
            {"name": "Everyday Sindhi suit", "pieces": ["Kurta", "Wide Sindhi shalwar", "Ajrak-print waistcoat"],
             "when": "Daily wear", "search": "kurta shalwar"},
        ],
        "women": [
            {"name": "Cholo and suthan", "pieces": ["Cholo (mirror-work shirt)", "Suthan (shalwar)", "Ajrak dupatta"],
             "when": "Cultural days, weddings", "search": "mirror work kurta"},
            {"name": "Ajrak suit", "pieces": ["Ajrak-print kameez", "Plain shalwar", "Ajrak or ralli dupatta"],
             "when": "Daily wear, gatherings", "search": "ajrak print suit"},
            {"name": "Ralli look", "pieces": ["Ralli or rilli patchwork kurta", "Wide-leg shalwar", "Silver jewellery"],
             "when": "Casual and festive", "search": "rilli"},
        ],
        "catalog_words": {
            "men": ["ajrak", "sindhi", "kurta", "kameez shalwar", "shalwar kameez"],
            "women": ["ajrak", "mirror work", "sheesha", "ralli", "rilli", "sindhi"],
        },
    },
    "balochi": {
        "label": "Balochi",
        "region": "Balochistan",
        "intro": "Long, loose silhouettes, wide shalwars and hand embroidery (doch) in deep jewel colours.",
        "colours": ["maroon", "deep red", "emerald", "black", "white"],
        "men": [
            {"name": "Balochi suit", "pieces": ["Long loose kameez", "Very wide Balochi shalwar", "Pag (turban)", "Chappal"],
             "when": "Balochi Culture Day, gatherings", "search": "kameez shalwar"},
            {"name": "Formal Balochi look", "pieces": ["White kameez shalwar", "Waistcoat", "Embroidered cap or pag"],
             "when": "Weddings, Eid", "search": "white kameez shalwar waistcoat"},
        ],
        "women": [
            {"name": "Balochi doch dress", "pieces": ["Long embroidered frock (doch)", "Front pocket (pandol)",
                                                     "Wide shalwar", "Large dupatta"],
             "when": "Weddings, Eid, cultural days", "search": "embroidered long frock"},
            {"name": "Everyday Balochi suit", "pieces": ["Long kameez with embroidered yoke", "Wide shalwar", "Chadar"],
             "when": "Daily wear", "search": "embroidered kameez"},
        ],
        "catalog_words": {
            "men": ["kameez shalwar", "shalwar kameez", "waistcoat", "balochi"],
            "women": ["balochi", "mirror work", "embroidered frock", "frock"],
        },
    },
    "pathan": {
        "label": "Pashtun (Pathan)",
        "region": "Khyber Pakhtunkhwa",
        "intro": "Perahan tunban (Pathani suit), waistcoats, a pakol or Peshawari cap, Peshawari chappal; earthy tones.",
        "colours": ["white", "grey", "brown", "olive", "black", "navy"],
        "men": [
            {"name": "Pathani suit", "pieces": ["Perahan tunban (long kameez, wide shalwar)", "Waistcoat",
                                               "Peshawari chappal"],
             "when": "Daily wear, Jummah, Eid", "search": "kameez shalwar waistcoat"},
            {"name": "Winter look", "pieces": ["Kameez shalwar", "Patu (woollen shawl)", "Pakol (Chitrali cap)"],
             "when": "Winter, hill areas", "search": "shawl"},
        ],
        "women": [
            {"name": "Firaq partug", "pieces": ["Long embroidered frock (firaq)", "Wide shalwar (partug)", "Large chadar"],
             "when": "Weddings, Eid, cultural days", "search": "embroidered frock"},
            {"name": "Everyday Pashtun suit", "pieces": ["Long kameez", "Shalwar", "Chadar or large dupatta"],
             "when": "Daily wear", "search": "long kameez shalwar"},
        ],
        "catalog_words": {
            "men": ["pathani", "peshawari", "kameez shalwar", "shalwar kameez", "waistcoat", "shawl"],
            "women": ["frock", "chadar", "embroidered kameez", "peshawari"],
        },
    },
    "saraiki": {
        "label": "Saraiki",
        "region": "South Punjab (Multan, Bahawalpur, D.I. Khan)",
        "intro": "White Multani suits, Saraiki ajrak in dark blue, the patka turban and colourful chunri.",
        "colours": ["white", "dark blue", "red", "green", "mustard"],
        "men": [
            {"name": "Multani suit", "pieces": ["White kurta shalwar", "Saraiki ajrak (shoulder shawl)", "Patka (turban)",
                                               "Multani khussa"],
             "when": "Saraiki Culture Day, melas", "search": "white kurta shalwar"},
            {"name": "Everyday Saraiki look", "pieces": ["Kurta", "Tehmat or shalwar", "Embroidered shoulder scarf"],
             "when": "Daily wear", "search": "kurta"},
        ],
        "women": [
            {"name": "Chunri suit", "pieces": ["Shalwar kameez", "Chunri (tie-dye) dupatta", "Multani khussa"],
             "when": "Weddings, gatherings", "search": "chunri"},
            {"name": "Ajrak look", "pieces": ["Plain kameez", "Shalwar", "Saraiki ajrak shawl"],
             "when": "Cultural days", "search": "ajrak"},
            {"name": "Ghagra look", "pieces": ["Ghagra", "Short kurti", "Bochan or chunni (head scarf)"],
             "when": "Weddings and parties", "search": "ghagra"},
        ],
        "catalog_words": {
            "men": ["kurta", "ajrak", "multani", "kameez shalwar", "shalwar kameez"],
            "women": ["chunri", "chunari", "bandhani", "ajrak", "multani", "ghagra"],
        },
    },
    "gilgiti": {
        "label": "Gilgit-Baltistan",
        "region": "Gilgit-Baltistan (Gilgit, Hunza, Skardu)",
        "intro": "Warm wool and fine embroidery: the choga robe, the khoi cap, and women's embroidered caps with silsila.",
        "colours": ["cream", "brown", "white", "red", "green", "multicolour"],
        "men": [
            {"name": "Choga and khoi", "pieces": ["Shalwar kameez", "Choga (woollen robe)", "Khoi / Gilgiti wool cap"],
             "when": "Festivals, guests, winter", "search": "wool waistcoat"},
            {"name": "Everyday mountain look", "pieces": ["Kameez shalwar", "Woollen waistcoat", "Shawl"],
             "when": "Daily wear, cold weather", "search": "waistcoat"},
        ],
        "women": [
            {"name": "Embroidered cap look", "pieces": ["Colourful frock or kameez", "Loose shalwar",
                                                       "Embroidered Iraghi (khoi) cap with silsila", "Long dupatta"],
             "when": "Festivals, weddings", "search": "embroidered frock"},
            {"name": "Winter look", "pieces": ["Kameez shalwar", "Wool shawl", "Embroidered cap"],
             "when": "Winter, daily wear", "search": "wool shawl"},
        ],
        "catalog_words": {
            "men": ["waistcoat", "shawl", "wool", "kameez shalwar", "shalwar kameez"],
            "women": ["frock", "shawl", "embroidered", "wool"],
        },
    },
}

# What people write in a profile / chat -> the guide's key.
_ALIASES = {
    "punjabi": "punjabi", "punjab": "punjabi",
    "sindhi": "sindhi", "sindh": "sindhi",
    "balochi": "balochi", "baloch": "balochi", "baluchi": "balochi", "balochistan": "balochi",
    "pathan": "pathan", "pashtun": "pathan", "pakhtun": "pathan", "pukhtun": "pathan", "pashto": "pathan",
    "saraiki": "saraiki", "siraiki": "saraiki", "seraiki": "saraiki", "multani": "saraiki",
    "gilgiti": "gilgiti", "gilgit": "gilgiti", "gilgit-baltistan": "gilgiti", "gilgit baltistan": "gilgiti",
    "balti": "gilgiti", "hunza": "gilgiti", "hunzai": "gilgiti", "shina": "gilgiti",
}


def culture_key(name: str | None) -> str | None:
    """"Pashtun" / "Pathan" -> "pathan"; None when it isn't one of the guide's cultures."""
    text = (name or "").strip().lower()
    if not text:
        return None
    if text in _ALIASES:
        return _ALIASES[text]
    for alias, key in _ALIASES.items():
        if alias in text:
            return key
    return None


def culture_guide(name: str | None, gender: str | None) -> dict | None:
    """The guide for one culture, the outfits for the user's gender first (both when unknown)."""
    key = culture_key(name)
    if key is None:
        return None
    c = CULTURES[key]
    g = (gender or "").strip().lower()
    side = "men" if g in {"male", "m", "man", "men"} else "women" if g in {"female", "f", "woman", "women"} else None
    outfits = c[side] if side else c["men"] + c["women"]
    return {"key": key, "label": c["label"], "region": c["region"], "intro": c["intro"], "colours": c["colours"],
            "gender": side, "outfits": outfits}


def culture_words(name: str | None) -> set[str]:
    """Words that mark a real product as this culture's (both genders: the search already
    keeps to the user's gender)."""
    key = culture_key(name)
    if key is None:
        return set()
    words = CULTURES[key]["catalog_words"]
    return {w for side in ("men", "women") for w in words[side]}


def prompt_summary() -> str:
    """One line per culture and gender, for Zayn's system prompt."""
    lines = []
    for c in CULTURES.values():
        for side in ("men", "women"):
            looks = "; ".join(f"{o['name']}: {', '.join(o['pieces'])}" for o in c[side])
            lines.append(f"- {c['label'].upper()} {side}: {looks}. Colours: {', '.join(c['colours'])}.")
    return "\n".join(lines)
