"""Product-specific size charts (fit check, SFR-025).

Outfitters attaches a size chart to most products through a tag like
"f0647-109-SimplifiedSizechart"; the store page loads it from the size-chart
app's API (smartsizechart.technogroves.com, robots.txt allows all). Rows
look like:

    ["SIZE", "30", "32", "34"]
    ["Round Waist Width ", "87", "92", "97"]   <- full circumference, cm
    ["Chest Width", "55", "58", "61"]          <- garment laid flat, cm

Only rows that can be interpreted without guessing become garment
circumferences (cm) that a body measurement can be compared with:
  * name contains "round"            -> circumference as given
  * name contains "width", no "round"-> flat width, x2 = circumference
  * anything else (e.g. just "Waist") -> ambiguous: kept for display only
Elastic waists publish both "... Relaxed" and "... Stretched" rows; they are
kept apart as waist_relaxed_cm / waist_stretched_cm (the fit check needs both).
Every converted value must also fall inside a plausible circumference range,
otherwise the measure is dropped. No unit is published; the values are
centimetres by magnitude (a 30-label waist of 87 can't be inches), and the
range check rejects anything that doesn't fit that reading.
"""

from __future__ import annotations

import re

from services.scraper.polite import PoliteClient

SIZE_CHART_API = "https://smartsizechart.technogroves.com/api/product_size_charts"
CHART_TAG = re.compile(r"sizechart", re.I)

# Body measures we can compare against, and plausible garment
# circumference ranges (cm) for adults. Tunable.
MEASURES = {
    "chest": ("chest", "bust"),
    "waist": ("waist",),
    "hip": ("hip",),
}
PLAUSIBLE_CM = {"chest": (60, 180), "waist": (50, 170), "hip": (60, 180)}


def chart_tag(tags: list[str]) -> str | None:
    return next((t.strip() for t in tags if CHART_TAG.search(t)), None)


def _measure_of(row_name: str) -> str | None:
    name = row_name.lower()
    for measure, words in MEASURES.items():
        if any(w in name for w in words):
            return measure
    return None


def parse_chart(rows: list[list[str]]) -> dict[str, dict[str, float]] | None:
    """{size_label: {"chest_cm"|"waist_cm"|"hip_cm": circumference}} or None."""
    if not rows or not rows[0] or str(rows[0][0]).strip().upper() != "SIZE":
        return None
    sizes = [str(s).strip() for s in rows[0][1:]]
    chart: dict[str, dict[str, float]] = {s: {} for s in sizes if s}
    for row in rows[1:]:
        if not row:
            continue
        name = str(row[0]).strip()
        measure = _measure_of(name)
        lowered = name.lower()
        if measure is None:
            continue
        if "round" in lowered:
            factor = 1.0
        elif "width" in lowered:
            factor = 2.0
        else:
            continue  # ambiguous: flat or round? don't guess
        values = row[1:]
        if len(values) != len(sizes):
            continue
        try:
            converted = [float(v) * factor for v in values]
        except (TypeError, ValueError):
            continue
        low, high = PLAUSIBLE_CM[measure]
        if not all(low <= c <= high for c in converted):
            continue
        variant = "_stretched" if "stretch" in lowered else "_relaxed" if "relax" in lowered else ""
        for size, c in zip(sizes, converted):
            if size:
                chart[size][f"{measure}{variant}_cm"] = round(c, 1)
    chart = {s: m for s, m in chart.items() if m}
    return chart or None


async def fetch_chart(client: PoliteClient, shop: str, tag: str) -> list[list[str]] | None:
    """Raw chart rows for one product tag, or None if there is none."""
    res = await client.get(SIZE_CHART_API, params={"shop": shop, "tags": tag}, headers={"Accept": "application/json"})
    if res.status_code != 200:
        return None
    chart = (res.json() or {}).get("size_chart") or {}
    rows = chart.get("size_chart_data")
    if not isinstance(rows, list) or not chart.get("is_active", True):
        return None
    return [[str(c) for c in row] for row in rows if isinstance(row, list)]
