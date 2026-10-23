"""Play a conversation workflow through the backend and compare the replies.

    python scripts/run_workflow.py                      # evals/chicken_chop.json, model from .env
    python scripts/run_workflow.py --url https://...    # a deployed backend instead
    python scripts/run_workflow.py --section 6          # only sections starting with "6"

Each user line is sent the way the app sends it: with the conversation so
far, the offer from the previous reply, and the ticked ingredients. The
script prints the real reply under the ideal one, plus any offer or action,
and checks the expected action, offer or photo status where the workflow
gives one.

Photo checks need pictures in evals/photos/ named as in the workflow file.
Missing photos are skipped. Read the replies yourself: "OK" only means the
action or status matched, not that the wording is good.
"""

import argparse
import base64
import json
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def make_client(url: str | None):
    if url:
        import httpx

        return httpx.Client(base_url=url.rstrip("/"), timeout=30)

    from fastapi.testclient import TestClient

    from app.config import get_settings
    from app.main import create_app

    # Calls made by this script aren't study data.
    settings = get_settings().model_copy(update={"log_db_path": ":memory:"})
    return TestClient(create_app(settings))


def opening_line(recipe: dict, ingredients: list[dict]) -> str:
    """The app's fixed first line (docs/api.md, The opening conversation)."""
    missing = [i["name"] for i in ingredients if not i["ready"]]
    if not missing:
        return (
            f"Today we're making {recipe['name']}, right? You've got everything, "
            "so say 'let's start' when you're ready."
        )
    listed = missing[0] if len(missing) == 1 else ", ".join(missing[:-1]) + " and " + missing[-1]
    return f"Today we're making {recipe['name']}, right? Have you got the {listed}?"


def wrap(label: str, text: str) -> str:
    return textwrap.fill(text, width=100, initial_indent=f"  {label:<7}", subsequent_indent=" " * 9)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("workflow", nargs="?", default=str(ROOT / "evals" / "chicken_chop.json"))
    parser.add_argument("--url", help="a running backend; default: run it in-process")
    parser.add_argument("--section", default="", help="only sections starting with this")
    parser.add_argument("--photos", default=str(ROOT / "evals" / "photos"))
    args = parser.parse_args()

    flow = json.loads(Path(args.workflow).read_text(encoding="utf-8"))
    recipe = flow["recipe"]
    steps = recipe["steps"]
    ingredients = [{"name": n, "ready": n in flow.get("ticked", [])} for n in recipe["ingredients"]]
    client = make_client(args.url)

    health = client.get("/health").json()
    print(f"Backend: {health.get('provider')} / {health.get('model')}")
    if not health.get("configured"):
        print(f"Not configured: {health.get('problem')}")
        return

    history: list[dict] = []
    pending_offer: dict | None = None
    first = opening_line(recipe, ingredients)
    history.append({"from": "assistant", "text": first})
    print(f"\n== 1 Opening (fixed line from the app)\n{wrap('app', first)}")

    section = None
    results = {"ok": 0, "miss": 0}

    for turn in flow["turns"]:
        if not turn["section"].startswith(args.section):
            continue
        if turn["section"] != section:
            section = turn["section"]
            print(f"\n== {section}")

        print(wrap("user", turn["user"]))
        print(wrap("ideal", turn["ideal"]))

        if turn.get("check"):
            photo = Path(args.photos) / turn["photo"]
            if not photo.exists():
                print(f"  (skipped: add {photo.relative_to(ROOT)} to run this photo check)")
                continue
            step = steps[turn["step"]]
            res = client.post(
                "/check-step",
                json={
                    "sessionId": "workflow",
                    "recipeId": recipe["id"],
                    "step": turn["step"],
                    "stepText": step["instruction"],
                    "doneLooksLike": step["check"],
                    "image": base64.b64encode(photo.read_bytes()).decode(),
                    "source": "glasses",
                    "question": turn["user"],
                },
            )
            body = res.json()
            if res.status_code != 200:
                print(wrap("ERROR", body.get("error", str(body))))
                continue
            print(wrap("actual", f"[{body['status']}] {body['say']}"))
            got, want = body["status"], turn.get("expectStatus")
            reply = body["say"]
        else:
            phase = turn.get("phase", "cooking")
            request = {
                "sessionId": "workflow",
                "recipeId": recipe["id"],
                "recipeName": recipe["name"],
                "phase": phase,
                "question": turn["user"],
                "acceptedSwaps": recipe.get("acceptedSwaps", []),
                "ingredients": ingredients,
                "history": history[-6:],
            }
            if phase == "cooking":
                i = turn["step"]
                request |= {
                    "step": i,
                    "stepText": steps[i]["instruction"],
                    "nextStepTitle": steps[i + 1]["title"] if i + 1 < len(steps) else "",
                }
            if pending_offer:
                request["pendingOffer"] = pending_offer
            res = client.post("/ask", json=request)
            body = res.json()
            if res.status_code != 200:
                print(wrap("ERROR", body.get("error", str(body))))
                continue

            reply = body["reply"]
            print(wrap("actual", reply))
            pending_offer = body.get("offer")
            action = body.get("action")
            for name, value in (("offer", pending_offer), ("action", action)):
                if value:
                    print(wrap(name, json.dumps(value)))
            if action and action["type"] == "tick_ingredient":
                for ingredient in ingredients:
                    if ingredient["name"] == action["name"]:
                        ingredient["ready"] = True

            if "expectAction" in turn:
                got, want = (action or {}).get("type"), turn["expectAction"]
            elif "expectOffer" in turn:
                got, want = (pending_offer or {}).get("type"), turn["expectOffer"]
            else:
                got = want = None

        history.append({"from": "user", "text": turn["user"]})
        history.append({"from": "assistant", "text": reply})
        if want is not None:
            ok = got == want
            results["ok" if ok else "miss"] += 1
            print(f"  {'OK  ' if ok else 'MISS'}   expected {want}, got {got}")

    print(f"\nExpected actions and statuses: {results['ok']} matched, {results['miss']} missed.")


if __name__ == "__main__":
    main()
