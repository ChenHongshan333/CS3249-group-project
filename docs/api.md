# Backend API contract (draft)

Status: **draft, to agree on Thu 22 Oct**. Once agreed, the Flutter app and the backend both code against this file. Change it in its own pull request so everyone sees the change.

All requests and responses are JSON. The base URL is shared in the group once the backend is deployed.

## `POST /ask`

A spoken question that is not a voice command, such as "how small is bite-sized?".

Request:

```json
{
  "sessionId": "a1b2c3",
  "recipeId": "salad",
  "step": 1,
  "question": "How small is bite-sized?",
  "acceptedSwaps": ["yoghurt-instead-of-mayo"],
  "history": [
    { "from": "assistant", "text": "Step two. Cut half a cucumber into small, bite-sized pieces." },
    { "from": "user", "text": "How small is bite-sized?" }
  ]
}
```

- `step` starts at 0.
- `history` holds the last few turns only, oldest first.

Response:

```json
{ "reply": "Aim for pieces about one to two centimetres wide. They don't have to be identical." }
```

The app speaks `reply` as it is, so keep it to one or two sentences.

## `POST /check-step`

The user asks CookAlong to look ("check this"). The app takes one fresh photo from the glasses, or from the phone camera as a fallback.

Request:

```json
{
  "sessionId": "a1b2c3",
  "recipeId": "salad",
  "step": 1,
  "image": "<base64 JPEG, no data: prefix>",
  "source": "glasses"
}
```

- `source` is `"glasses"` or `"phone"`.

Response:

```json
{
  "status": "not_yet",
  "say": "Most pieces look bite-sized, but a few look larger. You could cut those in half."
}
```

- `status` is `"done"`, `"not_yet"` or `"unsure"`. The app never moves to the next step because of `status`; the user decides.
- Use `"unsure"` when the photo is unclear, and say what to change, e.g. "Move the camera slightly above the bowl."

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
| `misheard` | `{ "heard": "next step", "meant": "repeat" }` |
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

## Open questions

- Recipe data: does the backend keep its own copy of the recipes, or does the app send the step text with each request?
- Does `/ask` need to stream its reply, or is one response fast enough?
