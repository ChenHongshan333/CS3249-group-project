"""OpenAI, and Qwen through Alibaba Cloud's OpenAI-compatible endpoint.

Both speak the Chat Completions format, so one class serves both; only the
base URL, key, and a couple of parameter names differ.
"""

import base64

import openai

from .base import LLM, LLMError, LLMTimeout


class OpenAICompatLLM(LLM):
    def __init__(
        self,
        *,
        name: str,
        api_key: str,
        model: str,
        base_url: str | None = None,
        native_openai: bool,
    ):
        self.name = name
        self.model = model
        self._native = native_openai
        self._client = openai.AsyncOpenAI(api_key=api_key, base_url=base_url, max_retries=0)

    async def _complete(self, system, text, image_jpeg, json_output, max_tokens, timeout):
        content: list[dict] = [{"type": "text", "text": text}]
        if image_jpeg is not None:
            data_url = "data:image/jpeg;base64," + base64.b64encode(image_jpeg).decode()
            content.append({"type": "image_url", "image_url": {"url": data_url}})

        extra: dict = {}
        if self._native:
            # Newer OpenAI models only accept max_completion_tokens.
            extra["max_completion_tokens"] = max_tokens
            if json_output:
                extra["response_format"] = {"type": "json_object"}
        else:
            # Qwen's compatible mode uses the older name. JSON mode is not
            # supported by every Qwen vision model, so the prompt asks for
            # JSON and safety.parse_check handles anything else.
            extra["max_tokens"] = max_tokens

        try:
            resp = await self._client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": content},
                ],
                timeout=timeout,
                **extra,
            )
        except openai.APITimeoutError as e:
            raise LLMTimeout(str(e)) from e
        except openai.APIError as e:
            raise LLMError(f"{self.name}: {e.__class__.__name__}") from e

        return resp.choices[0].message.content or ""
