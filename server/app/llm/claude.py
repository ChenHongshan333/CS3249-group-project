"""Anthropic Claude through the Messages API."""

import base64

import anthropic

from .base import LLM, LLMError, LLMTimeout

# Short spoken answers don't need thinking, and with the small max_tokens we
# send, thinking can use up the whole reply. Each model turns it off
# differently, and sending the wrong form is a 400 on every request.
_NO_THINKING_OFF = ("claude-opus-5-5", "claude-fable-", "claude-mythos-")


def thinking_off(model: str) -> dict:
    """Extra request fields that keep this model from thinking, or as close as it allows."""
    if model.startswith("claude-sonnet-5-5"):
        # Sonnet 5.5 rejects {"type": "disabled"}.
        return {"thinking": {"type": "between_tools"}}
    if model.startswith(_NO_THINKING_OFF):
        # Thinking can't be turned off on these; keep it as short as possible.
        return {"output_config": {"effort": "low"}}
    return {"thinking": {"type": "disabled"}}


class ClaudeLLM(LLM):
    name = "claude"

    def __init__(self, api_key: str, model: str):
        self.model = model
        # No automatic retries: the app only waits a few seconds.
        self._client = anthropic.AsyncAnthropic(api_key=api_key, max_retries=0)

    async def _complete(self, system, text, image_jpeg, json_output, max_tokens, timeout):
        content: list[dict] = []
        if image_jpeg is not None:
            content.append(
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64.b64encode(image_jpeg).decode(),
                    },
                }
            )
        content.append({"type": "text", "text": text})

        try:
            resp = await self._client.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                system=system,
                messages=[{"role": "user", "content": content}],
                # extra_body, so fields newer than the pinned SDK still go through.
                extra_body=thinking_off(self.model),
                timeout=timeout,
            )
        except anthropic.APITimeoutError as e:
            raise LLMTimeout(str(e)) from e
        except anthropic.APIError as e:
            raise LLMError(f"claude: {e.__class__.__name__}: {getattr(e, 'message', e)}") from e

        return "".join(block.text for block in resp.content if block.type == "text")
