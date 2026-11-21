"""Parsing of the stylist's hidden product-search trigger.

The model ends a reply with ``[SMARTFIT_SEARCH: {...json...}]`` when it has
enough information to search (see system_prompt.py). The trigger is removed
from the text shown to the user and returned separately so the app can run the
product search (SFR-022).
"""

from __future__ import annotations

import json
import re
from typing import Any

# Complete trigger — same pattern the Flutter app used.
TRIGGER = re.compile(r"\[SMARTFIT_SEARCH:\s*(\{.*?\})\]", re.S)

# The mascot's mood, hidden at the start of a reply (system_prompt.py).
MOODS = ("happy", "excited", "sassy", "confused", "sad", "thinking", "love", "surprised", "proud",
         "wink", "eyeroll", "shrug", "clap", "dance", "hairflip", "cool",
         "vogue", "snap", "strut", "kiss", "selfie", "spin", "facepalm",
         "thumbsup", "nod", "headshake", "bow", "point", "laugh", "yawn", "measure")
MOOD_TAG = re.compile(r"\[MOOD:\s*([A-Za-z]+)\s*\]\s*")
MOOD_FRAGMENT = re.compile(r"\[MOOD[^\]]*$")  # a tag cut off by the token limit

# Truncated / malformed trigger (e.g. the model hit its token limit). Complete
# triggers are removed first, so anything still starting with the marker is
# broken — strip from the marker to the end. (The old Dart pattern used `[^]]`,
# which in Dart means "any character", so it leaked most truncated triggers.)
CLEANUP = re.compile(r"\[SMARTFIT_SEARCH.*$", re.S)
# Any other tag cut off at the very end, even before its name is complete ("[SMARTFIT",
# "[MOOD: ha"): an unclosed bracket of capitals. Seen 20 Nov 2026: a reply ended "[SMARTFIT".
TAG_FRAGMENT = re.compile(r"\[[A-Z][A-Z_]+(?::[^\]]*)?\s*$")

# "Open this screen" button under an app-help answer (system_prompt.py, APP HELP).
# Only these screens: anything else the model writes is dropped, never followed.
SCREENS = ("home", "tryon", "hairstyle", "chat", "wardrobe", "profile", "edit_profile", "help", "privacy")
OPEN_TAG = re.compile(r"\[SMARTFIT_OPEN:\s*([A-Za-z_\- ]+?)\s*\]")
OPEN_FRAGMENT = re.compile(r"\[SMARTFIT_OPEN[^\]]*$")  # cut off by the token limit


def parse_mood(raw: str) -> tuple[str, str | None]:
    """Remove every mood tag; return (text, the first known mood or None)."""
    found = [m.group(1).lower() for m in MOOD_TAG.finditer(raw)]
    mood = next((m for m in found if m in MOODS), None)
    text = MOOD_FRAGMENT.sub("", MOOD_TAG.sub("", raw))
    return text, mood


def parse_open(raw: str) -> tuple[str, str | None]:
    """Remove every open-screen tag; return (text, the first allowed screen or None)."""
    found = [m.group(1).strip().lower().replace("-", "_").replace(" ", "_") for m in OPEN_TAG.finditer(raw)]
    screen = next((f for f in found if f in SCREENS), None)
    text = OPEN_FRAGMENT.sub("", OPEN_TAG.sub("", raw))
    return text.rstrip(), screen


def parse_reply(raw: str) -> tuple[str, dict[str, Any] | None, str | None]:
    """Split a model reply into (display_text, parsed_search, raw_search_json).
    Mood and open-screen tags are removed too; use parse_mood() / parse_open() to read them."""
    raw, _ = parse_mood(raw)
    raw, _ = parse_open(raw)
    match = TRIGGER.search(raw)
    search_raw = match.group(1) if match else None

    search: dict[str, Any] | None = None
    if search_raw is not None:
        try:
            parsed = json.loads(search_raw)
            search = parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            search = None

    display = TRIGGER.sub("", raw)
    display = CLEANUP.sub("", display).strip()
    display = TAG_FRAGMENT.sub("", display).strip()
    return display, search, search_raw
