from pathlib import Path

import pytest

from aibot.config import ConfigError, load_config

BASE_ENV = {
    "AIBOT_LLM_BASE_URL": "https://api.example.com/v1/",
    "AIBOT_LLM_MODEL": "some-model",
    "AIBOT_LLM_TIER_PAID": "true",
    "AIBOT_LLM_API_KEY": "sk-super-secret-value",
}


def test_env_only_config_loads_with_defaults() -> None:
    cfg = load_config(BASE_ENV)
    assert cfg.llm.base_url == "https://api.example.com/v1"  # trailing slash removed
    assert cfg.llm.effort == "medium"
    assert cfg.llm.effort_param == "reasoning_effort"
    assert cfg.min_confidence == 0.7
    assert cfg.max_bot_turns == 3
    assert cfg.llm.api_key is not None
    assert cfg.llm.api_key.get_secret_value() == "sk-super-secret-value"


def test_client_mode_requires_paid_flag() -> None:
    env = {k: v for k, v in BASE_ENV.items() if k != "AIBOT_LLM_TIER_PAID"}
    with pytest.raises(ConfigError, match="AIBOT_LLM_TIER_PAID"):
        load_config(env)


def test_demo_mode_does_not_need_paid_flag() -> None:
    env = {k: v for k, v in BASE_ENV.items() if k != "AIBOT_LLM_TIER_PAID"} | {"AIBOT_MODE": "demo"}
    assert load_config(env).mode == "demo"


@pytest.mark.parametrize("effort", ["none", "low", "medium", "high", "max"])
def test_effort_levels_accepted(effort: str) -> None:
    assert load_config(BASE_ENV | {"AIBOT_LLM_EFFORT": effort}).llm.effort == effort


def test_unknown_effort_rejected() -> None:
    with pytest.raises(ConfigError, match="effort"):
        load_config(BASE_ENV | {"AIBOT_LLM_EFFORT": "ultra"})


def test_missing_model_rejected() -> None:
    env = {k: v for k, v in BASE_ENV.items() if k != "AIBOT_LLM_MODEL"}
    with pytest.raises(ConfigError, match="model"):
        load_config(env)


def test_bad_base_url_rejected() -> None:
    with pytest.raises(ConfigError, match="base_url"):
        load_config(BASE_ENV | {"AIBOT_LLM_BASE_URL": "ftp://x"})


def test_api_key_never_in_repr() -> None:
    cfg = load_config(BASE_ENV | {"AIBOT_BOT_TOKEN": "bot-token-123", "AIBOT_WEBHOOK_SECRET": "whsec-456"})
    text = repr(cfg) + str(cfg) + cfg.model_dump_json()
    for secret in ("sk-super-secret-value", "bot-token-123", "whsec-456"):
        assert secret not in text


def test_custom_key_env_name(tmp_path: Path) -> None:
    f = tmp_path / "bot.yaml"
    f.write_text(
        "llm:\n  base_url: http://localhost:11434/v1\n  model: llama3\n  api_key_env: MY_OWN_KEY\n"
        "min_confidence: 0.8\n",
        encoding="utf-8",
    )
    cfg = load_config({"AIBOT_LLM_TIER_PAID": "true", "MY_OWN_KEY": "k-1234567"}, f)
    assert cfg.min_confidence == 0.8
    assert cfg.llm.api_key is not None
    assert cfg.llm.api_key.get_secret_value() == "k-1234567"


def test_env_overrides_yaml(tmp_path: Path) -> None:
    f = tmp_path / "bot.yaml"
    f.write_text("llm:\n  base_url: http://a.example/v1\n  model: from-yaml\n", encoding="utf-8")
    cfg = load_config({"AIBOT_LLM_TIER_PAID": "true", "AIBOT_LLM_MODEL": "from-env"}, f)
    assert cfg.llm.model == "from-env"


def test_unknown_yaml_field_rejected(tmp_path: Path) -> None:
    f = tmp_path / "bot.yaml"
    f.write_text("llm:\n  base_url: http://a.example/v1\n  model: m\nbogus: 1\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="bogus"):
        load_config({"AIBOT_LLM_TIER_PAID": "true"}, f)
