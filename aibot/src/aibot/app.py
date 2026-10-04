"""FastAPI application. Phase 1: health endpoint only; the webhook arrives in Phase 8."""

from __future__ import annotations

import os

from fastapi import FastAPI

from . import __version__
from .config import BotConfig, load_config


def create_app(config: BotConfig | None = None) -> FastAPI:
    app = FastAPI(title="aibot", version=__version__)
    app.state.config = config

    @app.get("/health")
    def health() -> dict[str, object]:
        cfg: BotConfig | None = app.state.config
        return {"status": "ok", "version": __version__, "bot_enabled": bool(cfg and cfg.enabled)}

    return app


def app_from_env() -> FastAPI:
    """Entry point for uvicorn: `uvicorn aibot.app:app_from_env --factory`."""
    from pathlib import Path

    yaml_path = os.environ.get("AIBOT_CONFIG")
    if not yaml_path and not os.environ.get("AIBOT_LLM_BASE_URL"):
        # Bot not configured for this client yet: serve /health only (bot_enabled=false).
        return create_app(None)
    return create_app(load_config(os.environ, Path(yaml_path) if yaml_path else None))
