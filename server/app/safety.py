"""Last-line checks on what the model says, before the app reads it aloud.

The prompts already forbid these claims. This catches the cases where a
model ignores the prompt, and keeps replies speakable.
"""

import json
import re

from .schemas import CheckStatus

# Claims the app must never make: food is cooked or safe, or allergy-safe.
_FORBIDDEN = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"\b(is|are|looks?|seems?)\s+(fully\s+|properly\s+|thoroughly\s+)?"
        r"(cooked\s+through|safe\s+to\s+eat|safe\s+for\s+you)",
        r"\bsafe\s+for\s+(your|an?|people\s+with)?\s*\w*\s*allerg",
        r"\b(allergy|allergen)[-\s](safe|free)\b",
        r"\bno\s+risk\s+of\s+food\s+poisoning\b",
    ]
]

COOKED_FALLBACK = (
    "I can't tell from a photo whether food is cooked through or safe, "
    "so please check it yourself before you eat."
)
ALLERGY_FALLBACK = (
    "I can't confirm anything is safe for an allergy, "
    "so please check the labels yourself."
)


def make_safe(text: str) -> tuple[str, bool]:
    """Return speakable text and whether a forbidden claim was replaced."""
    for pattern in _FORBIDDEN:
        if pattern.search(text):
            fallback = ALLERGY_FALLBACK if "allerg" in pattern.pattern else COOKED_FALLBACK
            return fallback, True
    return _speakable(text), False


def _speakable(text: str) -> str:
    # The reply is read aloud, so drop markdown symbols and list markers.
    text = re.sub(r"[*_#`>]+", "", text)
    text = re.sub(r"^\s*([-•]|\d+\.)\s+", "", text, flags=re.MULTILINE)
    return " ".join(text.split())


UNCLEAR_SAY = (
    "I couldn't get a clear answer from that photo. "
    "Try holding the camera a little closer and ask me again."
)


def parse_check(raw: str) -> tuple[CheckStatus, str]:
    """Read the model's JSON verdict. Anything malformed becomes "unsure"."""
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    try:
        data = json.loads(match.group(0)) if match else {}
    except json.JSONDecodeError:
        data = {}

    status = data.get("status")
    say = data.get("say")
    if status not in ("done", "not_yet", "unsure") or not isinstance(say, str) or not say.strip():
        return "unsure", UNCLEAR_SAY

    say, replaced = make_safe(say)
    # A replaced claim means the model judged doneness or safety; never
    # report that as "done".
    return ("unsure" if replaced else status), say
