"""Size / fit check (SFR-025), shared by the recommendation and try-on services
so a product that "doesn't fit" in the recommendations can't be tried on either.

Body measurements are circumferences in cm from the user's profile
(chest_cm, waist_cm, hip_cm). A garment fits when it is at least the body
measurement plus the minimum room (ease) that part of the body needs.
"""

from __future__ import annotations

from dataclasses import dataclass

from shared.schemas.catalog import ScrapedProduct
from shared.size_estimate import letter_sizes, same_size, size_kind

LETTER_SIZES = {"XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL", "2XL", "3XL", "4XL", "XXXXL"}
ONE_SIZE = {"FREE", "FREE SIZE", "ONE SIZE", "OS"}
# Minimum extra room (cm) a garment needs over the body measurement to count
# as fitting: chest needs movement room, denim waists stretch, hips a little.
MIN_EASE_CM = {"chest_cm": 4.0, "waist_cm": 0.0, "hip_cm": 2.0}
# More room than this and we still recommend the size but say it may be loose.
LOOSE_EASE_CM = {"chest_cm": 30.0, "waist_cm": 12.0, "hip_cm": 20.0}

# The user's own clothes (try-on): which flat tape measurements each kind of
# garment needs. A flat width x 2 = the garment's circumference.
OWN_GARMENT_MEASURES = {"upper": ("chest_cm",), "lower": ("waist_cm",), "dress": ("chest_cm", "waist_cm")}
FLAT_WIDTH_RANGE_CM = (15.0, 120.0)  # anything outside is a typo, not a garment


@dataclass(frozen=True)
class SizeFit:
    """compatible: True = a fitting size is in stock; False = it isn't (or
    nothing fits); None = can't tell (no chart/measurements and the product
    uses a different size system), so the product is shown, not hidden.

    verdict says how the garment sits on this body, which is what the try-on
    shows the user: "fits" | "small" | "big" | "unknown". It is about the body,
    not about stock — a garment in the right size that happens to be sold out
    is still "fits"."""

    compatible: bool | None
    recommended_size: str | None
    basis: str  # "size_chart" | "label" | "measurements" | "unknown"
    note: str = ""
    verdict: str = "unknown"


def _label(m: str) -> str:
    return m.removesuffix("_cm")


def _capacity_and_rest(row: dict[str, float], m: str) -> tuple[float | None, float | None, bool]:
    """(largest body it fits, garment size at rest, stretch?) for measure m.
    Elastic waists: capacity = stretched, at rest = relaxed."""
    base = m.removesuffix("_cm")
    stretched, relaxed = row.get(f"{base}_stretched_cm"), row.get(f"{base}_relaxed_cm")
    plain = row.get(m)
    if stretched is not None:
        return stretched, relaxed if relaxed is not None else plain, True
    rest = plain if plain is not None else relaxed
    return rest, rest, False


def clean_body(body: dict[str, float | None]) -> dict[str, float]:
    """Only the measurements the user actually has (positive numbers)."""
    out = {}
    for key in ("chest_cm", "waist_cm", "hip_cm"):
        try:
            value = float(body.get(key) or 0)
        except (TypeError, ValueError):
            continue
        if value > 0:
            out[key] = value
    return out


def fit_from_chart(product: ScrapedProduct, body: dict[str, float]) -> SizeFit | None:
    """Product-specific chart vs the user's body measurements, or None when
    the chart and the measurements have nothing in common."""
    chart = product.size_chart or {}
    measures = [m for m in body if any(_capacity_and_rest(row, m)[0] is not None for row in chart.values())]
    if not measures:
        return None
    for size, row in chart.items():  # chart order = smallest -> largest
        fits = True
        loose = []
        for m in measures:
            capacity, rest, stretch = _capacity_and_rest(row, m)
            if capacity is None or capacity < body[m] + (0.0 if stretch else MIN_EASE_CM[m]):
                fits = False
                break
            if rest is not None and rest - body[m] > LOOSE_EASE_CM[m]:
                loose.append(m)
        if not fits:
            continue
        note = f"Size {size} from this product's size chart"
        if loose:
            note += f"; may fit loose at the {', '.join(_label(m) for m in loose)}"
        in_stock = size.strip().upper() in {s.strip().upper() for s in product.sizes}
        if not in_stock:
            note = f"Your size here is {size}, which is out of stock"
        return SizeFit(in_stock, size, "size_chart", note, "big" if loose else "fits")
    return SizeFit(False, None, "size_chart",
                   f"Even the largest size is smaller than your {', '.join(_label(m) for m in measures)}",
                   "small")


def size_fit(product: ScrapedProduct, letter_size: str | None, body: dict[str, float]) -> SizeFit:
    """Never converts between size systems without the product's own chart.

    Store labels are read with size_estimate.letter_sizes ("L (14)", "X-Large",
    "S-M", "XL RGF" ...; 21 Nov 2026: a plain comparison missed most of them),
    and the recommended size is the product's OWN label for the user's size."""
    stock = [s.strip().upper() for s in product.sizes]
    if set(stock) & ONE_SIZE or any(size_kind(s) == "one" for s in product.sizes):
        return SizeFit(True, product.sizes[0], "label", "One size", "fits")
    custom = next((s for s in product.sizes if size_kind(s) == "custom"), None)
    if custom:
        return SizeFit(True, custom, "label", "Made to your measurements", "fits")
    chart_fit = fit_from_chart(product, body)
    if chart_fit is not None:
        return chart_fit
    in_stock: dict[str, str] = {}  # letter size -> the store's own label for it
    for label in product.sizes:
        for letter in letter_sizes(label):
            in_stock.setdefault(letter, label)
    made = {letter for label in (product.all_sizes or product.sizes) for letter in letter_sizes(label)} | set(in_stock)
    if letter_size and made:
        wanted = next(iter(letter_sizes(letter_size)), same_size(letter_size))
        ok = wanted in in_stock
        if ok:
            return SizeFit(True, in_stock[wanted], "label", "", "fits")
        # the label is their size; stock is a shop problem, not a fit problem
        note = f"Size {wanted} is out of stock" if wanted in made else f"Not made in size {wanted}"
        return SizeFit(False, wanted, "label", note, "unknown")
    if not letter_size and not body:
        return SizeFit(None, None, "unknown", "")
    shown = ", ".join(product.sizes) or "none in stock"
    return SizeFit(None, None, "unknown",
                   f"Sold in sizes {shown}; no size chart to match against your measurements")


def own_garment_fit(category: str, flat_widths_cm: dict[str, float], body: dict[str, float]) -> SizeFit:
    """The user's own clothes, measured flat with a tape, vs their body.

    flat_widths_cm: {"chest_cm": 52, "waist_cm": 40} = straight across the
    garment laid flat; x2 = its circumference. Raises ValueError (a message for
    the user) when a needed measurement is missing on either side."""
    needed = OWN_GARMENT_MEASURES[category]
    missing_garment = [m for m in needed if not flat_widths_cm.get(m)]
    if missing_garment:
        raise ValueError(f"Please enter the garment's {' and '.join(_label(m) for m in missing_garment)} width.")
    missing_body = [m for m in needed if m not in body]
    if missing_body:
        raise ValueError(f"Add your {' and '.join(_label(m) for m in missing_body)} measurement in your profile "
                         "first, so we can check the fit.")
    too_small, loose, parts = [], [], []
    for m in needed:
        garment = round(flat_widths_cm[m] * 2, 1)
        room = garment - body[m]
        parts.append(f"{_label(m)} {garment:g} cm on you {body[m]:g} cm")
        if room < MIN_EASE_CM[m]:
            too_small.append((m, garment))
        elif room > LOOSE_EASE_CM[m]:
            loose.append(m)
    if too_small:
        what = ", ".join(f"{_label(m)} ({g:g} cm around, you need at least {body[m] + MIN_EASE_CM[m]:g} cm)"
                         for m, g in too_small)
        return SizeFit(False, None, "measurements", f"Too small at the {what}", "small")
    note = "; ".join(parts)
    note = note[:1].upper() + note[1:]  # "Chest 110 cm on you 96 cm"
    if loose:
        note += f". Loose at the {', '.join(_label(m) for m in loose)}"
    return SizeFit(True, None, "measurements", note, "big" if loose else "fits")
