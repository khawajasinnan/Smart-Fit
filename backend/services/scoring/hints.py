"""Styling comments and practical hints (SFR-033).

Built only from facts the score already measured (component notes, the
garment's real colours, the user's skin tone, body shape and occasion), so a
hint can never claim something the scoring didn't check. Deliberately
template-based rather than LLM-written: same input, same advice, nothing
invented (spec §23.25).
"""

from __future__ import annotations

from shared.color_harmony import extract_colors, pairing_suggestions
from shared.occasion import usual_garments
from services.scoring.formula import Component

BODY_TIPS = {  # shape -> (tip for women, tip for men)
    "pear": ("Balance a pear shape with detail at the shoulders — an embroidered neckline or structured top.",
             "A structured shoulder (a waistcoat or tailored jacket) balances wider hips."),
    "apple": ("A V-neck or a straight, longer kameez draws the eye down and lengthens an apple shape.",
              "A straight, longer kurta or an open jacket draws the eye down and lengthens the frame."),
    "hourglass": ("Keep the waist defined — a belt or a fitted cut shows off an hourglass shape.",
                  "A tailored, fitted cut shows off a balanced frame."),
    "rectangle": ("Layers, a peplum or a belt add shape to a rectangle frame.",
                  "Layering — a waistcoat or an open jacket — adds shape to a straight frame."),
    "inverted": ("Wider-leg trousers or an A-line hem balance broader shoulders.",
                 "Straight or relaxed trousers balance broad shoulders; avoid very skinny fits."),
    "trapezoid": ("Most cuts suit this frame; a tailored fit at the shoulders looks sharpest.",
                  "Most cuts suit a trapezoid frame; a tailored fit at the shoulders looks sharpest."),
    # men's shapes in onboarding (21 Nov 2026); "inverted" above is checked first, so an
    # inverted triangle never gets the triangle tip
    "triangle": ("Balance a triangle shape with detail at the shoulders, like an embroidered neckline.",
                 "A structured shoulder (a waistcoat or blazer) and darker trousers balance a wider middle."),
    "oval": ("A V-neck or a straight, longer kameez draws the eye down and lengthens the frame.",
             "A straight, longer kurta, vertical lines and an open waistcoat lengthen an oval frame."),
}


def overall_comment(score: float) -> str:
    if score >= 85:
        return "This look really works for you."
    if score >= 70:
        return "A strong look — a couple of small tweaks would perfect it."
    if score >= 55:
        return "A decent look; the hints below would lift it."
    return "This combination isn't doing you justice yet — see what to change below."


def comments(components: list[Component]) -> list[str]:
    """One comment per component, strongest first (SFR-033 "AI-generated comments")."""
    return [c.note for c in sorted(components, key=lambda c: -c.score) if c.note]


def hints(components: list[Component], product: dict, profile: dict, occasion: str | None,
          fit_status: str, gender: str | None) -> list[str]:
    """Practical, specific things to do — weakest part of the look first."""
    by_key = {c.key: c for c in components}
    out: list[str] = []

    if fit_status == "small":
        out.append("Go one size up — a garment that's tight pulls at the seams and spoils the drape.")
    elif fit_status == "big":
        out.append("Go one size down, or have it tailored at the shoulders and waist.")

    occ = by_key.get("occasion")
    if occasion and occ and occ.score <= 30:
        usual = usual_garments(occasion)
        if usual:
            out.append(f"For {occasion}, people usually wear {', '.join(usual[:3])} — consider one of those instead.")

    colours = extract_colors(product)
    pairs = pairing_suggestions(colours, profile.get("skin_tone"))
    if colours and pairs:
        accents = "a dupatta, shoes or jewellery" if (gender or "").lower() == "female" \
            else "shoes, a waistcoat or a watch strap"
        out.append(f"Pair the {colours[0]} with {' or '.join(pairs)} accents — {accents}.")
    colour = by_key.get("colour")
    if colour and colour.known and colour.score < 50:
        out.append("Bring a flattering colour near your face (a scarf, collar or dupatta) to lift the look.")

    hair = by_key.get("hairstyle")
    if hair and hair.score < 45:
        out.append("Try the hairstyle SmartFit ranked first for your face shape — it will balance this outfit better.")

    body = (profile.get("body_type") or "").lower()
    is_female = (gender or "").lower() == "female"
    tip = next((t[0] if is_female else t[1] for shape, t in BODY_TIPS.items() if shape in body), None)
    if tip:
        out.append(tip)

    style = by_key.get("style")
    if style and style.known and style.score <= 45:
        prefs = [s for s in profile.get("style_preferences") or [] if isinstance(s, str)]
        if prefs:
            out.append(f"To keep it closer to your {prefs[0]} style, add one {prefs[0]} piece or accessory.")
    return out[:5]
