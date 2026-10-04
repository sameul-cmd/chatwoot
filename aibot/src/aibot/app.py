"""FastAPI application: /health, the Chatwoot webhook, metrics and the KB reload."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
import os
import time
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, HTTPException, Request

from . import __version__
from .audit import AuditDb
from .chatwoot import ChatwootClient
from .config import BotConfig, load_config
from .events import IncomingMessage, parse_event
from .handlers import Context, Handler
from .handlers.answer import AnswerHandler
from .kbstate import KbState
from .llm import LlmClient

log = logging.getLogger("aibot.app")
SIGNATURE_TOLERANCE = 300  # seconds


def signature_ok(secret: str, timestamp: str, raw: bytes, signature: str, now: float) -> bool:
    """Chatwoot signs `<timestamp>.<raw body>` with HMAC-SHA256 (verified live, EXPLORATION_REPORT 5d)."""
    try:
        if abs(now - int(timestamp)) > SIGNATURE_TOLERANCE:
            return False
    except ValueError:
        return False
    expected = (
        "sha256=" + hmac.new(secret.encode(), f"{timestamp}.".encode() + raw, hashlib.sha256).hexdigest()
    )
    return hmac.compare_digest(expected, signature)


def wired(cfg: BotConfig | None) -> bool:
    return bool(cfg and cfg.webhook_secret and cfg.hmac_secret and cfg.bot_token and cfg.chatwoot_url)


def create_app(
    config: BotConfig | None = None,
    *,
    context: Context | None = None,
    handlers: list[Handler] | None = None,
    clock: Callable[[], float] = time.time,
) -> FastAPI:
    """`context` and `handlers` let tests supply fakes; production builds them from the configuration."""
    if context is None and config is not None and wired(config):
        config.data_dir.mkdir(parents=True, exist_ok=True)
        audit = AuditDb(config.data_dir / "aibot.db")
        llm = LlmClient(config)
        context = Context(config, audit, KbState(config, audit, llm), llm, ChatwootClient(config))
    chain: list[Handler] = handlers if handlers is not None else [AnswerHandler()]

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        task = asyncio.create_task(context.kb.refresh_vectors()) if context else None
        if context:
            context.audit.prune(context.cfg.audit_days)
        yield
        if task:
            task.cancel()

    app = FastAPI(title="aibot", version=__version__, lifespan=lifespan)
    app.state.config = config
    app.state.context = context
    cfg = config or (context.cfg if context else None)

    async def process(ctx: Context, event: IncomingMessage) -> None:
        try:
            for handler in chain:
                if await handler.handle(event, ctx):
                    return
        except Exception as exc:  # noqa: BLE001  (one bad message must never stop the bot)
            log.error("handling a message failed: %s", type(exc).__name__)

    @app.get("/health")
    def health() -> dict[str, object]:
        return {
            "status": "ok",
            "version": __version__,
            "bot_enabled": bool(cfg and cfg.enabled),
            "wired": context is not None,
            "kb_entries": len(context.kb.chunks) if context else 0,
            "embeddings": bool(context and context.kb.vectors),
        }

    @app.post("/webhook/{secret}")
    async def webhook(secret: str, request: Request, background: BackgroundTasks) -> dict[str, str]:
        if context is None or cfg is None or not cfg.webhook_secret or not cfg.hmac_secret:
            raise HTTPException(503, "the bot is not wired to Chatwoot yet (run: opskit bot enable)")
        if not hmac.compare_digest(secret, cfg.webhook_secret.get_secret_value()):
            raise HTTPException(404)
        raw = await request.body()
        if not signature_ok(
            cfg.hmac_secret.get_secret_value(),
            request.headers.get("x-chatwoot-timestamp", ""),
            raw,
            request.headers.get("x-chatwoot-signature", ""),
            clock(),
        ):
            raise HTTPException(401, "bad signature")
        if not cfg.enabled:
            return {"status": "disabled"}
        try:
            event = parse_event(json.loads(raw))
        except (ValueError, AttributeError):
            raise HTTPException(400, "not JSON") from None
        if event is None:
            return {"status": "ignored"}
        if event.account_id != cfg.account_id or (cfg.inboxes and event.inbox_id not in cfg.inboxes):
            return {"status": "ignored"}
        if not context.audit.claim(event.message_id):
            return {"status": "duplicate"}
        background.add_task(process, context, event)
        return {"status": "accepted"}

    @app.get("/metrics")
    def metrics() -> dict[str, object]:
        if context is None:
            raise HTTPException(503)
        return {**context.audit.metrics(), "unanswered": context.audit.unanswered()}

    @app.post("/admin/reload")
    async def reload() -> dict[str, int]:
        """Reload the KB without a restart. The bot is only reachable inside the client's own network."""
        if context is None:
            raise HTTPException(503)
        context.kb.load()
        await context.kb.refresh_vectors()
        return {"kb_entries": len(context.kb.chunks)}

    return app


def app_from_env() -> FastAPI:
    """Entry point for uvicorn: `uvicorn aibot.app:app_from_env --factory`."""
    yaml_path = os.environ.get("AIBOT_CONFIG")
    if not yaml_path and not os.environ.get("AIBOT_LLM_BASE_URL"):
        # Bot not configured for this client yet: serve /health only (bot_enabled=false).
        return create_app(None)
    return create_app(load_config(os.environ, Path(yaml_path) if yaml_path else None))
