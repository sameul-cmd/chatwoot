from fastapi.testclient import TestClient

from aibot.app import create_app
from aibot.config import load_config


def test_health_without_config() -> None:
    r = TestClient(create_app()).get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["bot_enabled"] is False


def test_health_with_config_never_leaks_secrets() -> None:
    cfg = load_config(
        {
            "AIBOT_LLM_BASE_URL": "https://x.example/v1",
            "AIBOT_LLM_MODEL": "m",
            "AIBOT_LLM_TIER_PAID": "true",
            "AIBOT_LLM_API_KEY": "sk-leak-check",
        }
    )
    r = TestClient(create_app(cfg)).get("/health")
    assert r.json()["bot_enabled"] is True
    assert "sk-leak-check" not in r.text
