"""Settings read from environment variables or server/.env."""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

Provider = Literal["claude", "openai", "qwen", "openrouter", "fake"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Which model family answers /ask and /check-step.
    llm_provider: Provider = "claude"

    anthropic_api_key: str = ""
    claude_model: str = "claude-haiku-5-5"

    openai_api_key: str = ""
    openai_model: str = ""

    # Qwen through Alibaba Cloud Model Studio's OpenAI-compatible endpoint.
    # The default is the international (Singapore) region.
    qwen_api_key: str = ""
    qwen_model: str = "qwen-vl-max"
    qwen_base_url: str = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"

    # OpenRouter: one key for models from many companies, through an
    # OpenAI-compatible endpoint. Model ids look like "anthropic/claude-haiku-5.5".
    openrouter_api_key: str = ""
    openrouter_model: str = "anthropic/claude-haiku-5.5"
    openrouter_base_url: str = "https://openrouter.ai/api/v1"

    # The app gives up after 6 s (/ask) and 8 s (/check-step), so the backend
    # stops waiting for the model a little earlier and returns a clear error.
    ask_timeout_s: float = 5.0
    check_timeout_s: float = 7.0

    # Photos are shrunk to this many pixels on the long side before they are
    # sent to the model: faster, cheaper, and still enough to judge a step.
    max_image_side: int = 1024

    # Optional shared secret. When set, every request needs an X-API-Key header.
    app_api_key: str = ""
    # Optional key for GET /export/events.csv. The export is off when empty.
    admin_key: str = ""

    log_db_path: str = "data/cookalong.db"
    cors_origins: str = "*"


@lru_cache
def get_settings() -> Settings:
    return Settings()
