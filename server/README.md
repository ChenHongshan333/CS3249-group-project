# CookAlong backend

Owners: Zhihan, Hongshan

The backend is the only part of CookAlong that talks to the AI. The Flutter app sends it questions, step photos and log events, and it sends back short replies for the app to speak. It keeps the AI key off the phone, holds the prompts and safety rules in one place, and stores the study log.

```
Glasses ─▶ Phone app ─▶ this backend ─▶ Claude / OpenAI / Qwen
```

The requests and responses are defined in [`docs/api.md`](../docs/api.md). Change that file first, in its own pull request, if the contract needs to change.

## Rules

- The AI API key lives in `server/.env` and is never committed. `.env` files are ignored by git.
- Healthier swaps come from the recipe data, not from the AI, so every participant sees the same ones.
- The AI describes what it sees; it never says meat is cooked through or that food is safe for an allergy. The prompts say so, and [`app/safety.py`](app/safety.py) replaces any reply that breaks the rule.

## Run it on your computer

Needs Python 3.12 or newer.

```bash
cd server
python -m venv .venv
.venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
pip install -r requirements-dev.txt
copy .env.example .env          # macOS/Linux: cp .env.example .env
```

Put a key in `.env`, or set `LLM_PROVIDER=fake` to try it without one. Then:

```bash
uvicorn app.main:app --reload --port 8000
```

Open http://localhost:8000/docs to try every endpoint in the browser. To point the app at it, enter the URL under Profile → Developer → Backend URL. The web version can use `http://localhost:8000`. A phone needs your computer's Wi-Fi IP address (for example `http://192.168.1.20:8000`) and the server started with `--host 0.0.0.0`.

## Switch models

Set `LLM_PROVIDER` in `.env` and restart:

| `LLM_PROVIDER` | Needs | Notes |
| --- | --- | --- |
| `claude` | `ANTHROPIC_API_KEY` | Defaults to `claude-haiku-5-5`, which is fast and reads photos. Set `CLAUDE_MODEL` to try another. |
| `openai` | `OPENAI_API_KEY`, `OPENAI_MODEL` | Pick a current vision-capable model. There is no default because the names change often. |
| `qwen` | `QWEN_API_KEY` | Alibaba Cloud Model Studio, international (Singapore) endpoint. Defaults to `qwen-vl-max`. |
| `fake` | nothing | Canned replies, for trying the app and for tests. |

`GET /health` shows which provider and model are active, or what is missing.

### Choose with your own photos

Take a photo of each recipe step, some finished and some not, and list them in a `cases.json` (the format is at the top of [`scripts/compare_models.py`](scripts/compare_models.py)). Then:

```bash
python scripts/compare_models.py path/to/photos
```

Every provider whose key is in `.env` checks every photo. The script prints accuracy, median reply time, and how many replies went over the app's 8-second limit.

## Endpoints

| Endpoint | What it does |
| --- | --- |
| `POST /ask` | Answers what the user says about the current step, in one or two sentences. With `"phase": "opening"` it runs the short chat before step 1. The reply can carry an `offer` ("Would you like a timer?") and an `action` for the app to do. |
| `POST /check-step` | Shrinks the photo to 1024 px, asks the model whether the step looks finished, and returns `done`, `not_yet` or `unsure`. A reply that can't be read becomes `unsure`. |
| `POST /log` | Saves one study event to SQLite. |
| `GET /health` | Shows whether the server is up and which model it uses. |
| `GET /export/events.csv` | Downloads all study events as CSV. It is off unless `ADMIN_KEY` is set, and needs that key in an `X-Admin-Key` header. |

Errors use the contract's `{"error": "..."}` shape:

- 400: the request is malformed or the photo is unreadable.
- 503: no key is set.
- 504: the model took longer than `ASK_TIMEOUT_S` or `CHECK_TIMEOUT_S`. These are 5 s and 7 s, just under the app's own limits.
- 502: the model failed.

Each model call is also timed in an `llm_calls` table, so you can compare providers on real sessions.

## Prompts and safety

The prompts are in [`app/prompts.py`](app/prompts.py): one each for the opening, questions while cooking, and photo checks. Their voice follows the team's conversation workflow: warm and brief, one question at a time, ask before doing things for the cook, and describe a photo before giving advice.

[`app/safety.py`](app/safety.py) checks every reply before the app speaks it:

- **Doneness and allergy claims**: a sentence that says food is cooked through, safe to eat, or allergy-safe is replaced in place. A caveat such as "a photo can't confirm that chicken is cooked through" is kept, along with the rest of the reply.
- **Offers and actions**: anything outside the five types in `docs/api.md` is dropped, as is anything that doesn't fit the phase or the request (for example, a timer longer than an hour, or ticking an ingredient the app didn't send).

## Try the conversation workflow

[`evals/chicken_chop.json`](evals/chicken_chop.json) is the team's chicken chop workflow as a script. It plays every user line through the backend, the way the app would:

```bash
python scripts/run_workflow.py                    # uses the model in .env
python scripts/run_workflow.py --section 6        # just section 6
python scripts/run_workflow.py --url https://...  # a deployed backend
```

It prints each real reply under the ideal one, with any offer or action. Where the workflow expects a particular action or photo status, it marks the turn OK or MISS. Read the wording yourself, and rerun the script after every prompt change. For photo checks, add the pictures listed in [`evals/photos/`](evals/photos/README.md).

## Tests

```bash
pytest
```

The tests use the fake model, so they need no key and cost nothing.

## Deploy

Any host that runs Python works. On [Render](https://render.com):

1. New → Web Service → connect this GitHub repository.
2. Root directory `server`, build command `pip install -r requirements.txt`, start command `uvicorn app.main:app --host 0.0.0.0 --port $PORT`.
3. Add the variables from `.env.example` under Environment. Never put keys in the repository.
4. Share the `https://….onrender.com` URL with the app team.

**The study log needs lasting storage.** On free hosting plans, files such as `data/cookalong.db` are wiped whenever the service restarts or redeploys. Before the user study, either attach a persistent disk and point `LOG_DB_PATH` at it, or set `ADMIN_KEY` and download `/export/events.csv` after every session.

## Not done yet

- **Shared key.** Once the URL is public, anyone who finds it can spend your AI credit. `APP_API_KEY` is ready on the server side, but turning it on needs two more changes: the app must send the `X-API-Key` header, and `docs/api.md` must document it in its own pull request.
- **Hidden errors in the app.** The app falls back to its built-in demo answers when the backend fails, which hides backend errors during testing. Check `/health` and the server log while you test.
