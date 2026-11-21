"""Face anchors for hairstyle alignment, from the MediaPipe 478-point face mesh
(services/cv_analysis/face_landmarks.py loads the model).

The same three anchors are stored for every catalog hairstyle (measured on
the photo it was cut from) and found on the user's photo; overlay.py maps one
set onto the other. Eye centres fix position, size and head tilt; the chin
fixes the face length, so a hairstyle from a long face still sits right on a
round one.
"""

from __future__ import annotations

from collections.abc import Sequence

from services.cv_analysis.structure import FACE_CONTOURS

# The person's own left/right (MediaPipe's "left_eye" is the person's left = image right).
_LEFT_EYE = FACE_CONTOURS["left_eye"][:-1]
_RIGHT_EYE = FACE_CONTOURS["right_eye"][:-1]
CHIN = 152
FOREHEAD_TOP = 10
CHEEK_R, CHEEK_L = 234, 454
NOSE_TIP = 1
# Skin sample for light matching: cheeks and forehead, away from eyes, brows and hair.
SKIN_POINTS = (50, 101, 118, 117, 280, 330, 347, 346, 151, 9, 108, 337)


def _mean(points: Sequence[tuple[float, float]]) -> tuple[float, float]:
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def anchors(points: Sequence[tuple[float, float]], img_w: int, img_h: int) -> dict[str, list[float]] | None:
    """{'left_eye', 'right_eye', 'chin', 'forehead'} in pixels, or None without a full mesh."""
    if len(points) < 468:
        return None
    px = [(x * img_w, y * img_h) for x, y in points]
    left = _mean([px[i] for i in _LEFT_EYE])
    right = _mean([px[i] for i in _RIGHT_EYE])
    return {
        "left_eye": [round(left[0], 2), round(left[1], 2)],
        "right_eye": [round(right[0], 2), round(right[1], 2)],
        "chin": [round(px[CHIN][0], 2), round(px[CHIN][1], 2)],
        "forehead": [round(px[FOREHEAD_TOP][0], 2), round(px[FOREHEAD_TOP][1], 2)],
    }


def face_turn(points: Sequence[tuple[float, float]]) -> float:
    """0 = looking straight; larger = head turned (nose-to-cheek asymmetry / cheek width)."""
    nose, r, lft = points[NOSE_TIP], points[CHEEK_R], points[CHEEK_L]
    cheek = abs(lft[0] - r[0]) or 1e-6
    return abs(abs(nose[0] - r[0]) - abs(lft[0] - nose[0])) / cheek


def skin_luma(luma, points: Sequence[tuple[float, float]]) -> float | None:
    """Median brightness (0-255) of small patches on the cheeks and forehead."""
    import numpy as np

    h, w = luma.shape[:2]
    if len(points) < 468:
        return None
    face_w = abs(points[CHEEK_L][0] - points[CHEEK_R][0]) * w
    half = max(2, int(face_w * 0.03))
    values = []
    for i in SKIN_POINTS:
        x, y = int(points[i][0] * w), int(points[i][1] * h)
        patch = luma[max(0, y - half):y + half, max(0, x - half):x + half]
        if patch.size:
            values.append(float(np.median(patch)))
    return float(np.median(values)) if values else None
