"""A stand-in model for tests and for running the server without a key."""

import asyncio
import json

from .base import LLM


class FakeLLM(LLM):
    name = "fake"
    model = "fake"

    def __init__(self):
        # Tests set these to make the "model" misbehave.
        self.next_reply: str | None = None
        self.delay_s: float = 0.0
        self.calls: list[dict] = []

    async def _complete(self, system, text, image_jpeg, json_output, max_tokens, timeout):
        self.calls.append({"system": system, "text": text, "has_image": image_jpeg is not None})
        if self.delay_s:
            await asyncio.sleep(self.delay_s)
        if self.next_reply is not None:
            return self.next_reply
        if image_jpeg is not None:
            return json.dumps(
                {"status": "not_yet", "say": "Most of it looks ready. A few pieces still look large."}
            )
        return "This is a demo answer from the fake model. Choose a real provider in the server settings."
