# Backend API contract (draft)

Status: **draft**; the two open questions were settled on 23 Oct (see Decisions). Once agreed, the Flutter app and the backend both code against this file. Change it in its own pull request so everyone sees the change.

All requests and responses are JSON. The base URL is shared in the group once the backend is deployed.

## `POST /ask`

Anything the user says that is not a voice command the app handles itself: a question ("how small is bite-sized?"), an answer to something CookAlong asked ("yes, start it"), or, before step 1, a reply in the opening conversation.

Request:

```json
{
  "sessionId": "a1b2c3",
  "recipeId": "salad",
  "recipeName": "Rainbow salad bowl",
  "step": 1,
  "stepText": "Cut half a cucumber into small, bite-sized pieces.",
  "nextStepTitle": "Build your bowl",
  "question": "How small is bite-sized?",
  "acceptedSwaps": ["yoghurt-instead-of-mayo"],
  "history": [
    { "from": "assistant", "text": "Step two. Cut half a cucumber into small, bite-sized pieces." },
    { "from": "user", "text": "How small is bite-sized?" }
  ]
}
```

- `step` starts at 0.
- `stepText` is the instruction the user currently sees. The backend answers about this text and keeps no recipe copy of its own.
- `nextStepTitle` is empty on the last step.
- `history` holds the last few turns only, oldest first.

Optional fields (added 23 Oct; requests without them still work):

| Field | Meaning |
| --- | --- |
| `phase` | `"cooking"` (default) or `"opening"`, the short conversation before step 1. In the opening, `step` and `stepText` may be left out. |
| `ingredients` | `[{ "name": "garlic", "ready": true }]`. `ready` is the tick on the Get ready screen. In the opening, CookAlong only asks about ingredients that are not ready. |
| `pendingOffer` | The `offer` from the previous reply, if the user has not answered it yet. Send it back exactly as received, then forget it. |
| `steps` | Opening only (added 24 Oct): every step as the user will see it, `[{ "title": "Wash & prepare", "text": "Rinse the greens…" }]`, in order, so CookAlong can adapt them to missing ingredients. Send the adapted text once steps were changed. |

Response:

```json
{ "reply": "Aim for pieces about one to two centimetres wide. They don't have to be identical." }
```

The app speaks `reply` as it is, so keep it to one or two sentences.

The response may also carry an `offer`, an `action`, or both:

- `offer`: something the reply proposes, such as "Would you like a ten-minute timer?". The app keeps it and sends it back as `pendingOffer` with the next `/ask`.
- `action`: something the app does now, because the user accepted an offer or asked for it directly.

Both use the same shape. The app ignores any `type` it does not know.

| `type` | Other fields | When |
| --- | --- | --- |
| `start_timer` | `seconds` (1–3600), `label` | "Yes, start the timer." |
| `next_step` | | "Yes, let's move on." |
| `repeat_step` | | "Say that again?" |
| `start_cooking` | | Opening only: the user is ready for step 1. |
| `tick_ingredient` | `names`, a list of the request's `ingredients` (also `name`, the first of them, for older apps) | Opening only: "I've got the garlic and the sauce now." |
| `adapt_steps` | `steps`, the changed steps only: `[{ "step": 0, "text": "Rinse the greens and cucumber." }]`. `step` indexes the request's `steps`; `text` is the whole new instruction | Opening only (added 24 Oct): the cook has decided how to manage without a missing ingredient, by leaving it out or using a substitute. The app replaces those steps and shows the changes in the chat. |
| `custom_swap` | `swap`, the cook's idea in a few words; `healthier` and `fits`, both true or false; `steps` as in `adapt_steps`, only when both are true | Opening only (added 24 Oct): the cook suggests their own healthier swap, such as "Can I use Greek yoghurt instead of mayo?". `reply` says in one sentence whether it is healthier and fits the dish, and why. When both are true, the app changes `steps` as for `adapt_steps`. Either way the app logs it as `custom_swap`. |

Example of an offer, then the user accepting it:

```json
// Request
{ "question": "It's still a little too firm for me.", "...": "..." }
// Response
{
  "reply": "Give it another minute. Would you like a one-minute timer?",
  "offer": { "type": "start_timer", "seconds": 60, "label": "Pasta" }
}

// Next request
{
  "question": "Please.",
  "pendingOffer": { "type": "start_timer", "seconds": 60, "label": "Pasta" },
  "...": "..."
}
// Response
{
  "reply": "One-minute timer started.",
  "action": { "type": "start_timer", "seconds": 60, "label": "Pasta" }
}
```

### The opening conversation

After the user starts a recipe, and before step 1, the app speaks a fixed first line. Every participant hears the same opening, and it needs no backend call:

- Some ingredients not ticked: "Today we're making {recipe}, right? Have you got the {unticked ingredients}?"
- All ticked: "Today we're making {recipe}, right? You've got everything, so say 'let's start' when you're ready."

The user's replies go to `/ask` with `"phase": "opening"`. CookAlong confirms what is missing, suggests what to leave out or swap, and returns `start_cooking` when the user is ready. Saying "let's start" or tapping Start also begins step 1 without a backend call.

When an ingredient is missing, CookAlong says whether the recipe still works without it and talks through substitutes. Once the cook decides, it returns `adapt_steps` with the steps that change:

```json
// Request (phase "opening", with "steps")
{ "question": "I'll use a red pepper instead.", "...": "..." }
// Response
{
  "reply": "Good choice. I've changed step 2 to use the red pepper. Just let me know when you're ready.",
  "action": {
    "type": "adapt_steps",
    "steps": [{ "step": 1, "text": "Cut half a cucumber and the red pepper into small, bite-sized pieces." }]
  }
}
```

From then on the app sends the adapted text as `stepText`, so answers while cooking match the changed steps.

The cook can also suggest their own healthier swap before step 1, for an ingredient they have. CookAlong judges it and returns `custom_swap`:

```json
// Request (phase "opening", with "steps")
{ "question": "Could I use Greek yoghurt instead of the mayo?", "...": "..." }
// Response
{
  "reply": "Yes, Greek yoghurt has far less fat and works well in the dressing. I've changed step 3.",
  "action": {
    "type": "custom_swap",
    "swap": "Greek yoghurt instead of mayo",
    "healthier": true,
    "fits": true,
    "steps": [{ "step": 2, "text": "Stir two tablespoons of Greek yoghurt into the dressing." }]
  }
}
```

If it isn't healthier or doesn't fit, `healthier` or `fits` is false, there are no `steps`, and the reply says why in a few words.

## `POST /check-step`

The user asks CookAlong to look ("check this"). The app takes one fresh photo from the glasses, or from the phone camera as a fallback.

Request:

```json
{
  "sessionId": "a1b2c3",
  "recipeId": "salad",
  "step": 1,
  "stepText": "Cut half a cucumber into small, bite-sized pieces.",
  "doneLooksLike": "The cucumber is chopped into bite-sized pieces.",
  "image": "<base64 JPEG, no data: prefix>",
  "source": "glasses"
}
```

- `doneLooksLike` comes from the recipe data and tells the AI what to look for.
- `source` is `"glasses"` or `"phone"`.
- `question` (optional) is what the user asked, such as "does this look chopped small enough?". Leave it out for a plain "check this".

Response:

```json
{
  "status": "not_yet",
  "say": "Most pieces look bite-sized, but a few look larger. You could cut those in half."
}
```

- `status` is `"done"`, `"not_yet"` or `"unsure"`. The app never moves to the next step because of `status`; the user decides.
- Use `"unsure"` when the photo is unclear, and say what to change, e.g. "Move the camera slightly above the bowl."
- Whether meat, fish, eggs or rice are cooked is never `"done"`. CookAlong describes what it sees and says a photo can't confirm it.

## `POST /log`

One event in a cooking session, saved for the user study.

Request:

```json
{
  "sessionId": "a1b2c3",
  "type": "step_next",
  "time": "2026-10-28T14:03:12+08:00",
  "data": { "step": 2 }
}
```

`type` is one of:

| Type | `data` |
| --- | --- |
| `session_start` | `{ "recipeId": "salad", "condition": "A" }` |
| `step_next`, `step_repeat` | `{ "step": 2 }` |
| `pause`, `resume` | `{ "step": 2 }` |
| `question` | `{ "step": 1, "question": "...", "reply": "...", "ms": 1840 }` |
| `check` | `{ "step": 1, "status": "not_yet", "ms": 2650 }` |
| `swap` | `{ "swapId": "yoghurt-instead-of-mayo", "accepted": true }` |
| `custom_swap` | `{ "swap": "Greek yoghurt instead of mayo", "healthier": true, "fits": true, "applied": true, "reason": "Yes, Greek yoghurt has far less fat…" }`: a swap the cook suggested (added 24 Oct). Kept apart from `swap`, so the fixed swaps stay the same for every participant. `applied` is true when steps changed; `reason` is CookAlong's reply |
| `misheard` | `{ "heard": "next step", "meant": "repeat" }` |
| `opening_end` | `{ "ms": 41200, "turns": 3, "missing": ["cherry tomatoes"] }`: how long the opening took, how many user replies, and what was still unticked at step 1 |
| `session_end` | `{ "completed": true }` |

`ms` is how long the backend took to answer, for the reply-time measure.

Response:

```json
{ "ok": true }
```

## Errors

On failure, return a non-200 status with:

```json
{ "error": "short description" }
```

The app then says something like "Sorry, I couldn't reach the assistant. You can keep going and ask me again."

## Decisions

Agreed by team poll on 23 Oct.

- **Recipes live in the app.** The app sends the current step's text with each request, so the backend never holds a second copy that could drift. If the backend later turns recipe links into recipes, recipes move to the backend and the app loads them from a new `GET /recipes`.
- **The opening conversation confirms, it does not choose.** Agreed 23 Oct: the user picks the recipe in the app, and CookAlong opens with "Today we're making …, right?". The Get ready checklist stays; the opening only asks about ingredients that are not ticked.
- **Cooks may suggest their own swaps** (#22, team poll 24 Oct). The study needs the same fixed swaps for every participant, so suggestions are allowed but logged as `custom_swap`, apart from the fixed `swap` events.
- **Offers are confirmed through `/ask`.** When CookAlong proposes something ("Would you like a timer?"), the app sends the offer back with the user's next words, so "please" or "no thanks" is understood without the app parsing it.
- **No streaming for now.** `/ask` returns the whole reply in one response. Reply times are measured from the log (`ms`); streaming is reconsidered later if replies are too slow after trying a faster model and shorter prompts.
