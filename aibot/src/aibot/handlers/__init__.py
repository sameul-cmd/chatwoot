"""Handlers: the webhook offers each customer message to an ordered list; V1 has the answer handler only.

A V2 add-on (order capture, booking, ...) is a new handler placed before the answer handler;
app.py does not change.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from ..audit import AuditDb
from ..chatwoot import ChatwootClient
from ..config import BotConfig
from ..events import IncomingMessage
from ..kbstate import KbState
from ..llm import LlmClient


@dataclass
class Context:
    cfg: BotConfig
    audit: AuditDb
    kb: KbState
    llm: LlmClient
    chatwoot: ChatwootClient


class Handler(Protocol):
    async def handle(self, event: IncomingMessage, ctx: Context) -> bool:
        """Return True when the message has been dealt with."""
