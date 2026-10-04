"""Reading a Chatwoot webhook: which events the bot acts on."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class IncomingMessage:
    message_id: int
    conversation_id: int
    account_id: int
    inbox_id: int
    text: str
    has_attachments: bool


def parse_event(payload: dict[str, Any]) -> IncomingMessage | None:
    """The customer's message the bot should answer, or None for everything else.

    Chatwoot also sends the bot its own replies, the widget's template messages, private notes and
    conversations that a person already took over: all of those are ignored.
    """
    if payload.get("event") != "message_created":
        return None
    if payload.get("message_type") != "incoming" or payload.get("private"):
        return None
    conversation = payload.get("conversation") or {}
    if conversation.get("status") != "pending":
        return None
    text = (payload.get("content") or "").strip()
    attachments = bool(payload.get("attachments"))
    if not text and not attachments:
        return None
    try:
        return IncomingMessage(
            message_id=int(payload["id"]),
            conversation_id=int(conversation["id"]),
            account_id=int(payload["account"]["id"]),
            inbox_id=int(payload["inbox"]["id"]),
            text=text,
            has_attachments=attachments,
        )
    except (KeyError, TypeError, ValueError):
        return None
