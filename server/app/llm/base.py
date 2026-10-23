"""The one interface every model provider implements."""

import asyncio
from abc import ABC, abstractmethod


class LLMError(Exception):
    """The provider failed (network, quota, bad key, refused request)."""


class LLMTimeout(LLMError):
    """The provider did not answer in time."""


class LLMNotConfigured(LLMError):
    """A required key or model name is missing from the environment."""


class LLM(ABC):
    name: str
    model: str

    async def complete(
        self,
        system: str,
        text: str,
        *,
        image_jpeg: bytes | None = None,
        json_output: bool = False,
        max_tokens: int = 200,
        timeout: float = 10.0,
    ) -> str:
        """Send one user message (text, optionally with a photo) and return the reply."""
        try:
            return await asyncio.wait_for(
                self._complete(system, text, image_jpeg, json_output, max_tokens, timeout),
                timeout,
            )
        except TimeoutError as e:
            raise LLMTimeout(f"{self.name} took longer than {timeout:.0f}s") from e

    @abstractmethod
    async def _complete(
        self,
        system: str,
        text: str,
        image_jpeg: bytes | None,
        json_output: bool,
        max_tokens: int,
        timeout: float,
    ) -> str: ...
