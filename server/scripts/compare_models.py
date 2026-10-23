"""Compare providers on your own step photos: accuracy and reply time.

1. Put photos in a folder with a cases.json beside them:
   [
     {"photo": "salad-step2-done.jpg",
      "stepText": "Cut the tomatoes in half and slice the cucumber...",
      "doneLooksLike": "The tomatoes are halved and the cucumber is sliced...",
      "expected": "done"},
     ...
   ]
   "expected" is what a person would say: "done", "not_yet" or "unsure".
2. Put the keys you have in server/.env.
3. From server/:  python scripts/compare_models.py path/to/photos
   Add --providers claude,qwen to test only some of them.

Every provider whose key is set is tried on every photo. Nothing is logged
to the study database.
"""

import argparse
import asyncio
import base64
import json
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import prompts, safety  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.images import prepare_jpeg  # noqa: E402
from app.llm import LLMError, LLMNotConfigured, build_llm  # noqa: E402
from app.schemas import CheckStepRequest  # noqa: E402


async def run_case(llm, case: dict, folder: Path, max_side: int, timeout: float):
    photo = base64.b64encode((folder / case["photo"]).read_bytes()).decode()
    req = CheckStepRequest(
        session_id="compare",
        recipe_id="compare",
        step=0,
        step_text=case["stepText"],
        done_looks_like=case.get("doneLooksLike", ""),
        image=photo,
        source="glasses",
    )
    jpeg = prepare_jpeg(req.image, max_side)
    start = time.perf_counter()
    try:
        raw = await llm.complete(
            prompts.CHECK_SYSTEM,
            prompts.check_context(req),
            image_jpeg=jpeg,
            json_output=True,
            max_tokens=200,
            timeout=timeout,
        )
        status, say = safety.parse_check(raw)
    except LLMError as e:
        status, say = "error", str(e)
    return status, say, (time.perf_counter() - start) * 1000


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("folder", type=Path)
    parser.add_argument("--providers", default="claude,openai,qwen,openrouter")
    parser.add_argument("--timeout", type=float, default=20.0)
    args = parser.parse_args()

    settings = get_settings()
    cases = json.loads((args.folder / "cases.json").read_text(encoding="utf-8"))

    for name in args.providers.split(","):
        try:
            llm = build_llm(settings, name.strip())
        except LLMNotConfigured as e:
            print(f"\n== {name}: skipped ({e})")
            continue

        print(f"\n== {llm.name} ({llm.model})")
        correct, times = 0, []
        for case in cases:
            status, say, ms = await run_case(
                llm, case, args.folder, settings.max_image_side, args.timeout
            )
            ok = status == case["expected"]
            correct += ok
            if status != "error":
                times.append(ms)
            mark = "ok  " if ok else "MISS"
            print(f"  {mark} {case['photo']:<32} {status:<8} {ms:6.0f} ms  {say}")

        if times:
            over = sum(t > settings.check_timeout_s * 1000 for t in times)
            print(
                f"  accuracy {correct}/{len(cases)}, median {statistics.median(times):.0f} ms, "
                f"slowest {max(times):.0f} ms, {over} over the app's time limit"
            )


if __name__ == "__main__":
    asyncio.run(main())
