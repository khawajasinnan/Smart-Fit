"""Budgets from the chat (18 Nov 2026: "budget 10000 for sharara" showed a PKR 232,000
sharara). A budget is a hard limit, read only from the user's own words."""

from __future__ import annotations

import pytest

from shared.schemas.recommendation import UserProfileInput
from shared.taxonomy import _extract_budget, build_search_context


@pytest.mark.parametrize("text, expected", [
    ("my budget is 10000pkr show me sharara", (None, 10000)),
    ("sharara under 10000", (None, 10000)),
    ("sharara budget 10,000 PKR", (None, 10000)),
    ("sharara in 10k", (None, 10000)),
    ("10k budget", (None, 10000)),
    ("my budget is Rs. 10000 for sharara", (None, 10000)),
    ("kurta under rs 3,500", (None, 3500)),
    ("2 lakhs", (None, 200000)),
    ("1.5 lakh", (None, 150000)),
    ("10 hazar tak", (None, 10000)),
    ("5k-10k", (5000, 10000)),
    ("between 5000 and 10000", (5000, 10000)),
    ("5000 se 8000 tak", (5000, 8000)),
    ("budget 8000 not 20000", (None, 8000)),
    ("10000", (None, 10000)),  # the answer to "Budget kitna hai?"
])
def test_budgets_are_understood(text, expected):
    assert _extract_budget(text) == expected


@pytest.mark.parametrize("text", [
    "i am 175 cm and 70 kg", "size 32 jeans", "3pc lawn", "2026 collection", "show me 3 shararas",
    "sharara 50kg", "170", "sharara",
])
def test_measurements_sizes_and_years_are_never_a_budget(text):
    assert _extract_budget(text) == (None, None)


def ctx(user_message="", assistant="", chat_context="", prefs=None):
    return build_search_context(UserProfileInput(gender="female"), user_message, assistant, chat_context, prefs or {})


def test_the_stylists_reply_never_sets_the_budget():
    c = ctx("show me sharara", assistant="Here is one at PKR 232,000 within budget")
    assert c["budget_max"] is None


def test_a_budget_answered_one_message_earlier_is_used():
    c = ctx("Looking for: sharara", chat_context="User: show me sharara\nUser: 10000")
    assert c["budget_max"] == 10000


def test_only_user_lines_of_a_transcript_count():
    c = ctx("sharara", chat_context="User: sharara please\nStylist: Budget kitna hai? Most are PKR 232,000\nUser: 9000")
    assert c["budget_max"] == 9000


def test_the_ai_budget_wins_over_the_text():
    assert ctx("sharara under 20000", prefs={"budget_max": 10000})["budget_max"] == 10000
