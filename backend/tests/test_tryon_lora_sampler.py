"""LoRA data order across Kaggle sessions: a resumed run must continue the
same seeded order, so "one pass" sees every pair exactly once."""

import sys
from itertools import islice
from pathlib import Path

import pytest

pytest.importorskip("torch")
pytest.importorskip("torchvision")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services" / "tryon" / "lora"))

from data import PassSampler  # noqa: E402


def take(sampler: PassSampler, n: int) -> list[int]:
    return list(islice(iter(sampler), n))


def test_one_pass_covers_every_sample_once():
    order = take(PassSampler(100, seed=42), 100)
    assert sorted(order) == list(range(100))


def test_resume_continues_the_same_order():
    full = take(PassSampler(100, seed=42), 250)  # 2.5 passes
    for cut in (0, 1, 37, 99, 100, 101, 180):
        assert take(PassSampler(100, seed=42, start=cut), 250 - cut) == full[cut:]


def test_a_two_session_pass_has_no_repeats_or_gaps():
    first = take(PassSampler(11, seed=3), 6)  # session 1 stops mid-pass
    second = take(PassSampler(11, seed=3, start=6), 5)  # session 2 resumes
    assert sorted(first + second) == list(range(11))


def test_each_pass_is_reshuffled_and_seeded():
    s = PassSampler(50, seed=1)
    assert s.order(0) != s.order(1)
    assert PassSampler(50, seed=1).order(0) == s.order(0)
    assert PassSampler(50, seed=2).order(0) != s.order(0)


def test_empty_dataset_is_rejected():
    with pytest.raises(ValueError):
        PassSampler(0, seed=1)
