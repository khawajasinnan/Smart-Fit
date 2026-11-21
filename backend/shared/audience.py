"""Adult-only products: SmartFit recommends clothing for men and women 18+.

One rule for every product source (live chat search, catalog import,
recommendation guard). A product is children's wear when its tags, category,
title or link name the children's section, or its sizes are age sizes
("3-4Y", "6-12M"). Word matches are whole words, so adult styles survive:
"boyfriend jeans", "baby pink", "babydoll dress", "girlfriend fit", "mini skirt".
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from urllib.parse import urlparse

# Whole words that mark a children's section in a title, category or link.
_KIDS_WORDS = re.compile(
    r"\b(kids?|kidswear|children|childrens|child|boys|girls|baby\s+(?:boys?|girls?)|babies|infants?|"
    r"newborns?|toddlers?|juniors?|tweens?|teens?|kiddos?)\b"
)
# Tags are labels, so a single word there is a section ("boy", "baby").
_KIDS_TAGS = {"kid", "kids", "boy", "boys", "girl", "girls", "baby", "babies", "infant", "infants",
              "newborn", "toddler", "toddlers", "junior", "juniors", "children", "child", "teen", "teens",
              "kids wear", "kidswear", "boys wear", "girls wear"}
# Children's age sizes: "3-4Y", "3-4 years", "6-12M", "2T", "8Y", "10 yrs".
_AGE_SIZE = re.compile(
    r"^\s*\d{1,2}\s*(?:-|–|to)?\s*\d{0,2}\s*(?:y|yr|yrs|year|years|m|mo|mos|month|months|t)\s*$"
)


def _words(text: str) -> str:
    return re.sub(r"[-_/]+", " ", text.lower())


def is_age_size(size: str) -> bool:
    return bool(_AGE_SIZE.match(size.lower()))


def is_kids_item(
    title: str = "",
    tags: Iterable[str] = (),
    category: str = "",
    product_url: str = "",
    sizes: Iterable[str] = (),
) -> bool:
    """True for children's clothing (never shown to SmartFit's adult users)."""
    tag_list = [t.strip().lower() for t in tags if isinstance(t, str)]
    if any(t in _KIDS_TAGS for t in tag_list):
        return True
    path = urlparse(product_url).path if product_url else ""
    text = " ".join((_words(title), _words(category), _words(path), " ".join(_words(t) for t in tag_list)))
    if _KIDS_WORDS.search(text):
        return True
    size_list = [s for s in sizes if isinstance(s, str) and s.strip()]
    # most sizes are ages: a children's size run (one "10Y" among S/M/L isn't enough)
    return bool(size_list) and sum(is_age_size(s) for s in size_list) * 2 > len(size_list)


def is_adult_product(product: dict) -> bool:
    """For the scraper's product dicts (title, tags, category, product_url, sizes)."""
    return not is_kids_item(
        product.get("title") or "",
        product.get("tags") or [],
        product.get("category") or "",
        product.get("product_url") or "",
        product.get("sizes") or [],
    )
