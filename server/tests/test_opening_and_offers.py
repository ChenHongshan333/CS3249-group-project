"""The opening conversation, offers and actions (docs/api.md, /ask)."""

import json

import pytest

from app.safety import COOKED_FALLBACK, make_safe
from conftest import ASK_BODY

TIMER = {"type": "start_timer", "seconds": 60, "label": "Pasta"}

OPENING_BODY = {
    "sessionId": "a1b2c3",
    "recipeId": "chicken-chop",
    "recipeName": "Chicken chop with tomato pasta",
    "phase": "opening",
    "question": "I don't have cherry tomatoes.",
    "ingredients": [
        {"name": "chicken thigh", "ready": True},
        {"name": "cherry tomatoes", "ready": False},
        {"name": "garlic", "ready": False},
    ],
}


def reply_json(**fields) -> str:
    return json.dumps({"reply": "Okay.", "offer": None, "action": None, **fields})


# Backwards compatibility


def test_plain_reply_has_no_extra_fields(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="About one centimetre.")
    assert client.post("/ask", json=ASK_BODY).json() == {"reply": "About one centimetre."}


def test_plain_text_from_the_model_still_works(client, fake_llm):
    fake_llm.next_reply = "Just plain text."
    assert client.post("/ask", json=ASK_BODY).json() == {"reply": "Just plain text."}


def test_cooking_still_needs_step_text(client):
    res = client.post("/ask", json={**ASK_BODY, "stepText": ""})
    assert res.status_code == 400


# Offers and actions


def test_offer_is_returned(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="Would you like a one-minute timer?", offer=TIMER)
    body = client.post("/ask", json=ASK_BODY).json()
    assert body["offer"] == TIMER
    assert "action" not in body


def test_pending_offer_is_in_the_prompt(client, fake_llm):
    client.post("/ask", json={**ASK_BODY, "question": "Please.", "pendingOffer": TIMER})
    text = fake_llm.calls[0]["text"]
    assert "Your last reply offered a 60-second timer" in text
    assert '"seconds":60' in text


def test_accepted_offer_becomes_action(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="One-minute timer started.", action=TIMER)
    body = client.post("/ask", json={**ASK_BODY, "question": "Please.", "pendingOffer": TIMER})
    assert body.json()["action"] == TIMER


def test_timer_without_seconds_is_dropped(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "start_timer", "label": "Pasta"})
    assert "action" not in client.post("/ask", json=ASK_BODY).json()


def test_timer_longer_than_an_hour_is_dropped(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "start_timer", "seconds": 99999})
    assert "action" not in client.post("/ask", json=ASK_BODY).json()


def test_unknown_action_is_dropped(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "order_pizza"})
    assert "action" not in client.post("/ask", json=ASK_BODY).json()


def test_opening_actions_are_not_allowed_while_cooking(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "start_cooking"})
    assert "action" not in client.post("/ask", json=ASK_BODY).json()


def test_bad_pending_offer_is_rejected(client):
    res = client.post("/ask", json={**ASK_BODY, "pendingOffer": {"type": "order_pizza"}})
    assert res.status_code == 400


# The opening conversation


def test_opening_uses_its_own_prompt_and_context(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="No problem, it works without them.")
    res = client.post("/ask", json=OPENING_BODY)
    assert res.status_code == 200
    call = fake_llm.calls[0]
    assert "short chat before step 1" in call["system"]
    assert "Ingredients already ticked: chicken thigh" in call["text"]
    assert "Ingredients not ticked yet: cherry tomatoes, garlic" in call["text"]


def test_opening_needs_no_step_text(client, fake_llm):
    assert "stepText" not in OPENING_BODY
    assert client.post("/ask", json=OPENING_BODY).status_code == 200


def test_opening_start_cooking(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="Lovely, let's start.", action={"type": "start_cooking"})
    body = client.post("/ask", json={**OPENING_BODY, "question": "That's everything."}).json()
    assert body == {"reply": "Lovely, let's start.", "action": {"type": "start_cooking"}}


@pytest.mark.parametrize("reply", [
    "Lovely, let's start.",
    "Great! Let’s get cooking.",
    "We're starting now.",
    "I'll start cooking now.",
])
def test_opening_start_announcement_gets_missing_action(client, fake_llm, reply):
    fake_llm.next_reply = reply_json(reply=reply)
    body = client.post("/ask", json={**OPENING_BODY, "question": "I have everything"}).json()
    assert body == {"reply": reply, "action": {"type": "start_cooking"}}


@pytest.mark.parametrize("reply", [
    "Say 'let's start' when you're ready.",
    "When you're ready, let's start.",
    "Shall we start cooking?",
    "Let's start once you have the garlic.",
    "Don't start cooking yet.",
])
def test_opening_does_not_start_for_invitations_or_conditions(client, fake_llm, reply):
    fake_llm.next_reply = reply_json(reply=reply)
    assert "action" not in client.post("/ask", json=OPENING_BODY).json()


def test_start_announcement_does_not_start_during_cooking(client, fake_llm):
    fake_llm.next_reply = reply_json(reply="Let's start cooking.")
    assert "action" not in client.post("/ask", json=ASK_BODY).json()


def test_tick_ingredient_uses_the_apps_spelling(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "tick_ingredient", "name": "Garlic "})
    body = client.post("/ask", json={**OPENING_BODY, "question": "Found the garlic."}).json()
    assert body["action"] == {"type": "tick_ingredient", "name": "garlic", "names": ["garlic"]}


def test_tick_several_ingredients_at_once(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={"type": "tick_ingredient", "names": ["Cherry tomatoes", "garlic", "saffron"]}
    )
    body = client.post("/ask", json={**OPENING_BODY, "question": "Got both now."}).json()
    # Unknown names are dropped; "name" keeps older apps working.
    assert body["action"] == {
        "type": "tick_ingredient",
        "name": "cherry tomatoes",
        "names": ["cherry tomatoes", "garlic"],
    }


def test_tick_unknown_ingredient_is_dropped(client, fake_llm):
    fake_llm.next_reply = reply_json(action={"type": "tick_ingredient", "name": "saffron"})
    assert "action" not in client.post("/ask", json=OPENING_BODY).json()


def test_cooking_actions_are_not_allowed_in_the_opening(client, fake_llm):
    fake_llm.next_reply = reply_json(action=TIMER)
    assert "action" not in client.post("/ask", json=OPENING_BODY).json()


def test_opening_end_can_be_logged(client):
    res = client.post(
        "/log",
        json={"sessionId": "a1", "type": "opening_end", "data": {"ms": 41200, "turns": 3}},
    )
    assert res.status_code == 200


# Safety filter: caveats are kept, claims are replaced in place


def test_caveat_from_the_workflow_is_kept():
    text = (
        "Yes, that's clearer. The visible centre looks opaque, "
        "though a photo can't confirm that chicken is cooked through."
    )
    assert make_safe(text) == (text, False)


def test_claim_after_reassurance_is_replaced():
    assert make_safe("Don't worry, it's cooked through.") == (COOKED_FALLBACK, True)


def test_only_the_claim_sentence_is_replaced():
    out, replaced = make_safe("The centre looks opaque. The chicken is fully cooked. Enjoy!")
    assert replaced
    assert out == f"The centre looks opaque. {COOKED_FALLBACK} Enjoy!"


def test_negative_statements_are_kept():
    for text in [
        "It isn't cooked through yet, give it two more minutes.",
        "I can't tell if it is safe to eat.",
    ]:
        assert make_safe(text) == (text, False)


def test_check_step_keeps_the_description_of_meat(client, fake_llm, jpeg_b64):
    from conftest import check_body

    fake_llm.next_reply = json.dumps(
        {"status": "done", "say": "The centre looks opaque. The chicken is cooked through."}
    )
    body = client.post("/check-step", json=check_body(jpeg_b64)).json()
    assert body["status"] == "unsure"
    assert body["say"].startswith("The centre looks opaque.")


# Cut-off model output


def test_cut_off_json_keeps_whole_sentences(client, fake_llm):
    fake_llm.next_reply = '{"reply": "Nice work. Next is seasoning the chicken, so let'
    assert client.post("/ask", json=ASK_BODY).json() == {"reply": "Nice work."}


def test_cut_off_json_is_never_read_aloud(client, fake_llm):
    fake_llm.next_reply = '{"re'
    res = client.post("/ask", json=ASK_BODY)
    assert res.status_code == 502
    assert "{" not in res.text.replace('{"error"', "")
