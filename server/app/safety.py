"""Last-line checks on what the model says, before the app reads it aloud.

The prompts already forbid these claims. This catches the cases where a
model ignores the prompt, and keeps replies speakable.
"""

import json
import re

from .schemas import PHASE_ACTIONS, Action, AskRequest, CheckStatus, StepChange

_CLAIM_VERB = r"(?:\bis|\bare|'s|'re|\blooks?|\bseems?)"
_CERTAINLY = r"(?:\s+(?:fully|properly|thoroughly|completely|definitely|totally))?"

# Claims the app must never make: food is cooked or safe, or allergy-safe.
_COOKED = [
    re.compile(p, re.IGNORECASE)
    for p in [
        rf"{_CLAIM_VERB}{_CERTAINLY}\s+(?:cooked\s+through|safe\s+to\s+eat|safe\s+for\s+you)",
        rf"{_CLAIM_VERB}\s+(?:fully|properly|thoroughly|completely)\s+cooked\b",
        r"\bno\s+risk\s+of\s+food\s+poisoning\b",
    ]
]
_ALLERGY = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"\bsafe\s+for\s+(?:your|an?|people\s+with)?\s*\w*\s*allerg",
        r"\b(?:allergy|allergen)[-\s](?:safe|free)\b",
    ]
]

# A claim in the same clause as one of these is a caveat, not a claim:
# "a photo can't confirm that chicken is cooked through" is what we want.
_NEGATION = re.compile(
    r"\b(?:can't|cannot|can\s+not|couldn't|won't|not|never|unable|don't|doesn't|"
    r"no\s+way|impossible|whether|if)\b",
    re.IGNORECASE,
)

COOKED_FALLBACK = (
    "A photo can't tell me whether food is cooked through or safe, "
    "so please check it yourself before you eat."
)
ALLERGY_FALLBACK = (
    "I can't confirm anything is safe for an allergy, "
    "so please check the labels yourself."
)

# Match start announcements, while leaving quoted instructions, questions
# and conditional invitations in the opening chat.
_OPENING_START = re.compile(
    r"(?:^|[,;:]\s*)(?:let'?s\s+(?:start|begin|cook|get\s+(?:started|cooking))"
    r"|we(?:'re|\s+are)\s+(?:starting|beginning)"
    r"|i(?:'ll|\s+will)\s+(?:start|begin))\b",
    re.IGNORECASE,
)
_DEFERRED_START = re.compile(
    r"\b(?:say|tell|when|whenever|once|if|before|after|until|unless|"
    r"not|don't|never|can't|cannot|won't)\b|\?",
    re.IGNORECASE,
)


def _claims(sentence: str, patterns: list[re.Pattern]) -> bool:
    for clause in re.split(r"[,;:—–]|\bbut\b|\bthough\b|\balthough\b", sentence):
        for pattern in patterns:
            match = pattern.search(clause)
            if match and not _NEGATION.search(clause[: match.start()]):
                return True
    return False


def make_safe(text: str) -> tuple[str, bool]:
    """Drop sentences that claim food is cooked or allergy-safe.

    Returns speakable text and whether anything was replaced. Other
    sentences, such as a description of what the photo shows, are kept.
    """
    text = _speakable(text)
    out: list[str] = []
    replaced = False
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if _claims(sentence, _ALLERGY):
            sentence, replaced = ALLERGY_FALLBACK, True
        elif _claims(sentence, _COOKED):
            sentence, replaced = COOKED_FALLBACK, True
        # The fallback replaces the claim in place, once.
        if sentence and sentence not in out:
            out.append(sentence)
    return " ".join(out), replaced


def _speakable(text: str) -> str:
    # The reply is read aloud, so drop markdown symbols and list markers.
    text = re.sub(r"[*#`>]+|(?<!\w)_+|_+(?!\w)", "", text)
    text = re.sub(r"^\s*([-•]|\d+\.)\s+", "", text, flags=re.MULTILINE)
    return " ".join(text.split())


def _json_object(raw: str) -> dict:
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        return {}
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


UNCLEAR_SAY = (
    "I couldn't get a clear answer from that photo. "
    "Try holding the camera a little closer and ask me again."
)


def parse_check(raw: str) -> tuple[CheckStatus, str]:
    """Read the model's JSON verdict. Anything malformed becomes "unsure"."""
    data = _json_object(raw)
    status = data.get("status")
    say = data.get("say")
    if status not in ("done", "not_yet", "unsure") or not isinstance(say, str) or not say.strip():
        return "unsure", UNCLEAR_SAY

    say, replaced = make_safe(say)
    # A replaced claim means the model judged doneness or safety; never
    # report that as "done".
    return ("unsure" if replaced else status), say


def parse_ask(raw: str, req: AskRequest) -> tuple[str, Action | None, Action | None]:
    """Read {"reply", "offer", "action"} from the model.

    A reply that isn't JSON is used as plain text. Offers and actions that
    don't fit the phase or the request are dropped, never passed to the app.
    """
    data = _json_object(raw)
    if data:
        reply = data.get("reply")
    elif raw.lstrip().startswith("{"):
        # JSON that was cut off: keep the reply text if it got that far.
        reply = _partial_reply(raw)
    else:
        reply = raw
    if not isinstance(reply, str):
        reply = ""
    reply, _ = make_safe(reply)

    offer = _valid_action(data.get("offer"), req)
    action = _valid_action(data.get("action"), req)
    if req.phase == "opening" and action is None:
        sentences = re.split(r"(?<=[.!?])\s+", reply.replace("\u2019", "'"))
        if any(_OPENING_START.search(s) and not _DEFERRED_START.search(s) for s in sentences):
            action = Action(type="start_cooking")
            offer = None
    return reply, offer, action


def _partial_reply(raw: str) -> str:
    match = re.search(r'"reply"\s*:\s*"((?:[^"\\]|\\.)*)', raw)
    if not match:
        return ""
    try:
        text = json.loads(f'"{match.group(1)}"')
    except json.JSONDecodeError:
        text = match.group(1)
    # Drop an unfinished last sentence rather than speak half of it.
    whole = re.match(r"^(.*[.!?])", text, re.DOTALL)
    return whole.group(1) if whole else ""


def _valid_action(value: object, req: AskRequest) -> Action | None:
    if not isinstance(value, dict):
        return None
    try:
        action = Action.model_validate(value)
    except ValueError:
        return None
    if action.type not in PHASE_ACTIONS[req.phase]:
        return None

    if action.type == "start_timer":
        if action.seconds is None:
            return None
        return Action(type="start_timer", seconds=action.seconds, label=action.label or "Timer")
    if action.type == "tick_ingredient":
        # Only ingredients the app sent, spelled the way the app spells them.
        by_lower = {i.name.lower(): i.name for i in req.ingredients}
        asked = [action.name or ""] + list(action.names or [])
        names = list(dict.fromkeys(
            by_lower[n.strip().lower()] for n in asked if n.strip().lower() in by_lower
        ))
        return Action(type="tick_ingredient", name=names[0], names=names) if names else None
    if action.type == "adapt_steps":
        steps = _valid_step_changes(action, req)
        return Action(type="adapt_steps", steps=steps) if steps else None
    if action.type == "custom_swap":
        return _valid_custom_swap(action, req)
    return Action(type=action.type)


def _valid_custom_swap(action: Action, req: AskRequest) -> Action | None:
    """The cook's own swap needs a name and a verdict. Steps change only
    when it is both healthier and fits the dish."""
    swap = (action.swap or "").strip()
    if not swap or action.healthier is None or action.fits is None:
        return None
    steps = _valid_step_changes(action, req) if action.healthier and action.fits else None
    return Action(
        type="custom_swap",
        swap=swap,
        healthier=action.healthier,
        fits=action.fits,
        steps=steps or None,
    )


# Oil doesn't boil; long before that it smokes and can catch fire (#94).
_BRING_OIL_TO_BOIL = re.compile(r"\bbring\s+(the\s+)?oil\s+to\s+(?:a\s+)?boil\b", re.IGNORECASE)
_BOIL_OIL = re.compile(r"\bboil(?:ing)?(?=\s+(?:the\s+|some\s+|a\s+little\s+)?oil\b)", re.IGNORECASE)


def _step_text(text: str | None) -> str:
    """New step text, as it will be read aloud."""
    text, _ = make_safe((text or "").strip())
    def warm(m: re.Match, rest: str = "") -> str:
        return ("Warm" if m[0][0].isupper() else "warm") + rest

    text = _BRING_OIL_TO_BOIL.sub(lambda m: warm(m, f" {m[1] or ''}oil"), text)
    return _BOIL_OIL.sub(warm, text)


def _valid_step_changes(action: Action, req: AskRequest) -> list[StepChange]:
    """Keeps changes to steps the app sent that really change them. The new
    text is read aloud later, so it gets the same safety pass as replies.
    Removing every step is not a change the app can cook from."""
    changes: dict[int, StepChange] = {}
    for change in action.steps or []:
        if change.step >= len(req.steps):
            continue
        old = req.steps[change.step]
        if change.remove:
            changes[change.step] = StepChange(step=change.step, remove=True)
            continue
        text = _step_text(change.text)
        title = _step_text(change.title) or None
        check = _step_text(change.check) or None
        if not text:
            continue
        if text == old.text.strip() and title in (None, old.title) and check in (None, old.check):
            continue
        changes[change.step] = StepChange(
            step=change.step,
            text=text,
            title=title if title != old.title else None,
            check=check if check != old.check else None,
        )
    if changes and all(c.remove for c in changes.values()) and len(changes) == len(req.steps):
        return []
    return [changes[i] for i in sorted(changes)]
