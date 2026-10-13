"""Build search context from user profile + chat messages.

Includes a comprehensive taxonomy of Pakistani clothing for both men and women,
strict category mapping, and multi-word garment preservation.
"""

import re

from models.schemas import UserProfileInput
from services.brands import PAKISTANI_BRANDS, normalize_gender

# Garments that are exclusively for one gender in Pakistani fashion context
GENDER_EXCLUSIVE_GARMENTS = {
    "male": {
        "pent coat", "pentcoat", "two-piece-suit", "three-piece-suit",
        "sherwani", "prince coat", "prince-coat", "kurta pajama", "kurta-pajama",
        "groom", "groom-suit",
    },
    "female": {
        "kurti", "lawn suit", "lawn-suit", "gharara", "sharara",
        "lehenga", "bridal", "abaya", "anarkali", "saree", "sari",
        "frock", "maxi dress", "maxi-dress",
    },
}

# Female alternatives when a female user asks for male garments
FEMALE_ALTERNATIVES = {
    "pent coat": ["trouser suit", "co-ord set", "formal pret", "party wear"],
    "two-piece-suit": ["trouser suit", "co-ord set", "formal pret", "party wear"],
    "three-piece-suit": ["trouser suit", "co-ord set", "formal pret", "luxury pret"],
    "sherwani": ["bridal lehenga", "formal pret", "party wear", "luxury pret"],
    "prince coat": ["formal pret", "luxury pret", "party wear"],
    "kurta pajama": ["kurti", "lawn suit", "pret", "casual eastern"],
}

# Male alternatives when a male user asks for female garments
MALE_ALTERNATIVES = {
    "kurti": ["kurta pajama", "shalwar kameez", "casual shirt"],
    "lawn suit": ["shalwar kameez", "kurta pajama"],
    "gharara": ["sherwani", "prince coat", "waistcoat"],
    "sharara": ["sherwani", "prince coat", "waistcoat"],
    "lehenga": ["sherwani", "prince coat", "pent coat"],
    "bridal": ["sherwani", "groom suit", "prince coat"],
    "abaya": ["kurta pajama", "shalwar kameez"],
}


def gender_garment_conflict(gender: str, garment: str) -> dict | None:
    """Check if a garment conflicts with the user's gender.
    
    Returns None if no conflict, or a dict with:
      - conflict: True
      - message: user-friendly warning
      - alternatives: list of suggested alternatives
    """
    gender = gender.lower().strip()
    garment_lower = garment.lower().strip()
    
    if gender == "female":
        male_garments = GENDER_EXCLUSIVE_GARMENTS.get("male", set())
        if garment_lower in male_garments:
            alts = FEMALE_ALTERNATIVES.get(garment_lower, ["trouser suit", "party wear", "formal pret"])
            return {
                "conflict": True,
                "message": f"You've selected Female in your profile, and '{garment}' is typically a men's outfit in Pakistani fashion. Would you like to see women's alternatives instead?",
                "alternatives": alts,
            }
    elif gender == "male":
        female_garments = GENDER_EXCLUSIVE_GARMENTS.get("female", set())
        if garment_lower in female_garments:
            alts = MALE_ALTERNATIVES.get(garment_lower, ["shalwar kameez", "pent coat", "kurta pajama"])
            return {
                "conflict": True,
                "message": f"You've selected Male in your profile, and '{garment}' is typically a women's outfit. Would you like to see men's alternatives instead?",
                "alternatives": alts,
            }
    return None

# ──────────────────────────────────────────────────────────────────────────────
# COMPREHENSIVE PAKISTANI OUTFIT TAXONOMY
# Maps user-friendly terms → canonical category key used for strict filtering.
# ──────────────────────────────────────────────────────────────────────────────

# fmt: off
CATEGORY_MAP: dict[str, str] = {
    # ── MEN — Eastern / Traditional ──
    "shalwar kameez":         "shalwar-kameez",
    "shalwar qameez":         "shalwar-kameez",
    "salwar kameez":          "shalwar-kameez",
    "salwar qameez":          "shalwar-kameez",
    "kameez shalwar":         "shalwar-kameez",
    "qameez shalwar":         "shalwar-kameez",
    "kurta shalwar":          "kurta-pajama",
    "kurta pajama":           "kurta-pajama",
    "kurta trouser":          "kurta-pajama",
    "kurta and pajama":       "kurta-pajama",
    "kurta and trouser":      "kurta-pajama",
    "kurta":                  "kurta",
    "waist coat":             "waistcoat",
    "waistcoat":              "waistcoat",
    "waist coat set":         "waistcoat",
    "waistcoat set":          "waistcoat",
    "kurta waist coat":       "waistcoat",
    "kurta waistcoat":        "waistcoat",
    "kurta waist coat set":   "waistcoat",
    "kurta waistcoat set":    "waistcoat",
    "sherwani":               "sherwani",
    "achkan":                 "sherwani",
    "prince coat":            "prince-coat",
    "achkan coat":            "prince-coat",
    "nehru jacket":           "prince-coat",

    # ── MEN — Western / Formal ──
    "pent coat":              "two-piece-suit",
    "pent coat two piece":    "two-piece-suit",
    "two piece suit":         "two-piece-suit",
    "two piece pent coat":    "two-piece-suit",
    "2 piece suit":           "two-piece-suit",
    "suit":                   "two-piece-suit",
    "formal suit":            "two-piece-suit",
    "three piece suit":       "three-piece-suit",
    "3 piece suit":           "three-piece-suit",
    "pent coat three piece":  "three-piece-suit",
    "three piece pent coat":  "three-piece-suit",
    "3 piece pent coat":      "three-piece-suit",
    "pent coat 3 piece":      "three-piece-suit",
    "trouser and shirt":      "casual-trouser-shirt",
    "shirt and trouser":      "casual-trouser-shirt",
    "trouser shirt":          "casual-trouser-shirt",
    "shirt trouser":          "casual-trouser-shirt",
    "blazer":                 "blazer",
    "sport coat":             "blazer",
    "blazer trouser":         "blazer",
    "formal shirt":           "formal-shirt",
    "dress shirt":            "formal-shirt",
    "casual shirt":           "casual-shirt",
    "shirt":                  "casual-shirt",
    "polo":                   "polo-shirt",
    "polo shirt":             "polo-shirt",
    "drop shoulder t-shirt":   "t-shirt",
    "drop shoulder t-shirts":  "t-shirt",
    "drop shoulder tshirt":    "t-shirt",
    "drop shoulder tshirts":   "t-shirt",
    "drop shoulder tee":       "t-shirt",
    "t-shirt":                "t-shirt",
    "t-shirts":               "t-shirt",
    "tshirt":                 "t-shirt",
    "tshirts":                "t-shirt",
    "tee":                    "t-shirt",
    "tee shirt":              "t-shirt",
    "tee shirts":             "t-shirt",
    "t shirt":                "t-shirt",
    "t shirts":               "t-shirt",
    "trouser":                "trouser",
    "trousers":               "trouser",
    "pant":                   "trouser",
    "pants":                  "trouser",
    "chinos":                 "chinos",
    "jeans":                  "jeans",
    "denim":                  "jeans",
    "jacket":                 "jacket",
    "bomber jacket":          "jacket",
    "hoodie":                 "hoodie",
    "sweater":                "sweater",
    "pullover":               "sweater",
    "cardigan":               "sweater",
    "coat":                   "coat",
    "overcoat":               "coat",
    "parka":                  "coat",
    "shorts":                 "shorts",

    # ── WOMEN — Eastern / Traditional ──
    "kurti":                  "kurti",
    "kurtis":                 "kurti",
    "ladies kurti":           "kurti",
    "women kurta":            "kurti",
    "lawn suit":              "lawn-suit",
    "lawn":                   "lawn-suit",
    "unstitched":             "unstitched",
    "unstitched suit":        "unstitched",
    "unstitched lawn":        "unstitched",
    "two piece suit ladies":  "ladies-two-piece",
    "ladies 2 piece":         "ladies-two-piece",
    "three piece lawn":       "ladies-three-piece",
    "3 piece suit ladies":    "ladies-three-piece",
    "ladies three piece":     "ladies-three-piece",
    "pret":                   "pret",
    "ready to wear":          "pret",
    "stitched":               "pret",
    "formal wear":            "ladies-formal",
    "party wear":             "ladies-formal",
    "luxury pret":            "ladies-formal",
    "bridal":                 "bridal",
    "bridal dress":           "bridal",
    "wedding dress":          "bridal",
    "lehenga":                "bridal",
    "gharara":                "gharara",
    "sharara":                "sharara",
    "anarkali":               "anarkali",
    "frock":                  "frock",
    "maxi":                   "maxi-dress",
    "maxi dress":             "maxi-dress",
    "abaya":                  "abaya",
    "hijab":                  "hijab",
    "dupatta":                "dupatta",
    "shawl":                  "shawl",
    "stole":                  "shawl",
    "pashmina":               "shawl",
    "trouser suit":           "trouser-suit",
    "co-ord set":             "coord-set",
    "coord set":              "coord-set",

    # ── UNISEX / Accessories ──
    "khussa":                 "khussa",
    "chappal":                "chappal",
    "peshawari chappal":      "chappal",
    "sandal":                 "sandal",
    "loafer":                 "loafer",
    "sneaker":                "sneaker",
    "sneakers":               "sneaker",
    "perfume":                "perfume",
    "fragrance":              "perfume",
    "watch":                  "watch",
    "cap":                    "cap",
    "topi":                   "cap",
    "prayer cap":             "cap",
}
# fmt: on

# Reverse lookup: canonical category → set of acceptable product-title keywords
CATEGORY_KEYWORDS: dict[str, set[str]] = {
    "shalwar-kameez": {"shalwar", "salwar", "kameez", "qameez"},
    "kurta":          {"kurta", "kurta pajama", "kurta trouser", "kurta shalwar"},
    "kurta-pajama":   {"kurta", "pajama", "pajamas", "shalwar", "salwar", "trouser"},
    "casual-trouser-shirt": {"trouser", "shirt", "pant", "casual", "night suit", "nightwear", "t-shirt"},
    "waistcoat":      {"waistcoat", "vest", "kurta waistcoat"},
    "sherwani":       {"sherwani", "achkan", "groom"},
    "prince-coat":    {"prince coat", "achkan", "nehru", "bandhgala"},
    "two-piece-suit": {"pent coat", "pentcoat", "two piece", "2 piece", "2-piece", "blazer trouser", "blazer pant", "formal suit", "pent-coat", "coat pant", "coat trouser", "suit", "suits", "tuxedo", "tuxedos"},
    "three-piece-suit": {"three piece", "3 piece", "three-piece", "3-piece", "vest suit", "suit waistcoat", "coat pant waistcoat"},
    "blazer":         {"blazer", "sport coat", "sports coat"},
    "formal-shirt":   {"formal shirt", "dress shirt"},
    "casual-shirt":   {"casual shirt", "button down", "oxford", "button up"},
    "polo-shirt":     {"polo"},
    "t-shirt":        {"t-shirt", "t-shirts", "tee", "tee shirt", "tshirt", "tshirts", "t shirt", "drop shoulder"},
    "trouser":        {"trouser", "pant", "dress pant", "formal pant"},
    "chinos":         {"chino", "chinos"},
    "jeans":          {"jean", "jeans", "denim"},
    "jacket":         {"jacket", "bomber", "windbreaker"},
    "hoodie":         {"hoodie", "hoody"},
    "sweater":        {"sweater", "pullover", "cardigan", "knitwear"},
    "coat":           {"coat", "overcoat", "trench", "parka"},
    "shorts":         {"shorts", "short"},
    "kurti":          {"kurti", "kurtis", "women kurta", "ladies kurta"},
    "lawn-suit":      {"lawn", "lawn suit"},
    "unstitched":     {"unstitched", "fabric"},
    "ladies-two-piece":    {"two piece", "2 piece"},
    "ladies-three-piece":  {"three piece", "3 piece"},
    "pret":           {"pret", "ready to wear", "stitched", "rtw"},
    "ladies-formal":  {"formal", "party wear", "luxury pret", "evening"},
    "bridal":         {"bridal", "wedding", "bride", "dulhan", "lehenga"},
    "gharara":        {"gharara"},
    "sharara":        {"sharara"},
    "anarkali":       {"anarkali"},
    "frock":          {"frock"},
    "maxi-dress":     {"maxi", "maxi dress", "gown"},
    "abaya":          {"abaya"},
    "hijab":          {"hijab"},
    "dupatta":        {"dupatta", "chunri"},
    "shawl":          {"shawl", "pashmina", "stole"},
    "trouser-suit":   {"trouser suit", "pant suit"},
    "coord-set":      {"co-ord", "coord", "matching set"},
    "khussa":         {"khussa", "mojri"},
    "chappal":        {"chappal", "peshawari"},
    "sandal":         {"sandal"},
    "loafer":         {"loafer"},
    "sneaker":        {"sneaker"},
    "perfume":        {"perfume", "fragrance", "attar"},
    "watch":          {"watch"},
    "cap":            {"cap", "topi", "prayer cap"},
}

# Categories that should NEVER co-appear in results.
# When user asks for category X, products matching any category in set Y are BLOCKED.
CATEGORY_CONFLICTS: dict[str, set[str]] = {
    # Eastern ↔ Western conflicts
    "two-piece-suit": {"shalwar-kameez", "kurta", "kurti", "t-shirt", "casual-shirt", "hoodie", "waistcoat", "sherwani", "kurta-pajama"},
    "three-piece-suit": {"shalwar-kameez", "kurta", "kurti", "t-shirt", "casual-shirt", "hoodie", "kurta-pajama"},
    "shalwar-kameez": {"two-piece-suit", "three-piece-suit", "blazer", "jeans", "t-shirt", "chinos", "casual-trouser-shirt"},
    "kurta":          {"two-piece-suit", "three-piece-suit", "blazer", "jeans", "t-shirt", "chinos", "hoodie", "casual-trouser-shirt"},
    "kurti":          {"two-piece-suit", "blazer", "jeans", "shalwar-kameez"},
    "blazer":         {"shalwar-kameez", "kurta", "kurti", "hoodie", "t-shirt"},
    "sherwani":       {"casual-shirt", "t-shirt", "jeans", "blazer", "hoodie", "two-piece-suit"},
    "prince-coat":    {"casual-shirt", "t-shirt", "jeans", "hoodie", "two-piece-suit"},
    # Western standalone items — block eastern sets
    "trouser":        {"kurta", "shalwar-kameez", "waistcoat", "sherwani", "kurti"},
    "chinos":         {"kurta", "shalwar-kameez", "waistcoat", "sherwani", "kurti"},
    "jeans":          {"kurta", "shalwar-kameez", "waistcoat", "sherwani", "kurti"},
    "t-shirt":        {"kurta", "shalwar-kameez", "formal-shirt", "sherwani", "kurti"},
    "casual-shirt":   {"kurta", "shalwar-kameez", "sherwani", "kurti", "waistcoat"},
    "polo-shirt":     {"kurta", "shalwar-kameez", "sherwani"},
    "jacket":         {"kurta", "shalwar-kameez", "sherwani"},
    "hoodie":         {"kurta", "shalwar-kameez", "sherwani", "blazer", "two-piece-suit"},
    "sweater":        {"kurta", "shalwar-kameez", "sherwani"},
    "shorts":         {"kurta", "shalwar-kameez", "sherwani", "trouser"},
    # Accessories shouldn't mix with clothing
    "waistcoat":      {"jeans", "t-shirt", "hoodie", "shorts", "two-piece-suit", "three-piece-suit", "blazer"},
}


# ── Occasion → default garments ──
EVENT_GARMENTS: dict[str, list[str]] = {
    "mehndi":   ["embroidered kurta", "waistcoat", "shalwar kameez"],
    "mayun":    ["yellow kurta", "shalwar kameez"],
    "nikah":    ["white kurta", "waistcoat", "sherwani"],
    "baraat":   ["sherwani", "prince coat", "two-piece-suit", "pent coat",],
    "walima":   ["suit", "blazer", "waistcoat", "formal"],
    "wedding":  ["sherwani", "waistcoat", "suit", "prince coat"],
    "eid":      ["kurta", "shalwar kameez", "waistcoat"],
    "office":   ["formal shirt", "trouser", "blazer"],
    "casual":   ["t-shirt", "jeans", "casual shirt"],
    "party":    ["blazer", "formal shirt", "suit"],
    "date":     ["casual shirt", "chinos", "blazer"],
    "friday":   ["kurta", "shalwar kameez"],
    "funeral":  ["white shalwar kameez", "white kurta"],
    "interview": ["suit", "formal shirt", "blazer"],
}

COLOR_KEYWORDS = {
    "black", "white", "navy", "blue", "red", "green", "beige", "cream",
    "brown", "maroon", "pink", "purple", "grey", "gray", "olive", "mustard",
    "teal", "gold", "silver", "peach", "coral", "burgundy", "emerald",
    "charcoal", "sky blue", "royal blue", "off white", "ivory", "rust",
    "lavender", "mint", "sage", "plum", "copper", "bronze", "turquoise",
    "magenta", "yellow", "orange", "khaki", "tan", "wine", "pastel",
}

# ── Ethnicity → cultural outfit keywords ──
ETHNICITY_KEYWORDS: dict[str, set[str]] = {
    "punjabi": {"phulkari", "punjabi jutti", "patiala", "paranda", "phulkari dupatta"},
    "sindhi": {"ajrak", "sindhi cap", "sindhi topi", "mirror work", "sheesha", "ralli"},
    "balochi": {"balochi", "balochi dress", "balochi embroidery", "mirror work", "balochi chappal"},
    "pathan": {"pathani", "peshawari chappal", "pakol", "chitrali", "peshawari"},
    "saraiki": {"chunri", "bandhani", "saraiki", "multani"},
}

# Multi-word garment phrases to detect before splitting into tokens
_MULTI_WORD_GARMENTS = sorted(CATEGORY_MAP.keys(), key=len, reverse=True)

BRAND_ALIASES: dict[str, set[str]] = {
    brand.name: {brand.name.lower(), brand.base_url.replace("https://", "").replace("www.", "").split(".")[0].lower()}
    for brand in PAKISTANI_BRANDS
}
BRAND_ALIASES.update(
    {
        "Junaid Jamshed": {"junaid jamshed", "j.", "j ", "junaid", "jj"},
        "Ideas (Gul Ahmed)": {"ideas", "gul ahmed", "gulahmed"},
        "Maria.B": {"maria b", "maria.b", "mariab"},
        "Bonanza Satrangi": {"bonanza", "satrangi", "bonanza satrangi"},
    }
)


def build_search_context(
    profile: UserProfileInput,
    user_message: str,
    assistant_message: str,
    chat_context: str,
    dynamic_prefs: dict | None = None,
) -> dict:
    """Build a search context dict from profile + chat messages."""
    dynamic_prefs = dynamic_prefs or {}
    dynamic_colors_provided = "colors" in dynamic_prefs
    dynamic_text = _dynamic_prefs_text(dynamic_prefs)
    current_request_text = " ".join(
        filter(
            None,
            [
                user_message,
                dynamic_text,
                assistant_message,
            ],
        )
    ).lower()
    chat_combined = " ".join(
        filter(
            None,
            [
                user_message,
                assistant_message,
                chat_context,
            ],
        )
    ).lower()
    profile_combined = " ".join(
        filter(
            None,
            [
                " ".join(profile.style_preferences),
                " ".join(profile.preferred_colors),
                " ".join(profile.occasions),
                profile.skin_tone or "",
                profile.body_type or "",
            ],
        )
    ).lower()
    combined = f"{chat_combined} {profile_combined}".strip()
    requested_brands = _extract_brands(current_request_text)
    construction = _extract_construction(current_request_text)

    # ── Detect garment with strict priority ─────────────────────────────
    # The current user message is the source of truth.  Older chat context,
    # profile defaults, or a bad AI trigger must not override "pent coat" with
    # "shalwar kameez" (or the reverse).
    exact_category: str | None = None
    detected_garment: str | None = None
    dynamic_garment = str(dynamic_prefs.get("garment") or "").strip()
    if dynamic_garment:
        detected = _detect_garment(dynamic_garment)
        if detected:
            detected_garment, exact_category = detected

    for source_text in (user_message, dynamic_text, assistant_message, chat_context, profile_combined):
        if exact_category:
            break
        detected = _detect_garment(source_text)
        if detected:
            detected_garment, exact_category = detected
            break

    outfit_context = _extract_outfit_context(current_request_text, exact_category)
    if not outfit_context:
        outfit_context = _extract_outfit_context(chat_combined, exact_category)
    if outfit_context == "shalwar-kameez-waistcoat":
        exact_category = "waistcoat"
        detected_garment = "waistcoat for shalwar kameez"

    # ── Also tolerate canonical category keys (e.g. "two-piece-suit") that
    # may be emitted by the AI or other producers. Accept both hyphenated and
    # space-separated forms to be more robust.
    if not exact_category:
        for source_text in (user_message, dynamic_text, assistant_message, chat_context, profile_combined):
            normalized_source = source_text.lower()
            for canonical in set(CATEGORY_MAP.values()):
                if (
                    canonical not in normalized_source
                    and canonical.replace("-", " ") not in normalized_source
                ):
                    continue
                exact_category = canonical
                # present a human-friendly detected_garment where possible
                detected_garment = canonical.replace("-", " ")
                break
            if exact_category:
                break

    # ── Tokenize remaining text ──
    tokens = set(re.findall(r"[a-z][a-z-]{2,}", combined))

    # ── Colors ──
    # Colors directly mentioned in chat are hard requirements for this search.
    # Profile colors remain soft preferences only.
    requested_colors = _normalize_dynamic_colors(dynamic_prefs.get("colors"))
    for color in _extract_colors(current_request_text):
        if color not in requested_colors:
            requested_colors.append(color)
    colors: list[str] = requested_colors[:]
    for c in _extract_colors(profile_combined):
        if c not in colors:
            colors.append(c)
    for c in profile.preferred_colors:
        normalized = c.lower().strip()
        if normalized and normalized not in colors:
            colors.append(normalized)

    # ── Gender ──
    gender = normalize_gender(profile.gender)

    # ── Build search query ──
    if detected_garment:
        query_parts = [detected_garment]
    else:
        # Fallback: look for single-word garments in tokens
        single_word_garments = {k for k in CATEGORY_MAP if " " not in k}
        found = sorted(tokens & single_word_garments)
        if found:
            best = found[0]
            exact_category = CATEGORY_MAP[best]
            detected_garment = best
            query_parts = [best]
        else:
            query_parts = _default_garments(gender, profile)

    # Prepend color to query
    query_colors = requested_colors if dynamic_colors_provided else (requested_colors or colors)
    if query_colors:
        query_parts = [f"{query_colors[0]} {query_parts[0]}"] + query_parts[1:]

    search_query = " ".join(query_parts[:3]).strip()

    # ── Budget ──
    invalid_budget = _contains_negative_budget(current_request_text)
    budget_min = _positive_int_or_none(dynamic_prefs.get("budget_min"))
    budget_max = _positive_int_or_none(dynamic_prefs.get("budget_max"))
    if dynamic_prefs.get("budget_min") is not None and budget_min is None:
        invalid_budget = True
    if dynamic_prefs.get("budget_max") is not None and budget_max is None:
        invalid_budget = True
    if budget_min is None and budget_max is None:
        budget_min, budget_max = _extract_budget(current_request_text)
    if budget_min is None and budget_max is None:
        budget_min, budget_max = _extract_budget(chat_combined)
    requested_size = (
        _extract_size(str(dynamic_prefs.get("size") or ""))
        or _extract_size(current_request_text)
        or _extract_size(chat_combined)
    )

    return {
        "search_query": search_query,
        "exact_category": exact_category,
        "detected_garment": detected_garment,
        "gender": gender,
        "colors": colors,
        "requested_colors": requested_colors,
        "combined_text": combined,
        "budget_min": budget_min or profile.budget_min,
        "budget_max": budget_max or profile.budget_max,
        "requested_size": requested_size,
        "invalid_budget": invalid_budget,
        "requested_brands": requested_brands,
        "construction": construction,
        "outfit_context": outfit_context,
        "ethnicity": (profile.ethnicity or "").lower().strip() if hasattr(profile, 'ethnicity') else "",
    }


def _default_garments(gender: str, profile: UserProfileInput) -> list[str]:
    styles = [s.lower() for s in profile.style_preferences]
    if any(s in styles for s in ("ethnic", "formal", "classic")):
        return ["kurta"] if gender == "male" else ["kurti"]
    if any(s in styles for s in ("streetwear", "casual")):
        return ["jeans", "shirt"] if gender == "male" else ["jeans", "top"]
    if gender == "male":
        return ["casual shirt"]
    return ["kurti"]


def _dynamic_prefs_text(dynamic_prefs: dict) -> str:
    parts: list[str] = []
    garment = dynamic_prefs.get("garment")
    if garment:
        parts.append(str(garment))
    colors = _normalize_dynamic_colors(dynamic_prefs.get("colors"))
    if colors:
        parts.append(" ".join(colors))
    occasion = dynamic_prefs.get("occasion")
    if occasion:
        parts.append(str(occasion))
    notes = dynamic_prefs.get("style_notes")
    if notes:
        parts.append(str(notes))
    return " ".join(parts).lower()


def _normalize_dynamic_colors(raw: object) -> list[str]:
    if not raw:
        return []
    values = raw if isinstance(raw, list) else [raw]
    colors: list[str] = []
    for value in values:
        color = str(value).lower().strip()
        if color and color not in colors:
            colors.append(color)
    return colors


def _positive_int_or_none(value: object) -> int | None:
    if value is None:
        return None
    try:
        parsed = int(str(value).replace(",", "").strip())
    except ValueError:
        return None
    return parsed if parsed >= 0 else None


def _detect_garment(text: str) -> tuple[str, str] | None:
    """Return (detected phrase, canonical category) from text.

    We choose the earliest explicit phrase in the source text, with longer
    phrases winning only when they start at the same position. This preserves
    the user's current wording and avoids old/default context overriding it.
    """
    normalized = text.lower()
    matches: list[tuple[int, int, str, str]] = []
    for phrase in _MULTI_WORD_GARMENTS:
        pattern = rf"(?<![a-z0-9]){re.escape(phrase)}(?![a-z0-9])"
        match = re.search(pattern, normalized)
        if match:
            matches.append((match.start(), -len(phrase), phrase, CATEGORY_MAP[phrase]))
    if not matches:
        return None
    _, _, phrase, category = sorted(matches)[0]
    return phrase, category


def _extract_budget(text: str) -> tuple[int | None, int | None]:
    amounts = [
        int(match.group(1).replace(",", ""))
        for match in re.finditer(
            r"(?<!-)(?:rs\.?|pkr|under|below|budget|max|within)?\s*(\d[\d,]{2,6})",
            text,
        )
    ]
    if not amounts:
        return None, None
    strongest = max(amounts)
    if any(word in text for word in ("under", "below", "max", "within", "budget")):
        return None, strongest
    if len(amounts) >= 2:
        return min(amounts), max(amounts)
    return None, strongest


def _contains_negative_budget(text: str) -> bool:
    return bool(
        re.search(
            r"(?<!\d)-\s*\d[\d,]*\s*(?:pkr|rs\.?|rupees?)?\b",
            text,
            flags=re.IGNORECASE,
        )
    )


def _extract_colors(text: str) -> list[str]:
    """Extract color words/phrases while preserving user-message priority."""
    normalized = text.lower()
    colors: list[str] = []
    for color in sorted(COLOR_KEYWORDS, key=len, reverse=True):
        if re.search(rf"\b{re.escape(color)}\b", normalized) and color not in colors:
            colors.append(color)
    return colors


def _extract_brands(text: str) -> list[str]:
    normalized = f" {text.lower()} "
    found: list[str] = []
    for brand, aliases in BRAND_ALIASES.items():
        for alias in aliases:
            if re.search(rf"(?<![a-z0-9]){re.escape(alias)}(?![a-z0-9])", normalized):
                found.append(brand)
                break
    return found


def _extract_construction(text: str) -> str | None:
    normalized = text.lower()
    if re.search(r"\bunstitched\b|\bfabric\b|\bcloth only\b", normalized):
        return "unstitched"
    if re.search(r"\bstitched\b|\bready to wear\b|\bready-to-wear\b|\bpret\b|\brtw\b", normalized):
        return "stitched"
    return None


def _extract_outfit_context(text: str, exact_category: str | None) -> str | None:
    normalized = text.lower()
    has_waistcoat = "waistcoat" in normalized or "waist coat" in normalized
    has_shalwar = any(
        phrase in normalized
        for phrase in ("shalwar kameez", "shalwar qameez", "salwar kameez", "kurta shalwar")
    )
    if has_waistcoat and has_shalwar:
        return "shalwar-kameez-waistcoat"
    if exact_category == "three-piece-suit":
        return "western-three-piece"
    return None


def _extract_size(text: str) -> str | None:
    normalized = f" {text.lower()} "
    patterns = [
        ("4XL", ("4xl", "xxxxl")),
        ("XXXL", ("xxxl", "3xl", "triple xl")),
        ("XXL", ("xxl", "2xl", "double xl")),
        ("XL", ("xl", "x-large", "extra large")),
        ("L", ("large", " size l ", " l size", " l ")),
        ("M", ("medium", " size m ", " m size", " m ")),
        ("S", ("small", " size s ", " s size", " s ")),
        ("XS", ("xs", "x-small", "extra small")),
    ]
    for size, keys in patterns:
        if any(key in normalized for key in keys):
            return size
    return None


def product_matches_category(
    title: str,
    tags: list[str],
    product_category: str | None,
    exact_category: str | None,
) -> bool:
    """Check if a product matches the user's requested exact category.

    Returns True if no category filter is active, or if the product's
    title/tags/category contain keywords for the requested category.
    """
    if not exact_category:
        return True

    # ── Strict Shalwar Kameez Suit Filter (No standalone bottoms/tops allowed) ──
    if exact_category == "shalwar-kameez":
        title_lower = title.lower()
        blob_lower = f"{title_lower} {' '.join(tags).lower()} {product_category or ''}".lower()
        if re.search(
            r"shalwar[ -]?kameez|shalwar[ -]?qameez|salwar[ -]?kameez|salwar[ -]?qameez",
            blob_lower,
        ):
            return True

        # Clean the blob to remove category compound names (space or hyphen)
        clean_blob = re.sub(
            r"shalwar[ -]?kameez|shalwar[ -]?qameez|salwar[ -]?kameez|salwar[ -]?qameez",
            "",
            blob_lower,
        )
        clean_blob = re.sub(r"\s+", " ", clean_blob)

        has_bottom = any(
            w in clean_blob for w in ["shalwar", "salwar", "pajama", "pajamas", "trouser", "bottom"]
        )
        has_top = any(w in clean_blob for w in ["kameez", "qameez", "kurta", "kurti", "top"])
        has_suit_keyword = any(w in clean_blob for w in ["suit", "set", "2pc", "3pc", "2 piece", "3 piece", "2-piece", "3-piece", "pair"])
        
        is_suit = has_suit_keyword or (has_bottom and has_top)
        if not is_suit:
            return False

    acceptable = CATEGORY_KEYWORDS.get(exact_category)
    if not acceptable:
        return True  # unknown category, don't filter

    blob = f"{title} {' '.join(tags)} {product_category or ''}".lower()

    # Positive: product must contain at least one keyword for this category
    if any(kw in blob for kw in acceptable):
        return True

    # Negative: reject if product clearly belongs to a conflicting category
    return False


def product_conflicts_with_category(
    title: str,
    tags: list[str],
    exact_category: str | None,
) -> bool:
    """Returns True if a product clearly belongs to a CONFLICTING category.

    Two checks:
    1. Standard keyword-in-blob check against conflict sets.
    2. Strict traditional attire exclusions: when user requests a Western garment
       (e.g., suit, blazer, trouser), we strictly block traditional Eastern items.
    3. Primary garment detection: if the product title starts with a conflicting garment.
    """
    if not exact_category:
        return False

    blob = f"{title} {' '.join(tags)}".lower()

    # ── Strict Western ↔ Eastern Hard Block Heuristic ──
    _WESTERN_CATEGORIES = {
        "two-piece-suit",
        "three-piece-suit",
        "blazer",
        "formal-shirt",
        "casual-shirt",
        "trouser",
        "chinos",
        "jeans",
        "casual-trouser-shirt",
    }
    if exact_category in _WESTERN_CATEGORIES:
        traditional_keywords = {
            "kurta", "kameez", "shalwar", "salwar", "pajama", "unstitched",
            "lawn", "embroidered", "printed", "kurti", "sherwani", "waistcoat",
            "dupatta", "chiffon", "silk", "khaddar", "linen", "achkan",
            "prince coat", "princecoat", "nehru", "lawn suit", "unstitched suit",
            "cotton suit", "embellished suit", "matching separates"
        }
        for kw in traditional_keywords:
            if kw in blob:
                # Special exception: allow "linen" or "cotton" for blazers/shirts if not traditional
                if kw in {"linen", "silk"} and any(w in blob for w in ("blazer", "shirt", "pant", "suit")):
                    continue
                return True

    # ── Strict Western-Eastern suiting segregation ──
    if exact_category == "shalwar-kameez":
        western_suit_keywords = {"pent coat", "pentcoat", "two-piece", "three-piece", "coat pant", "blazer", "suit coat", "formal suit", "coat trouser"}
        if any(kw in blob for kw in western_suit_keywords):
            return True

    if exact_category in {"two-piece-suit", "three-piece-suit"}:
        traditional_suit_keywords = {"shalwar", "salwar", "kameez", "qameez", "kurta", "pajama", "sherwani"}
        if any(kw in blob for kw in traditional_suit_keywords):
            return True

    if exact_category == "waistcoat":
        western_suit_keywords = {
            "pent coat",
            "pentcoat",
            "two piece suit",
            "three piece suit",
            "2 piece suit",
            "3 piece suit",
            "coat pant",
            "coat trouser",
            "blazer",
            "formal suit",
        }
        if any(kw in blob for kw in western_suit_keywords):
            return True

    conflicts = CATEGORY_CONFLICTS.get(exact_category)
    if conflicts:
        # ── Check 1: standard keyword conflict ──
        for conflicting_cat in conflicts:
            conflict_keywords = CATEGORY_KEYWORDS.get(conflicting_cat, set())
            if exact_category == "shalwar-kameez" and conflicting_cat in {
                "two-piece-suit",
                "three-piece-suit",
            }:
                conflict_keywords = {
                    kw for kw in conflict_keywords if kw not in {"suit", "suits"}
                }
            if any(kw in blob for kw in conflict_keywords):
                return True

    # ── Check 3: primary garment detection ──
    title_lower = title.lower().strip()
    for phrase in _MULTI_WORD_GARMENTS:
        if title_lower.startswith(phrase):
            primary_category = CATEGORY_MAP.get(phrase)
            if primary_category and conflicts and primary_category in conflicts:
                return True
            break  # found the primary, stop looking

    return False
