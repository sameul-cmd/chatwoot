"""Configuration for aibot: bot.yaml + environment, with the BYOK LLM settings (ADR-011).

The API key is only ever read from the environment variable named by `llm.api_key_env`
and is wrapped in SecretStr so it never shows up in repr() or logs.
"""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator

Effort = Literal["none", "low", "medium", "high", "max"]
Mode = Literal["demo", "client"]


class ConfigError(ValueError):
    """Raised when the configuration is invalid or violates a policy (e.g. client mode without paid key)."""


class LLMSettings(BaseModel):
    """Any OpenAI-compatible endpoint, supplied by the owner (BYOK)."""

    model_config = ConfigDict(extra="forbid")

    base_url: str
    model: str = Field(min_length=1)
    api_key_env: str = Field(default="AIBOT_LLM_API_KEY", pattern=r"^[A-Z][A-Z0-9_]*$")
    effort: Effort = "medium"
    effort_param: str = Field(default="reasoning_effort", min_length=1)
    max_output_tokens: int = Field(default=800, ge=16, le=32000)
    api_key: SecretStr | None = None

    @field_validator("base_url")
    @classmethod
    def _http_url(cls, v: str) -> str:
        if not v.startswith(("http://", "https://")):
            raise ValueError("base_url must start with http:// or https://")
        return v.rstrip("/")


class HandoffKeywords(BaseModel):
    model_config = ConfigDict(extra="forbid")

    en: list[str] = Field(default_factory=lambda: ["human", "agent", "talk to a person"])
    bn: list[str] = Field(default_factory=lambda: ["মানুষ", "এজেন্ট"])


class BotConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool = True
    inboxes: list[int] = Field(default_factory=list)
    handoff_team: str | None = None
    default_language: Literal["bn", "en"] = "bn"
    min_confidence: float = Field(default=0.7, ge=0, le=1)
    max_bot_turns: int = Field(default=3, ge=1, le=20)
    audit_days: int = Field(default=30, ge=1, le=365)
    handoff_keywords: HandoffKeywords = Field(default_factory=HandoffKeywords)
    llm: LLMSettings
    mode: Mode = "client"
    llm_tier_paid: bool = False
    chatwoot_url: str | None = None
    bot_token: SecretStr | None = None
    webhook_secret: SecretStr | None = None


_ENV_TO_LLM = {
    "AIBOT_LLM_BASE_URL": "base_url",
    "AIBOT_LLM_MODEL": "model",
    "AIBOT_LLM_EFFORT": "effort",
    "AIBOT_LLM_EFFORT_PARAM": "effort_param",
    "AIBOT_LLM_API_KEY_ENV": "api_key_env",
}


def _truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes"}


def load_config(env: Mapping[str, str], yaml_path: Path | None = None) -> BotConfig:
    """Build the config from an optional bot.yaml and the environment (env wins)."""
    data: dict[str, object] = {}
    if yaml_path is not None:
        loaded = yaml.safe_load(yaml_path.read_text(encoding="utf-8")) or {}
        if not isinstance(loaded, dict):
            raise ConfigError(f"{yaml_path}: top level must be a mapping")
        data = dict(loaded)

    llm: dict[str, object] = dict(data.get("llm") or {})  # type: ignore[call-overload]
    for env_name, field in _ENV_TO_LLM.items():
        if env.get(env_name):
            llm[field] = env[env_name]
    data["llm"] = llm

    if env.get("AIBOT_MODE"):
        data["mode"] = env["AIBOT_MODE"]
    data["llm_tier_paid"] = _truthy(env.get("AIBOT_LLM_TIER_PAID"))
    for env_name, field in (
        ("AIBOT_CHATWOOT_URL", "chatwoot_url"),
        ("AIBOT_BOT_TOKEN", "bot_token"),
        ("AIBOT_WEBHOOK_SECRET", "webhook_secret"),
    ):
        if env.get(env_name):
            data[field] = env[env_name]

    try:
        cfg = BotConfig.model_validate(data)
    except ValueError as exc:  # pydantic.ValidationError is a ValueError
        raise ConfigError(str(exc)) from exc

    key = env.get(cfg.llm.api_key_env)
    if key:
        cfg.llm.api_key = SecretStr(key)

    # SPEC 13.6: client data may only go to a paid-tier or owner-owned key. The owner states this explicitly.
    if cfg.mode == "client" and not cfg.llm_tier_paid:
        raise ConfigError("client mode requires AIBOT_LLM_TIER_PAID=true (paid-tier or owner-owned LLM key)")
    return cfg
