import pytest

from aibot.app import app_from_env
from aibot.config import ConfigError


def test_unconfigured_bot_serves_health_only(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in ("AIBOT_CONFIG", "AIBOT_LLM_BASE_URL"):
        monkeypatch.delenv(name, raising=False)
    app = app_from_env()
    assert app.state.config is None


def test_half_configured_bot_fails_loudly(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("AIBOT_CONFIG", raising=False)
    monkeypatch.setenv("AIBOT_LLM_BASE_URL", "https://x.example/v1")
    monkeypatch.delenv("AIBOT_LLM_MODEL", raising=False)
    monkeypatch.setenv("AIBOT_LLM_TIER_PAID", "true")
    with pytest.raises(ConfigError):
        app_from_env()
