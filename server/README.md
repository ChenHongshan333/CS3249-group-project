# CookAlong backend

Owners: Zhihan, Hongshan

The backend is the only part of CookAlong that talks to the AI. The Flutter app sends it questions, step photos and log events, and it sends back short replies for the app to speak.

The requests and responses are defined in [`docs/api.md`](../docs/api.md). Change that file first, in its own pull request, if the contract needs to change.

## Rules

- The AI API key lives in `server/.env` and is never committed. `.env` files are ignored by git.
- Healthier swaps come from the recipe data, not from the AI, so every participant sees the same ones.
- The AI describes what it sees; it never says meat is cooked through or that food is safe for an allergy.

## Suggested order

1. A script that calls the AI with one recipe and step as context.
2. `POST /ask`, with a system prompt based on the conversation design rules.
3. `POST /check-step`, tested on your own photos of each step.
4. Deploy, share the URL with the app team, then add `POST /log`.
