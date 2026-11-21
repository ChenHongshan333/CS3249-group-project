"""Anthropic Claude through the Messages API."""

import base64

import anthropic

from .base import LLM, LLMError, LLMTimeout


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
                # Sonnet 5.5 thinks by default, and thinking can use up
                # max_tokens (200 for /ask) before any text, leaving an empty
                # reply. "between_tools" turns off up-front thinking; Sonnet
                # 5.5 rejects "disabled" with a 400.
                thinking={"type": "between_tools"},
                timeout=timeout,
            )
        except anthropic.APITimeoutError as e:
            raise LLMTimeout(str(e)) from e
        except anthropic.APIError as e:
            raise LLMError(f"claude: {e.__class__.__name__}: {getattr(e, 'message', e)}") from e

        return "".join(block.text for block in resp.content if block.type == "text")
