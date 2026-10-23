"""Pick the model provider named by LLM_PROVIDER."""

from ..config import Settings
from .base import LLM, LLMError, LLMNotConfigured, LLMTimeout
from .claude import ClaudeLLM
from .fake import FakeLLM
from .openai_compat import OpenAICompatLLM

__all__ = ["LLM", "LLMError", "LLMNotConfigured", "LLMTimeout", "build_llm"]


def build_llm(settings: Settings, provider: str | None = None) -> LLM:
    provider = provider or settings.llm_provider

    def need(value: str, env_name: str) -> str:
        if not value:
            raise LLMNotConfigured(f"{provider} needs {env_name} in server/.env")
        return value

    if provider == "claude":
        return ClaudeLLM(
            api_key=need(settings.anthropic_api_key, "ANTHROPIC_API_KEY"),
            model=settings.claude_model,
        )
    if provider == "openai":
        return OpenAICompatLLM(
            name="openai",
            api_key=need(settings.openai_api_key, "OPENAI_API_KEY"),
            # No default: OpenAI renames models often, so pick a current
            # vision-capable one explicitly.
            model=need(settings.openai_model, "OPENAI_MODEL"),
            native_openai=True,
        )
    if provider == "qwen":
        return OpenAICompatLLM(
            name="qwen",
            api_key=need(settings.qwen_api_key, "QWEN_API_KEY"),
            model=settings.qwen_model,
            base_url=settings.qwen_base_url,
            native_openai=False,
        )
    if provider == "fake":
        return FakeLLM()
    raise LLMNotConfigured(f"unknown LLM_PROVIDER {provider!r}")
