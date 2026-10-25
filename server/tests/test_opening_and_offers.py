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
    assert "Ingredients the cook has: chicken thigh" in call["text"]
    assert (
        "Ingredients the cook doesn't have: cherry tomatoes (leaving it out), "
        "garlic (leaving it out)" in call["text"]
    )
    assert "Say 'let's start' when you're ready." in call["system"]


# Choices made on Get ready (#98)


def test_opening_context_has_the_get_ready_choices(client, fake_llm):
    ingredients = [
        {"name": "chicken thigh", "ready": True},
        {"name": "cherry tomatoes", "ready": False, "use": "passata"},
        {"name": "garlic", "ready": False},
    ]
    client.post("/ask", json={**OPENING_BODY, "ingredients": ingredients})
    assert (
        "Ingredients the cook doesn't have: cherry tomatoes (using passata instead), "
        "garlic (leaving it out)" in fake_llm.calls[0]["text"]
    )
    # Already decided, so the opening doesn't ask about them again.
    assert "ask about them again" in fake_llm.calls[0]["system"]


def test_cooking_context_names_what_is_missing(client, fake_llm):
    client.post(
        "/ask",
        json={**ASK_BODY, "ingredients": [{"name": "onion", "ready": False}]},
    )
    assert "Ingredients the cook doesn't have: onion (leaving it out)" in fake_llm.calls[0]["text"]


def test_cooking_context_without_ingredients_is_unchanged(client, fake_llm):
    client.post("/ask", json=ASK_BODY)
    assert "doesn't have" not in fake_llm.calls[0]["text"]


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


# Adapting steps to a missing ingredient (#32)

STEPS = [
    {"title": "Prepare", "text": "Halve the cherry tomatoes and slice the garlic."},
    {"title": "Cook the chicken", "text": "Pan-fry the chicken thigh skin-side down."},
    {"title": "Make the sauce", "text": "Soften the garlic, then add the cherry tomatoes."},
]
ADAPT_BODY = {**OPENING_BODY, "question": "I'll leave the tomatoes out.", "steps": STEPS}


def adapt(*changes) -> dict:
    return {"type": "adapt_steps", "steps": [{"step": s, "text": t} for s, t in changes]}


def test_opening_context_lists_the_steps(client, fake_llm):
    client.post("/ask", json=ADAPT_BODY)
    text = fake_llm.calls[0]["text"]
    assert "[0] Prepare: Halve the cherry tomatoes" in text
    assert "[2] Make the sauce: Soften the garlic" in text
    assert "adapt_steps" in fake_llm.calls[0]["system"]


def test_adapt_steps_is_returned(client, fake_llm):
    fake_llm.next_reply = reply_json(
        reply="No problem. I've adjusted the steps.",
        action=adapt((0, "Slice the garlic."), (2, "Soften the garlic.")),
    )
    body = client.post("/ask", json=ADAPT_BODY).json()
    assert body["action"] == adapt((0, "Slice the garlic."), (2, "Soften the garlic."))


def test_adapt_steps_drops_unknown_and_unchanged_steps(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action=adapt(
            (0, "Slice the garlic."),
            (1, "Pan-fry the chicken thigh skin-side down."),  # unchanged
            (7, "Not a step."),
        )
    )
    body = client.post("/ask", json=ADAPT_BODY).json()
    assert body["action"] == adapt((0, "Slice the garlic."))


def test_adapt_steps_needs_the_steps(client, fake_llm):
    fake_llm.next_reply = reply_json(action=adapt((0, "Slice the garlic.")))
    assert "action" not in client.post("/ask", json=OPENING_BODY).json()


def test_adapt_steps_is_opening_only(client, fake_llm):
    fake_llm.next_reply = reply_json(action=adapt((0, "Slice the garlic.")))
    assert "action" not in client.post("/ask", json={**ASK_BODY, "steps": STEPS}).json()


def test_adapted_steps_get_the_safety_pass(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action=adapt((1, "Pan-fry the chicken thigh. It is cooked through and safe to eat."))
    )
    text = client.post("/ask", json=ADAPT_BODY).json()["action"]["steps"][0]["text"]
    assert "safe to eat" not in text
    assert text.startswith("Pan-fry the chicken thigh.")


def test_adapt_steps_prompt_keeps_step_numbers_out_of_the_reply(client, fake_llm):
    client.post("/ask", json=ADAPT_BODY)
    system = fake_llm.calls[0]["system"]
    assert "without step numbers" in system
    assert "I've changed step" not in system


# Steps that change or go when an ingredient is left out (#94)


def test_opening_context_has_each_steps_check(client, fake_llm):
    steps = [{**STEPS[0], "check": "The tomatoes are halved."}, *STEPS[1:]]
    client.post("/ask", json={**ADAPT_BODY, "steps": steps})
    text = fake_llm.calls[0]["text"]
    assert "[0] Prepare: Halve the cherry tomatoes and slice the garlic. " \
        "(Finished when: The tomatoes are halved.)" in text
    assert "[1] Cook the chicken: Pan-fry the chicken thigh skin-side down.\n" in text


def test_adapt_steps_can_change_title_and_check(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={
            "type": "adapt_steps",
            "steps": [
                {"step": 2, "text": "Soften the garlic.", "title": "Soften the garlic",
                 "check": "The garlic smells sweet."},
            ],
        }
    )
    body = client.post("/ask", json=ADAPT_BODY).json()
    assert body["action"]["steps"] == [
        {"step": 2, "text": "Soften the garlic.", "title": "Soften the garlic",
         "check": "The garlic smells sweet."},
    ]


def test_adapt_steps_can_remove_a_step(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={
            "type": "adapt_steps",
            "steps": [{"step": 0, "text": "Slice the garlic."}, {"step": 2, "remove": True}],
        }
    )
    body = client.post("/ask", json=ADAPT_BODY).json()
    assert body["action"]["steps"] == [
        {"step": 0, "text": "Slice the garlic."},
        {"step": 2, "remove": True},
    ]


def test_adapt_steps_cannot_remove_every_step(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={"type": "adapt_steps", "steps": [{"step": i, "remove": True} for i in range(3)]}
    )
    assert "action" not in client.post("/ask", json=ADAPT_BODY).json()


def test_a_change_needs_text_unless_it_removes_the_step(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={"type": "adapt_steps", "steps": [{"step": 0, "title": "Prepare"}]}
    )
    assert "action" not in client.post("/ask", json=ADAPT_BODY).json()


def test_a_change_to_only_the_title_is_kept(client, fake_llm):
    fake_llm.next_reply = reply_json(
        action={
            "type": "adapt_steps",
            "steps": [{"step": 1, "text": STEPS[1]["text"], "title": "Fry the chicken"}],
        }
    )
    body = client.post("/ask", json=ADAPT_BODY).json()
    assert body["action"]["steps"] == [
        {"step": 1, "text": STEPS[1]["text"], "title": "Fry the chicken"},
    ]


@pytest.mark.parametrize("said, kept", [
    ("Boil the oil for a minute.", "Warm the oil for a minute."),
    ("Heat the pan and boil a little oil.", "Heat the pan and warm a little oil."),
    ("Bring the oil to a boil, then add the chickpeas.", "Warm the oil, then add the chickpeas."),
    ("Bring water to a boil and add a little oil.", "Bring water to a boil and add a little oil."),
])
def test_adapted_steps_never_boil_oil(client, fake_llm, said, kept):
    fake_llm.next_reply = reply_json(action=adapt((1, said)))
    assert client.post("/ask", json=ADAPT_BODY).json()["action"]["steps"][0]["text"] == kept


def test_opening_has_room_for_rewritten_steps(client, fake_llm):
    client.post("/ask", json=ADAPT_BODY)
    client.post("/ask", json=ASK_BODY)
    assert fake_llm.calls[0]["max_tokens"] > fake_llm.calls[1]["max_tokens"]


# The cook's own healthier swap (#22)

SWAP_BODY = {**OPENING_BODY, "question": "Could I use less oil and a squeeze of lemon?", "steps": STEPS}


def custom(healthier=True, fits=True, *changes, swap="Lemon instead of some oil") -> dict:
    action = {"type": "custom_swap", "swap": swap, "healthier": healthier, "fits": fits}
    if changes:
        action["steps"] = [{"step": s, "text": t} for s, t in changes]
    return action


def test_custom_swap_is_in_the_opening_prompt(client, fake_llm):
    client.post("/ask", json=SWAP_BODY)
    assert "custom_swap" in fake_llm.calls[0]["system"]


def test_custom_swap_with_steps_is_returned(client, fake_llm):
    fake_llm.next_reply = reply_json(
        reply="Yes, that's lighter and still tasty. I've adjusted the steps.",
        action=custom(True, True, (1, "Pan-fry the chicken thigh in a teaspoon of oil.")),
    )
    body = client.post("/ask", json=SWAP_BODY).json()
    assert body["action"] == custom(True, True, (1, "Pan-fry the chicken thigh in a teaspoon of oil."))


@pytest.mark.parametrize("healthier, fits", [(False, True), (True, False)])
def test_custom_swap_that_doesnt_work_changes_no_steps(client, fake_llm, healthier, fits):
    fake_llm.next_reply = reply_json(
        reply="That isn't really healthier.",
        action=custom(healthier, fits, (1, "Deep-fry the chicken thigh.")),
    )
    assert client.post("/ask", json=SWAP_BODY).json()["action"] == custom(healthier, fits)


@pytest.mark.parametrize("missing", ["swap", "healthier", "fits"])
def test_custom_swap_needs_a_name_and_a_verdict(client, fake_llm, missing):
    action = custom()
    del action[missing]
    fake_llm.next_reply = reply_json(action=action)
    assert "action" not in client.post("/ask", json=SWAP_BODY).json()


def test_custom_swap_is_opening_only(client, fake_llm):
    fake_llm.next_reply = reply_json(action=custom())
    assert "action" not in client.post("/ask", json={**ASK_BODY, "steps": STEPS}).json()


def test_custom_swap_is_logged_on_its_own(client):
    res = client.post(
        "/log",
        json={
            "sessionId": "a1",
            "type": "custom_swap",
            "data": {"swap": "Lemon instead of some oil", "healthier": True, "fits": True, "applied": True},
        },
    )
    assert res.json() == {"ok": True}
