"""Face shape -> ranked hairstyles (SFR-029 suggest, SFR-031 default + alternatives).

The face shape itself comes from the face mesh proportions
(services/cv_analysis/structure.classify_face_shape: oval, round, square,
heart, oblong, diamond). Which hairstyles suit which shape is the common
stylist guidance, written as rules over each catalog hairstyle's measured
features (catalog.py):

  length       short (above the chin) / medium (to the shoulders) / long
  bangs        hair over the forehead (CelebA attribute "Bangs")
  wavy         wavy or curly (CelebA attribute "Wavy_Hair")
  top_volume   hair height above the forehead, in face lengths
  side_width   hair width at the cheekbones, in face widths

  oval     balanced: almost any style
  round    add height and length, avoid width at the cheeks and heavy bangs
  square   soften the jaw: waves, layers, medium/long; avoid short and straight
  heart    balance a wider forehead: bangs, chin-to-shoulder length, less height on top
  oblong   shorten the face: bangs and width at the sides, avoid height and very long straight hair
  diamond  balance the cheekbones: bangs, medium length, fullness at the jaw

Rule-based (no training data with "suits / doesn't suit" labels exists), so
the reason shown to the user is the rule that applied.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class StyleFeatures:
    gender: str  # "male" | "female"
    length: str  # "short" | "medium" | "long"
    bangs: bool
    wavy: bool
    top_volume: float
    side_width: float


@dataclass
class Suitability:
    score: float
    reasons: list[str] = field(default_factory=list)


FACE_SHAPES = ("oval", "round", "square", "heart", "oblong", "diamond")
HIGH_TOP = 0.30  # top_volume above this = noticeable height
WIDE_SIDES = 1.45  # side_width above this = noticeable width at the cheeks


def suitability(face_shape: str, f: StyleFeatures) -> Suitability:
    """0..1 (0.5 = neutral) with the reasons that moved it."""
    s = Suitability(0.5)

    def rule(condition: bool, delta: float, reason: str) -> None:
        if condition:
            s.score += delta
            if delta > 0:
                s.reasons.append(reason)

    shape = face_shape.lower()
    tall, wide = f.top_volume >= HIGH_TOP, f.side_width >= WIDE_SIDES
    if shape == "oval":
        rule(True, 0.15, "Oval faces suit almost any style")
        rule(f.length == "medium", 0.05, "a medium length keeps your balanced proportions")
    elif shape == "round":
        rule(tall, 0.15, "height on top makes a round face look longer")
        rule(f.length == "long" and f.gender == "female", 0.15, "long hair adds length to a round face")
        rule(f.gender == "male" and f.length == "short" and not wide, 0.1, "short sides keep a round face slim")
        rule(wide, -0.2, "")
        rule(f.bangs and not f.wavy, -0.1, "")
    elif shape == "square":
        rule(f.wavy, 0.2, "waves soften a strong jaw")
        rule(f.length in ("medium", "long") and f.gender == "female", 0.1, "length below the jaw softens a square face")
        rule(f.gender == "male" and f.length == "short", 0.1, "a short, neat cut suits a square jaw")
        rule(f.gender == "female" and f.length == "short" and not f.wavy, -0.2, "")
    elif shape == "heart":
        rule(f.bangs, 0.2, "bangs balance a wider forehead")
        rule(f.length == "medium", 0.15, "chin-to-shoulder length adds width at the jaw")
        rule(tall, -0.15, "")
    elif shape == "oblong":
        rule(f.bangs, 0.2, "bangs make a long face look shorter")
        rule(wide or f.wavy, 0.15, "width at the sides balances a long face")
        rule(tall, -0.2, "")
        rule(f.length == "long" and not f.wavy, -0.15, "")
    elif shape == "diamond":
        rule(f.bangs, 0.15, "bangs balance narrow forehead and chin")
        rule(f.length == "medium", 0.15, "fullness at the jaw balances wide cheekbones")
        rule(tall, -0.1, "")
    s.score = max(0.0, min(1.0, s.score))
    return s


def reason_text(face_shape: str, s: Suitability) -> str:
    if s.reasons:
        text = s.reasons[0]
        return text[0].upper() + text[1:] + "."
    return f"A neutral choice for a {face_shape.lower()} face."
