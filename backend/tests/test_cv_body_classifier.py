"""CV body classifier (pure Python, no MediaPipe needed) — spec §6.2 rules."""

import pytest

from shared.schemas.cv import BodyProportions
from services.cv_analysis import body_classifier as bc
from services.cv_analysis.body_classifier import (
    APP_BODY_SHAPE_LABELS,
    BODY_TYPES,
    FEMALE_SHOULDER_HIP_BASELINE,
    LandmarkPoint,
    body_measurements_cm,
    classify_body_shape,
    classify_from_measurements,
    classify_from_pose,
    compute_proportions,
    estimate_gender_from_pose,
    estimate_size,
    to_spec_size,
)


@pytest.mark.parametrize(
    ("chest", "waist", "hip", "expected"),
    [
        (100, 110, 104, "oval"),  # waist is the widest measurement
        (92, 68, 94, "hourglass"),  # chest ≈ hip, waist/hip 0.72 < 0.75
        (86, 70, 100, "triangle"),  # hip > chest by > 5%
        (110, 85, 98, "inverted_triangle"),  # chest > hip by > 5%
        (90, 88, 92, "rectangle"),  # all within 5%
    ],
)
def test_every_body_type_is_reachable_from_measurements(chest, waist, hip, expected):
    shape, confidence = classify_from_measurements(chest, waist, hip)
    assert shape == expected
    assert 0 < confidence <= 1


def test_spec_otherwise_case_is_not_called_oval():
    # A balanced figure with a modest waist: the spec's literal "otherwise ->
    # oval" would say oval; documented deviation -> rectangle (low confidence).
    assert classify_from_measurements(100, 90, 98) == ("rectangle", 0.55)


def test_uniformly_balanced_figure_with_slightly_wider_waist_is_rectangle():
    assert classify_from_measurements(95, 100, 96)[0] == "rectangle"


def test_every_spec_type_has_an_app_label():
    assert set(APP_BODY_SHAPE_LABELS) == set(BODY_TYPES)


def test_pose_uses_the_measured_baseline_not_one():
    # Real women's landmark ratio (median 1.674) used to be "Inverted Triangle".
    assert classify_from_pose(FEMALE_SHOULDER_HIP_BASELINE, "female")[0] == "rectangle"
    assert classify_from_pose(1.80, "female")[0] == "inverted_triangle"
    assert classify_from_pose(1.55, "female")[0] == "triangle"


def test_pose_only_never_guesses_waist_dependent_types():
    seen = {classify_from_pose(r / 100, "female")[0] for r in range(120, 230)}
    assert seen == {"triangle", "rectangle", "inverted_triangle"}


def test_uncalibrated_male_pose_result_is_low_confidence():
    assert bc.MALE_SHOULDER_HIP_BASELINE is None
    assert classify_from_pose(2.1, "male")[1] <= 0.35


def test_classify_body_shape_reports_its_source():
    props = BodyProportions(shoulder_width_ratio=FEMALE_SHOULDER_HIP_BASELINE)
    assert classify_body_shape(props, "female", 92, 68, 94) == ("hourglass", 0.8, "measurements")
    assert classify_body_shape(props, "female")[2] == "pose"
    assert classify_body_shape(props, "female", 92, None, 94)[2] == "pose"  # needs all three


def test_gender_hint_disabled_until_male_baseline_is_calibrated():
    # Previously a typical woman (ratio ~1.67) was "male" at 0.95 confidence.
    for ratio in (1.0, 1.28, 1.674, 1.9):
        assert estimate_gender_from_pose(BodyProportions(shoulder_width_ratio=ratio)) == ("uncertain", 0.0)


def test_gender_hint_works_once_calibrated(monkeypatch):
    monkeypatch.setattr(bc, "MALE_SHOULDER_HIP_BASELINE", 2.0)
    assert estimate_gender_from_pose(BodyProportions(shoulder_width_ratio=2.1))[0] == "male"
    assert estimate_gender_from_pose(BodyProportions(shoulder_width_ratio=1.6))[0] == "female"
    assert estimate_gender_from_pose(BodyProportions(shoulder_width_ratio=1.84))[0] == "uncertain"


def _landmarks(shoulder_half_width: float, hip_half_width: float) -> list[LandmarkPoint]:
    pts = [LandmarkPoint(0.5, 0.5, 0.0, 0.9) for _ in range(33)]
    pts[0] = LandmarkPoint(0.5, 0.10, 0, 0.9)  # nose
    pts[11] = LandmarkPoint(0.5 - shoulder_half_width, 0.25, 0, 0.9)
    pts[12] = LandmarkPoint(0.5 + shoulder_half_width, 0.25, 0, 0.9)
    pts[23] = LandmarkPoint(0.5 - hip_half_width, 0.55, 0, 0.9)
    pts[24] = LandmarkPoint(0.5 + hip_half_width, 0.55, 0, 0.9)
    pts[27] = LandmarkPoint(0.48, 0.95, 0, 0.9)
    pts[28] = LandmarkPoint(0.52, 0.95, 0, 0.9)
    return pts


def test_proportions_never_invent_a_waist():
    props = compute_proportions(_landmarks(0.10, 0.10), 1000, 1000)
    assert props.shoulder_width_ratio == pytest.approx(1.0)
    assert props.waist_hip_ratio is None
    with_measurements = compute_proportions(_landmarks(0.10, 0.10), 1000, 1000, waist_cm=70, hip_cm=100)
    assert with_measurements.waist_hip_ratio == 0.7


def test_measurements_are_scaled_by_height():
    # nose (y .10) to ankles (y .95) = 850 px; x 1.08 head factor = 918 px for 170 cm.
    m = body_measurements_cm(_landmarks(0.10, 0.06), 1000, 1000, height_cm=170)
    px_per_cm = 850 * 1.08 / 170
    assert m == {
        "shoulder_cm": round(200 / px_per_cm, 1),
        "hip_cm": round(120 / px_per_cm, 1),
        "torso_cm": round(300 / px_per_cm, 1),
    }
    assert body_measurements_cm(_landmarks(0.1, 0.1), 1000, 1000, height_cm=0) is None


def test_size_estimation_priority_unchanged():
    assert estimate_size({}, "male", profile_chest=95) == ("M", "profile_measurements")
    assert estimate_size({"chest_cm": 106.0}, "male") == ("XL", "pose_landmarks")
    assert estimate_size({}, "female", height_cm=165, weight_kg=60) == ("M", "bmi_fallback")
    assert estimate_size({}, None) == ("M", "default_fallback")


@pytest.mark.parametrize(("chart", "spec"), [("XS", "S"), ("S", "S"), ("M", "M"), ("L", "L"), ("XL", "XL"), ("XXL", "XL")])
def test_spec_size_is_s_m_l_xl(chart, spec):
    assert to_spec_size(chart) == spec
