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
        value = value.strip()
        if not value:
            raise LLMNotConfigured(f"{provider} needs {env_name} in server/.env")
        # Real keys are long. A placeholder left in a system environment
        # variable overrides server/.env, so name both places.
        if env_name.endswith("_KEY") and len(value) < 20:
            raise LLMNotConfigured(
                f"{env_name} is only {len(value)} characters, so it isn't a real key. "
                "Check server/.env and your system environment variables, which take priority."
            )
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
    if provider == "openrouter":
        return OpenAICompatLLM(
            name="openrouter",
            api_key=need(settings.openrouter_api_key, "OPENROUTER_API_KEY"),
            model=settings.openrouter_model,
            base_url=settings.openrouter_base_url,
            native_openai=False,
            # Shown on the OpenRouter usage page.
            headers={"X-Title": "CookAlong"},
            # Some models (Claude Haiku 5.5 among them) decide for themselves
            # whether to think first. Thinking used up max_tokens and cut
            # replies off mid-sentence, and it adds about a second. Short
            # spoken answers don't need it.
            extra_body={"reasoning": {"enabled": False}},
        )
    if provider == "fake":
        return FakeLLM()
    raise LLMNotConfigured(f"unknown LLM_PROVIDER {provider!r}")
