"""Score and rank products based on user profile, category match, and preferences.

Key change: massive penalty for category mismatch, and a minimum score threshold
to prevent irrelevant results from being shown.
"""

import re
import uuid

from models.schemas import ProductRecommendation, UserProfileInput
from services.query_builder import (
    CATEGORY_KEYWORDS,
    product_conflicts_with_category,
    product_matches_category,
)

MINIMUM_SCORE = 15  # products below this score are filtered out

COLOR_FAMILIES = {
    "blue": {"blue", "navy", "royal blue", "sky blue", "turquoise", "teal"},
    "navy": {"navy", "blue", "royal blue"},
    "royal blue": {"royal blue", "blue", "navy"},
    "sky blue": {"sky blue", "blue", "turquoise"},
    "green": {"green", "olive", "sage", "mint", "emerald", "teal"},
    "red": {"red", "maroon", "burgundy", "wine", "ruby"},
    "pink": {"pink", "rose pink", "magenta", "coral"},
    "white": {"white", "off white", "ivory", "cream"},
    "black": {"black", "charcoal"},
    "grey": {"grey", "gray", "charcoal"},
    "gray": {"gray", "grey", "charcoal"},
    "brown": {"brown", "tan", "khaki", "rust", "copper", "bronze"},
    "beige": {"beige", "tan", "cream", "khaki"},
    "cream": {"cream", "ivory", "off white", "beige", "white"},
    "purple": {"purple", "lavender", "plum"},
    "yellow": {"yellow", "mustard", "gold"},
    "gold": {"gold", "yellow", "mustard"},
    "orange": {"orange", "coral", "rust"},
}


def infer_clothing_size(profile: UserProfileInput) -> str | None:
    """Map body measurements to typical PK ready-to-wear size label."""
    chest = profile.chest_cm
    waist = profile.waist_cm
    hip = profile.hip_cm
    height = profile.height_cm
    weight = profile.weight_kg
    gender = (profile.gender or "").lower()

    if chest:
        chest_inches = chest / 2.54
        if chest_inches <= 35:
            base = "S"
        elif chest_inches <= 37:
            base = "M"
        elif chest_inches <= 39:
            base = "L"
        elif chest_inches <= 41:
            base = "XL"
        elif chest_inches <= 43:
            base = "XXL"
        elif chest_inches <= 45:
            base = "XXXL"
        else:
            base = "4XL"
    elif waist:
        if waist < 70:
            base = "S"
        elif waist < 78:
            base = "M"
        elif waist < 86:
            base = "L"
        else:
            base = "XL"
    elif height and weight:
        bmi = weight / ((height / 100) ** 2)
        if bmi < 20:
            base = "S"
        elif bmi < 25:
            base = "M"
        elif bmi < 30:
            base = "L"
        else:
            base = "XL"
    else:
        return None

    return base


def infer_size_guidance(profile: UserProfileInput) -> str:
    """Build a human-friendly size guidance string."""
    size = infer_clothing_size(profile)
    if not size:
        return ""
    parts = [f"Recommended Size: {size}"]
    if profile.chest_cm:
        parts.append(f"chest {profile.chest_cm:g}cm")
    if profile.waist_cm:
        parts.append(f"waist {profile.waist_cm:g}cm")
    return " — ".join(parts)


def skin_tone_color_hints(skin_tone: str | None) -> list[str]:
    if not skin_tone:
        return []
    tone = skin_tone.lower()
    if any(x in tone for x in ("fair", "light", "type i", "type ii")):
        return ["pastel", "navy", "jewel", "cool", "blue", "pink", "lavender"]
    if any(x in tone for x in ("medium", "wheat", "type iii", "type iv")):
        return ["earth", "olive", "teal", "maroon", "mustard", "white", "denim"]
    if any(x in tone for x in ("deep", "dark", "brown", "type v", "type vi")):
        return ["gold", "emerald", "coral", "white", "bright", "burgundy", "cream"]
    return []


def _hard_gender_conflict(text: str, gender: str) -> bool:
    female_only = {
        "saree",
        "sari",
        "lehenga",
        "gharara",
        "sharara",
        "dupatta",
        "kurti",
        "women",
        "womens",
        "ladies",
        "girls",
        "female",
    }
    male_only = {
        "men",
        "mens",
        "boys",
        "male",
        "sherwani",
        "prince coat",
        "groom",
        "pent coat",
        "pentcoat",
        "two piece suit",
        "three piece suit",
        "coat pant",
        "blazer suit",
        "tuxedo",
        "kurta pajama",
    }
    if gender == "male" and any(re.search(rf"\b{re.escape(word)}\b", text) for word in female_only):
        return True
    if gender == "female" and any(re.search(rf"\b{re.escape(word)}\b", text) for word in male_only):
        return True
    return False


def _product_matches_requested_color(product: dict, text: str, requested_colors: list[str]) -> bool:
    product_colors = [
        c.lower().strip() for c in (product.get("colors") or []) if isinstance(c, str)
    ]
    searchable = f"{text} {' '.join(product_colors)}"
    for requested in requested_colors:
        color = requested.lower().strip()
        family = COLOR_FAMILIES.get(color, {color})
        for candidate in family | {color}:
            if re.search(rf"\b{re.escape(candidate)}\b", searchable):
                return True
    return False


def _construction_conflict(text: str, construction: str | None) -> bool:
    if not construction:
        return False
    has_unstitched = any(w in text for w in ("unstitched", "fabric", "lawn fabric"))
    has_stitched = any(w in text for w in ("stitched", "ready to wear", "ready-to-wear", "pret", "rtw"))
    if construction == "unstitched":
        return has_stitched and not has_unstitched
    if construction == "stitched":
        return has_unstitched
    return False


def _outfit_context_conflict(text: str, outfit_context: str | None) -> bool:
    if outfit_context == "shalwar-kameez-waistcoat":
        return not (
            ("waistcoat" in text or "waist coat" in text or "vest" in text)
            and any(w in text for w in ("shalwar", "salwar", "kameez", "qameez", "kurta"))
        )
    if outfit_context == "western-three-piece":
        return any(w in text for w in ("shalwar", "salwar", "kameez", "qameez", "kurta"))
    return False


def score_product(
    product: dict,
    profile: UserProfileInput,
    context: dict,
) -> tuple[int, list[str]]:
    score = 50
    reasons: list[str] = []

    title = (product.get("title") or "").lower()
    tags_list = product.get("tags") or []
    tags = " ".join(tags_list) if isinstance(tags_list, list) else str(tags_list)
    tags = tags.lower()
    text = f"{title} {tags}"
    product_category = (product.get("category") or "").lower()
    exact_category = context.get("exact_category")
    requested_size = context.get("requested_size")
    requested_colors = [
        c.lower().strip()
        for c in (context.get("requested_colors") or [])
        if isinstance(c, str) and c.strip()
    ]
    requested_brands = [
        b.lower()
        for b in (context.get("requested_brands") or [])
        if isinstance(b, str) and b.strip()
    ]
    construction = context.get("construction")
    outfit_context = context.get("outfit_context")

    if requested_brands and product.get("brand", "").lower() not in requested_brands:
        return 0, ["wrong requested brand"]

    if _construction_conflict(text, construction):
        return 0, [f"not {construction}"]

    if _outfit_context_conflict(text, outfit_context):
        return 0, ["wrong outfit context"]

    if _hard_gender_conflict(text, context.get("gender", "female")):
        return 0, ["wrong gender category"]

    if requested_colors and not _product_matches_requested_color(
        product, text, requested_colors
    ):
        return 0, ["does not match requested color"]

    # CATEGORY MATCH / MISMATCH (most important signal)
    if exact_category:
        if product_matches_category(title, product.get("tags", []), product_category, exact_category):
            score += 25
            reasons.append(f"exact match for {context.get('detected_garment', exact_category)}")
        else:
            score -= 50  # strong penalty for wrong category
        if product_conflicts_with_category(title, product.get("tags", []), exact_category):
            score -= 40  # additional penalty for conflicting category

    # Gender alignment
    gender = context.get("gender", "female")
    if gender == "female" and any(
        re.search(rf"\b{w}\b", text) for w in ("men", "mens", "boys", "male")
    ):
        score -= 35
    elif gender == "male" and any(
        re.search(rf"\b{w}\b", text)
        for w in ("women", "womens", "girls", "ladies", "female")
    ):
        score -= 35
    else:
        score += 5
        reasons.append("matches your gender selection")

    # Merge colors from context and profile preferences for soft scoring.
    # Chat-requested colors were already enforced above as a hard filter.
    requested_colors: list[str] = []
    ctx_colors = context.get("colors") or []
    if isinstance(ctx_colors, list):
        requested_colors.extend([c.lower() for c in ctx_colors if isinstance(c, str)])
    if getattr(profile, "preferred_colors", None):
        requested_colors.extend([c.lower() for c in profile.preferred_colors if isinstance(c, str)])
    # Deduplicate while preserving order
    seen_colors = set()
    final_req_colors = []
    for c in requested_colors:
        if c not in seen_colors:
            seen_colors.add(c)
            final_req_colors.append(c)

    if final_req_colors:
        product_colors = [c.lower() for c in (product.get("colors") or []) if isinstance(c, str)]
        matched_color = None
        for color in final_req_colors:
            if color in text or any(color in pc for pc in product_colors):
                matched_color = color
                break
        if matched_color:
            score += 15
            reasons.append(f"{matched_color} matches your preference")
        else:
            # Soft penalty for not matching preferred colors — don't overfilter
            score -= 8

    # Style preference match (stronger weight)
    for pref in getattr(profile, "style_preferences", []) or []:
        if pref and pref.lower() in text:
            score += 12
            reasons.append(f"matches {pref} style")
            break

    # Occasion match (if the user has occasions in profile)
    for occ in getattr(profile, "occasions", []) or []:
        if occ and occ.lower() in text:
            score += 8
            reasons.append(f"suitable for {occ}")
            break

    # Skin tone color harmony
    for hint in skin_tone_color_hints(profile.skin_tone)[:6]:
        if hint in text:
            score += 5
            reasons.append(f"complements {profile.skin_tone} skin tone")
            break

    # Ethnicity / cultural match
    ethnicity = context.get("ethnicity", "").lower().strip()
    if ethnicity:
        from services.query_builder import ETHNICITY_KEYWORDS
        ethnic_keywords = ETHNICITY_KEYWORDS.get(ethnicity, set())
        if ethnic_keywords and any(kw in text for kw in ethnic_keywords):
            score += 8
            reasons.append(f"matches {ethnicity.title()} cultural style")

    # Budget — HARD FILTER: skip products above budget_max entirely
    price = product.get("price_pkr")
    bmin = context.get("budget_min") or profile.budget_min
    bmax = context.get("budget_max") or profile.budget_max
    if price and bmax and price > bmax:
        return 0, ["over budget"]  # hard exclude — caller checks MINIMUM_SCORE
    if price and bmax and price <= bmax:
        score += 10
        reasons.append("within your budget")
    elif price and bmin and price >= bmin:
        score += 4

    # Size availability
    inferred = requested_size or infer_clothing_size(profile)
    sizes = [s.upper() for s in (product.get("sizes") or [])]
    if inferred and sizes:
        if inferred in sizes or any(inferred in s for s in sizes):
            score += 10
            reasons.append(f"size {inferred} available")
        else:
            score += 1

    # Body type hints
    body = (profile.body_type or "").lower()
    if body:
        if "pear" in body and any(w in text for w in ("a-line", "flared", "wide leg")):
            score += 5
            reasons.append("flatters pear body shape")
        if "apple" in body and any(w in text for w in ("empire", "v-neck", "straight")):
            score += 5
            reasons.append("flatters apple body shape")
        if "hourglass" in body and any(w in text for w in ("fitted", "belted", "wrap")):
            score += 5
            reasons.append("flatters hourglass shape")

    score = max(0, min(99, score))

    # Deduplicate reasons
    seen: set[str] = set()
    unique_reasons: list[str] = []
    for r in reasons:
        if r not in seen:
            seen.add(r)
            unique_reasons.append(r)
    if not unique_reasons:
        unique_reasons.append("curated for your SmartFit profile")

    return score, unique_reasons[:4]


def rank_products(
    raw_products: list[dict],
    profile: UserProfileInput,
    context: dict,
    limit: int,
) -> list[ProductRecommendation]:
    inferred_size = context.get("requested_size") or infer_clothing_size(profile)
    size_guidance = (
        f"Requested Size: {inferred_size}"
        if context.get("requested_size")
        else infer_size_guidance(profile)
    )

    scored: list[tuple[int, ProductRecommendation]] = []
    for item in raw_products:
        match_score, match_reasons = score_product(item, profile, context)

        # ── MINIMUM SCORE THRESHOLD: skip irrelevant products ──
        if match_score < MINIMUM_SCORE:
            continue

        scored.append(
            (
                match_score,
                ProductRecommendation(
                    id=item.get("id") or str(uuid.uuid4()),
                    brand=item["brand"],
                    title=item["title"],
                    category=item.get("category"),
                    price_pkr=item.get("price_pkr"),
                    currency=item.get("currency", "PKR"),
                    image_url=item.get("image_url"),
                    product_url=item["product_url"],
                    sizes=item.get("sizes") or [],
                    colors=item.get("colors") or [],
                    tags=item.get("tags") or [],
                    match_score=match_score,
                    match_reasons=match_reasons,
                    in_stock=item.get("in_stock", True),
                    recommended_size=inferred_size,
                    size_guidance=size_guidance,
                ),
            )
        )

    scored.sort(key=lambda x: x[0], reverse=True)
    return [p for _, p in scored[:limit]]
