"""Chat orchestrator: trigger parsing and Gemini request building (no network)."""

from shared.schemas.chat import ChatRequest, ChatTurn
from services.chat_orchestrator.gemini_client import (
    EMPTY_REPLY_FALLBACK,
    build_contents,
    build_prompt_text,
    extract_text,
)
from services.chat_orchestrator.system_prompt import SYSTEM_PROMPT
from services.chat_orchestrator.tools import parse_reply


def test_complete_trigger_is_extracted_and_hidden():
    raw = (
        "Yeh outfit aap par acha lagega!\n"
        '[SMARTFIT_SEARCH: {"occasion": "eid", "garment": "shalwar kameez", '
        '"colors": ["black", "white"], "budget_max": 8000, "size": null}]'
    )
    display, search, search_raw = parse_reply(raw)
    assert display == "Yeh outfit aap par acha lagega!"
    assert search == {
        "occasion": "eid",
        "garment": "shalwar kameez",
        "colors": ["black", "white"],
        "budget_max": 8000,
        "size": None,
    }
    assert search_raw.startswith('{"occasion"') and search_raw.endswith("null}")


def test_no_trigger_returns_text_only():
    display, search, search_raw = parse_reply("Kis occasion ke liye chahiye?")
    assert display == "Kis occasion ke liye chahiye?"
    assert search is None and search_raw is None


def test_truncated_trigger_never_leaks_into_display():
    # The model hit its token limit mid-trigger: the whole fragment must go.
    raw = 'Main search karti hoon.\n[SMARTFIT_SEARCH: {"occasion": "wedding", "garment": "sher'
    display, search, search_raw = parse_reply(raw)
    assert display == "Main search karti hoon."
    assert search is None and search_raw is None


def test_truncated_trigger_containing_an_array_is_also_removed():
    raw = 'Theek hai!\n[SMARTFIT_SEARCH: {"colors": ["black"], "garment": "pent co'
    display, search, _ = parse_reply(raw)
    assert display == "Theek hai!"
    assert search is None


def test_invalid_json_keeps_raw_but_no_parsed_search():
    display, search, search_raw = parse_reply("Done [SMARTFIT_SEARCH: {not json}]")
    assert display == "Done"
    assert search is None
    assert search_raw == "{not json}"


def test_prompt_text_matches_former_app_layout():
    req = ChatRequest(message="black kurta", profile_context="gender: male", chat_context="User: hi")
    assert build_prompt_text(req) == (
        "User profile context:\ngender: male\n\nCurrent chat session context:\nUser: hi\n\nblack kurta"
    )
    assert build_prompt_text(ChatRequest(message="hi")) == "hi"


def test_contents_keep_last_16_history_turns_then_current_turn():
    history = [ChatTurn(role="user" if i % 2 == 0 else "model", text=f"t{i}") for i in range(30)]
    contents = build_contents(ChatRequest(message="now", history=history))
    assert len(contents) == 17
    assert contents[0]["parts"][0]["text"] == "t14"
    assert contents[-1] == {"role": "user", "parts": [{"text": "now"}]}


def test_extract_text_skips_thought_parts_and_handles_empty():
    data = {"candidates": [{"content": {"parts": [{"text": "hidden", "thought": True}, {"text": "Hello"}]}}]}
    assert extract_text(data) == "Hello"
    assert extract_text({"candidates": []}) == ""
    assert EMPTY_REPLY_FALLBACK


def test_system_prompt_is_intact():
    assert SYSTEM_PROMPT.startswith("You are SmartFit AI Stylist")
    assert "[SMARTFIT_SEARCH: {" in SYSTEM_PROMPT
    assert "Keep your conversational text to 1-2 sentences before the trigger\n" in SYSTEM_PROMPT
    assert "[MOOD: one of happy, excited, sassy, confused, sad, thinking, love, surprised, proud, wink, eyeroll, shrug, clap, dance, hairflip, cool, vogue, snap, strut, kiss, selfie, spin, facepalm, thumbsup, nod, headshake, bow, point, laugh, yawn, measure]" in SYSTEM_PROMPT
    assert "Your name is Zayn" in SYSTEM_PROMPT and "karti hoon" not in SYSTEM_PROMPT


# ── Mascot mood tag ─────────────────────────────────────────────────────────

from fastapi.testclient import TestClient  # noqa: E402

import services.chat_orchestrator.main as chat_main  # noqa: E402
from services.chat_orchestrator.tools import parse_mood  # noqa: E402


def test_mood_tag_is_read_and_hidden():
    text, mood = parse_mood("[MOOD: sassy]\nDarling, yeh color aap par kamaal lagega!")
    assert mood == "sassy" and text == "Darling, yeh color aap par kamaal lagega!"
    display, search, _ = parse_reply('[MOOD: excited] Great picks! [SMARTFIT_SEARCH: {"garment": "kurta"}]')
    assert display == "Great picks!" and search == {"garment": "kurta"}


def test_unknown_mood_or_none_gives_no_mood_and_never_leaks():
    assert parse_mood("[MOOD: furious] Hello")[1] is None
    assert parse_mood("Hello")[1] is None
    text, _ = parse_mood("Sure, main dhoond rahi hoon. [MOOD: thin")  # cut off by the token limit
    assert "[MOOD" not in text
    assert "[MOOD" not in parse_reply("[MOOD: HAPPY] Done")[0]
    assert parse_mood("[MOOD: HAPPY] Done")[1] == "happy"


def test_chat_endpoint_returns_the_mood(monkeypatch):
    async def fake_reply(_client, _req):
        return "[MOOD: love]\nYeh lehenga bohot pyara hai!"

    monkeypatch.setattr(chat_main, "generate_reply", fake_reply)
    with TestClient(chat_main.app) as c:
        body = c.post("/chat", json={"message": "lehenga for my wedding"}).json()
    assert body["mood"] == "love" and body["reply"] == "Yeh lehenga bohot pyara hai!"


# ── App help: "open this screen" button (system_prompt.py, APP HELP) ─────────

from services.chat_orchestrator.tools import SCREENS, parse_open  # noqa: E402


def test_open_tag_is_read_and_hidden():
    raw = '[MOOD: happy]\nNo problem! 1. Tap the "Try-On" tab.\n[SMARTFIT_OPEN: tryon]'
    assert parse_open(raw)[1] == "tryon"
    display, search, _ = parse_reply(raw)
    assert display == 'No problem! 1. Tap the "Try-On" tab.' and search is None
    assert parse_open("[SMARTFIT_OPEN: Edit-Profile]")[1] == "edit_profile"  # spelling variants


def test_only_known_screens_are_opened_and_tags_never_leak():
    assert parse_open("Go here [SMARTFIT_OPEN: https://evil.example]")[1] is None
    assert parse_open("Go here [SMARTFIT_OPEN: admin]")[1] is None  # not a shopper screen
    text, screen = parse_open("Tap the Hair tab. [SMARTFIT_OPEN: hairst")  # cut off by the token limit
    assert screen is None and "[SMARTFIT_OPEN" not in text
    assert "[SMARTFIT_OPEN" not in parse_reply("Done [SMARTFIT_OPEN: nowhere]")[0]
    assert set(SCREENS) == {"home", "tryon", "hairstyle", "chat", "wardrobe", "profile", "edit_profile", "help",
                            "privacy"}


def test_every_screen_the_prompt_offers_is_allowed():
    import re

    offered = set(re.findall(r"open-screen value: ([a-z_]+)", SYSTEM_PROMPT))
    listed = re.search(r"Allowed values only: ([a-z_, ]+)\.", SYSTEM_PROMPT).group(1)
    assert offered and offered <= set(SCREENS)
    assert {v.strip() for v in listed.split(",")} == set(SCREENS)


def test_app_help_rules_are_in_the_prompt():
    assert "## APP HELP: HOW TO USE SMARTFIT" in SYSTEM_PROMPT
    assert "There are NO silly questions" in SYSTEM_PROMPT
    assert "NEVER add [SMARTFIT_SEARCH] to a help answer" in SYSTEM_PROMPT
    # the bottom bar exactly as the app shows it (frontend sf_bottom_nav_bar.dart)
    assert '"Home", "Try-On", "Hair", "Stylist"' in SYSTEM_PROMPT and '"Saved", "Profile"' in SYSTEM_PROMPT


def test_chat_endpoint_returns_the_screen(monkeypatch):
    replies = iter([
        '[MOOD: point]\n1. Tap the "Try-On" tab at the bottom.\n[SMARTFIT_OPEN: tryon]',
        # a product answer never carries a screen button, even if the model adds one
        '[MOOD: excited] Dhoond raha hoon! [SMARTFIT_OPEN: tryon]\n[SMARTFIT_SEARCH: {"garment": "kurta"}]',
        "[MOOD: happy] Hello!",
    ])

    async def fake_reply(_client, _req):
        return next(replies)

    monkeypatch.setattr(chat_main, "generate_reply", fake_reply)
    with TestClient(chat_main.app) as c:
        help_ = c.post("/chat", json={"message": "I can't find the virtual try-on"}).json()
        shop = c.post("/chat", json={"message": "kurta for eid"}).json()
        hello = c.post("/chat", json={"message": "hi"}).json()
    assert help_["open"] == "tryon" and help_["reply"] == '1. Tap the "Try-On" tab at the bottom.'
    assert shop["open"] is None and shop["search"] == {"garment": "kurta"} and "SMARTFIT" not in shop["reply"]
    assert hello["open"] is None


def test_a_tag_cut_off_before_its_name_ends_never_shows():
    """20 Nov 2026 (E2E run): a reply ended with "[SMARTFIT" and the stub was shown."""
    reply = "Main aapke liye best options find karta hoon, any colour.\n[SMARTFIT"
    display, search, _ = parse_reply(reply)
    assert display == "Main aapke liye best options find karta hoon, any colour." and search is None
    for cut in ("[SMARTF", "[SMARTFIT_SE", "[SMARTFIT_SEARCH", "[MOOD", "[SMARTFIT_OPEN: try"):
        assert "[" not in parse_reply(f"Done. {cut}")[0], cut
    # ordinary brackets in a reply stay
    assert parse_reply("Sizes [S, M, L] are in stock")[0] == "Sizes [S, M, L] are in stock"
    assert parse_reply("Try the [Lawn] edit")[0] == "Try the [Lawn] edit"


def test_thinking_cannot_crowd_out_the_reply():
    """Gemini 2.5 counts thinking tokens in maxOutputTokens: the reply always keeps ~2000."""
    from services.chat_orchestrator.gemini_client import GENERATION_CONFIG, THINKING_BUDGET

    assert GENERATION_CONFIG["thinkingConfig"] == {"thinkingBudget": THINKING_BUDGET}
    assert GENERATION_CONFIG["maxOutputTokens"] - THINKING_BUDGET >= 2000


def test_a_cut_off_reply_still_returns_its_text():
    data = {"candidates": [{"finishReason": "MAX_TOKENS", "content": {"parts": [{"text": "Partial answer"}]}}],
            "usageMetadata": {"thoughtsTokenCount": 1100, "candidatesTokenCount": 90}}
    assert extract_text(data) == "Partial answer"
