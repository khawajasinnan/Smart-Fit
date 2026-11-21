"""Is this photo usable for a virtual try-on? (SFR-026/027, checked before any GPU work)

HRNet's 17 COCO keypoints (+ MediaPipe's person count) -> ok, or a code and a
message the app shows next to that photo. Pure function, unit-tested without
the models. The GPU step still has its own check; this one is free, fast and
gives the user a precise reason ("your ankles are cut off") instead of a
generic failure after a paid GPU run.

Rules:
  * exactly one person, and really a person: on 80 DressCode photos of people
    HRNet's mean joint confidence was >= 0.74, on 50 photos of clothes alone it
    was 0.32-0.80 and MediaPipe found nobody in nearly all of them. So when
    MediaPipe finds nobody we need >= 0.82, otherwise >= 0.6;
  * a shoulder and a hip visible (both of each in the front photo, where the
    body faces the camera);
  * upright: shoulders above hips, torso within 35 degrees of vertical;
  * big enough: shoulder-to-hip at least 15 % of the photo height;
  * front photo: the head is visible;
  * what the garment covers is in the photo: knees (or ankles, under a long
    dress) for a full outfit, knees and ankles for trousers.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

from services.cv_analysis.hrnet import INDEX, Keypoint

MAX_TORSO_TILT_DEG = 35.0
MIN_TORSO_FRACTION = 0.15  # shoulder-to-hip length / photo height (person fills about half the photo)
MIN_MEAN_CONFIDENCE = 0.6
MIN_MEAN_CONFIDENCE_ALONE = 0.82  # HRNet alone (MediaPipe found nobody): clothes reach 0.80
HEAD = ("nose", "left_eye", "right_eye", "left_ear", "right_ear")


@dataclass(frozen=True)
class PersonCheck:
    ok: bool
    code: str | None = None
    message: str = ""


def _found(kps: Sequence[Keypoint | None], *names: str) -> list[Keypoint]:
    return [k for n in names if (k := kps[INDEX[n]]) is not None]


def _mid(points: list[Keypoint]) -> tuple[float, float]:
    return sum(p.x for p in points) / len(points), sum(p.y for p in points) / len(points)


def check_person(
    keypoints: Sequence[Keypoint | None], people: int, category: str, angle: str, img_w: int, img_h: int
) -> PersonCheck:
    """category: 'upper' | 'lower' | 'dress'; angle: 'front' | 'right' | 'back' | 'left'."""
    where = f"the {angle} photo"
    if people > 1:
        return PersonCheck(False, "MULTIPLE_PEOPLE",
                           f"There's more than one person in {where}. Please take it with only you in the picture.")
    shoulders = _found(keypoints, "left_shoulder", "right_shoulder")
    hips = _found(keypoints, "left_hip", "right_hip")
    found = [k for k in keypoints if k is not None]
    confidence = sum(k.confidence for k in found) / len(found) if found else 0.0
    needed = MIN_MEAN_CONFIDENCE_ALONE if people == 0 else MIN_MEAN_CONFIDENCE
    if not shoulders or not hips or confidence < needed:
        return PersonCheck(False, "NO_PERSON",
                           f"We couldn't find your body in {where}. Stand 2-3 metres from the camera, in good light, "
                           "so you're visible from head to knees.")
    if angle == "front" and (len(shoulders) < 2 or len(hips) < 2):
        return PersonCheck(False, "NO_PERSON",
                           "In the front photo, please face the camera with both shoulders and hips visible.")

    (sx, sy), (hx, hy) = _mid(shoulders), _mid(hips)
    dx, dy = (hx - sx) * img_w, (hy - sy) * img_h
    tilt = math.degrees(math.atan2(abs(dx), dy)) if dy > 0 else 180.0
    if tilt > MAX_TORSO_TILT_DEG:
        return PersonCheck(False, "POSE_NOT_UPRIGHT",
                           f"Please stand up straight in {where} (not lying down, bending or upside down).")
    if math.hypot(dx, dy) < MIN_TORSO_FRACTION * img_h:
        return PersonCheck(False, "PERSON_TOO_SMALL",
                           f"You look too small in {where}. Come a little closer so your body fills most of the photo.")

    if angle == "front" and not _found(keypoints, *HEAD):
        return PersonCheck(False, "BODY_CUT_OFF", "Your head is cut off in the front photo. Please include your head.")
    knees = _found(keypoints, "left_knee", "right_knee")
    ankles = _found(keypoints, "left_ankle", "right_ankle")
    if category == "lower" and (not knees or not ankles):
        return PersonCheck(False, "BODY_CUT_OFF",
                           f"Trousers need your legs down to the ankles in {where}. Step back so your feet are in "
                           "the picture.")
    if category == "dress" and not knees and not ankles:  # a long kameez / dress may hide the knees
        return PersonCheck(False, "BODY_CUT_OFF",
                           f"A full outfit needs you visible down to at least the knees in {where}. Step back a little.")
    return PersonCheck(True)
