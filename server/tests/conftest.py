import base64
import io
import os

# Keep the module-level app in app.main from touching real keys or files,
# and keep tests the same on machines that have provider keys set.
for _name in list(os.environ):
    if _name.endswith("_API_KEY") or _name in ("ADMIN_KEY", "OPENAI_MODEL", "OPENROUTER_MODEL"):
        del os.environ[_name]
os.environ.update({"LLM_PROVIDER": "fake", "LOG_DB_PATH": ":memory:"})

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.llm.fake import FakeLLM
from app.main import create_app


@pytest.fixture
def fake_llm() -> FakeLLM:
    return FakeLLM()


def make_client(fake_llm: FakeLLM, **overrides) -> TestClient:
    settings = Settings(_env_file=None, llm_provider="fake", log_db_path=":memory:", **overrides)
    return TestClient(create_app(settings, llm=fake_llm))


@pytest.fixture
def client(fake_llm) -> TestClient:
    return make_client(fake_llm)


@pytest.fixture
def jpeg_b64() -> str:
    img = Image.new("RGB", (3000, 2000), (120, 180, 90))
    out = io.BytesIO()
    img.save(out, format="JPEG")
    return base64.b64encode(out.getvalue()).decode()


ASK_BODY = {
    "sessionId": "a1b2c3",
    "recipeId": "salad",
    "recipeName": "Rainbow salad bowl",
    "step": 1,
    "stepText": "Cut half a cucumber into small, bite-sized pieces.",
    "nextStepTitle": "Build your bowl",
    "question": "How small is bite-sized?",
    "acceptedSwaps": ["salad-lemon-dressing"],
    "history": [
        {"from": "assistant", "text": "Step two. Cut half a cucumber."},
        {"from": "user", "text": "How small is bite-sized?"},
    ],
}


def check_body(image: str) -> dict:
    return {
        "sessionId": "a1b2c3",
        "recipeId": "salad",
        "step": 1,
        "stepText": "Cut half a cucumber into small, bite-sized pieces.",
        "doneLooksLike": "The cucumber is chopped into bite-sized pieces.",
        "image": image,
        "source": "glasses",
    }
