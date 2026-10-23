"""Check each provider builds the request its API expects, without calling it."""

import asyncio
from types import SimpleNamespace

import pytest

from app.config import Settings
from app.llm import LLMNotConfigured, build_llm
from app.llm.claude import ClaudeLLM
from app.llm.openai_compat import OpenAICompatLLM


def settings(**kw) -> Settings:
    return Settings(_env_file=None, **kw)


def test_each_provider_needs_its_key():
    for provider, env in [("claude", "ANTHROPIC"), ("openai", "OPENAI"), ("qwen", "QWEN")]:
        with pytest.raises(LLMNotConfigured, match=env):
            build_llm(settings(), provider)


def test_openai_needs_a_model_name():
    with pytest.raises(LLMNotConfigured, match="OPENAI_MODEL"):
        build_llm(settings(openai_api_key="k"), "openai")


def test_qwen_uses_the_compatible_endpoint():
    llm = build_llm(settings(qwen_api_key="k"), "qwen")
    assert isinstance(llm, OpenAICompatLLM)
    assert "compatible-mode" in str(llm._client.base_url)


def test_claude_request_shape():
    llm = ClaudeLLM(api_key="k", model="claude-haiku-5-5")
    sent = {}

    async def create(**kwargs):
        sent.update(kwargs)
        return SimpleNamespace(content=[SimpleNamespace(type="text", text="ok")])

    llm._client = SimpleNamespace(messages=SimpleNamespace(create=create))
    out = asyncio.run(llm.complete("sys", "hi", image_jpeg=b"\xff\xd8", timeout=5))
    assert out == "ok"
    assert sent["system"] == "sys" and sent["model"] == "claude-haiku-5-5"
    content = sent["messages"][0]["content"]
    assert content[0]["type"] == "image" and content[0]["source"]["media_type"] == "image/jpeg"
    assert content[1] == {"type": "text", "text": "hi"}


@pytest.mark.parametrize("native", [True, False])
def test_openai_compatible_request_shape(native):
    llm = OpenAICompatLLM(name="x", api_key="k", model="m", native_openai=native)
    sent = {}

    async def create(**kwargs):
        sent.update(kwargs)
        msg = SimpleNamespace(content='{"status":"done","say":"ok"}')
        return SimpleNamespace(choices=[SimpleNamespace(message=msg)])

    llm._client = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create)))
    asyncio.run(llm.complete("sys", "hi", image_jpeg=b"\xff\xd8", json_output=True, timeout=5))

    assert sent["messages"][0] == {"role": "system", "content": "sys"}
    parts = sent["messages"][1]["content"]
    assert parts[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    if native:
        assert "max_completion_tokens" in sent and sent["response_format"]["type"] == "json_object"
    else:
        assert "max_tokens" in sent and "response_format" not in sent
