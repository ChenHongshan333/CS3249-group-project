# CookAlong

A voice-first cooking assistant for CS3249 that sees through Meta glasses and guides beginner cooks through a recipe, one step at a time.

## Layout

| Folder | What it holds | Owners |
| --- | --- | --- |
| [`mobile/`](mobile/) | The Flutter app for Android and iPhone: screens and the Meta glasses connection | Jaxon (glasses), AI agent (screens) |
| [`server/`](server/) | The backend that talks to the AI | Zhihan, Hongshan |
| [`docs/`](docs/) | The API contract between the app and the backend | Everyone |
| [`web/`](web/) | The original React prototype, kept as the reference for the Flutter screens | — |

## Working together

- Work on a branch named after the folder and task, such as `server/ask-endpoint` or `mobile/glasses-camera`.
- Open a pull request into `main` once your change runs. Someone else reviews it before merging.
- `main` must always run.
- Keep commits small and focused: one logical change each.
- Change [`docs/api.md`](docs/api.md) in its own pull request, so the app and backend teams both see it.
- Never commit API keys. Put them in a `.env` file, which git ignores.

## Running the web prototype

```bash
cd web
npm install
npm start
```
