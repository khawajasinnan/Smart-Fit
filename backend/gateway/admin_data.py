"""Pure helpers for the admin API (SFR-039 .. SFR-042): no I/O, unit-tested."""

from __future__ import annotations

import re
import statistics
from collections import Counter
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta

UserStatus = str  # "banned" | "suspended" | "deactivated" | "incomplete" | "active"

_UNSAFE_SEARCH = re.compile(r"[^\w@.\- ]", re.UNICODE)


def parse_ts(value) -> datetime | None:
    if not value:
        return None
    try:
        ts = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return ts if ts.tzinfo else ts.replace(tzinfo=UTC)


def iso_z(ts: datetime) -> str:
    """UTC timestamp for PostgREST filters, written without a '+' sign."""
    return ts.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def user_status(row: dict, now: datetime) -> UserStatus:
    if row.get("is_banned"):
        return "banned"
    until = parse_ts(row.get("suspended_until"))
    if until and until > now:
        return "suspended"
    if row.get("deactivated_at"):
        return "deactivated"
    if not row.get("profile_completed"):
        return "incomplete"
    return "active"


def clean_search(term: str) -> str:
    """Keep letters, digits, @ . - _ and spaces: safe inside a PostgREST or=() filter."""
    return _UNSAFE_SEARCH.sub("", term or "").strip()[:80]


def user_filters(search: str, status: str, now: datetime) -> dict[str, str]:
    filters: dict[str, str] = {}
    term = clean_search(search)
    if term:
        filters["or"] = f"(email.ilike.*{term}*,full_name.ilike.*{term}*,username.ilike.*{term}*)"
    stamp = iso_z(now)
    if status == "banned":
        filters["is_banned"] = "is.true"
    elif status == "suspended":
        filters["suspended_until"] = f"gt.{stamp}"
        filters["is_banned"] = "not.is.true"
    elif status == "deactivated":
        filters["deactivated_at"] = "not.is.null"
    elif status == "incomplete":
        filters["profile_completed"] = "not.is.true"
    elif status == "active":
        filters["and"] = (f"(is_banned.not.is.true,deactivated_at.is.null,profile_completed.is.true,"
                          f"or(suspended_until.is.null,suspended_until.lte.{stamp}))")
    return filters


def daily_series(timestamps: Iterable, days: int, now: datetime) -> list[dict]:
    """Counts per UTC day for the last `days` days, oldest first, zero-filled."""
    today = now.astimezone(UTC).date()
    first = today - timedelta(days=days - 1)
    counts: Counter = Counter()
    for value in timestamps:
        ts = parse_ts(value)
        if ts and first <= ts.astimezone(UTC).date() <= today:
            counts[ts.astimezone(UTC).date()] += 1
    return [{"date": (first + timedelta(days=i)).isoformat(), "count": counts[first + timedelta(days=i)]}
            for i in range(days)]


def top_counts(values: Iterable[str], n: int = 10) -> list[dict]:
    return [{"id": k, "count": c} for k, c in Counter(v for v in values if v).most_common(n)]


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    if len(values) == 1:
        return float(values[0])
    return float(statistics.quantiles(sorted(values), n=100, method="inclusive")[int(q) - 1])


def since(now: datetime, days: int) -> str:
    return iso_z(now - timedelta(days=days))
