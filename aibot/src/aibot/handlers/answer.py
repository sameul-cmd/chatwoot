"""Answer a customer from the KB, or hand the conversation to a person (SPEC 13.3-13.5)."""

from __future__ import annotations

import logging
import time

from ..chatwoot import ChatwootError
from ..config import BotConfig
from ..events import IncomingMessage
from ..kbstate import KbState
from ..lang import detect, reply_language
from ..llm import LlmClient, LlmError
from ..messages import answer_message, handoff_message
from ..models import Decision, HandoffReason
from ..policy import post_check, pre_check
from . import Context

log = logging.getLogger("aibot.answer")
HANDOFF_LABEL = "ai-handoff"


async def decide(
    cfg: BotConfig, kb: KbState, llm: LlmClient, text: str, lang: str, bot_turns: int
) -> tuple[Decision, str | None, float | None]:
    """The whole answer-or-hand-off decision for one customer message (shared with `aibot eval`).

    Returns the decision, how the KB was searched and the AI confidence (None where that step did not happen).
    """
    if reason := pre_check(text, bot_turns, cfg):
        return Decision("handoff", reason), None, None
    found = await kb.search(text)
    if not found.chunks:
        return Decision("handoff", "off_topic"), found.mode, None
    try:
        result = await llm.answer(text, found.chunks, lang)
    except LlmError as exc:
        log.warning("handing off after an AI error: %s", exc)
        return Decision("handoff", "llm_error"), found.mode, None
    return post_check(result, {c.id: c.content for c in found.chunks}, cfg), found.mode, result.confidence


class AnswerHandler:
    async def handle(self, event: IncomingMessage, ctx: Context) -> bool:
        started = time.monotonic()
        cfg = ctx.cfg
        lang = (
            reply_language(detect(event.text), cfg.default_language) if event.text else cfg.default_language
        )
        first = not ctx.audit.bot_spoke(event.conversation_id)
        row: dict[str, object] = {
            "conversation_id": event.conversation_id,
            "message_id": event.message_id,
            "language": lang,
            "question": event.text or None,
        }
        decision: Decision
        if not event.text:
            decision = Decision("handoff", "unsupported_message")
        else:
            decision, row["retrieval"], row["confidence"] = await decide(
                cfg, ctx.kb, ctx.llm, event.text, lang, ctx.audit.bot_turns(event.conversation_id)
            )
            if decision.reason == "llm_error":
                row["error"] = "llm_error"
        error = None
        if decision.action == "answer":
            error = await self._send(ctx, event, answer_message(decision.answer, lang, cfg, first))
            row.update(answer=decision.answer, used_ids=list(decision.used_ids))
        else:
            error = await self._hand_off(ctx, event, lang, decision.reason or "ai_handoff", first)
        row.update(
            action=decision.action,
            reason=decision.reason,
            sent=0 if error == "send_failed" else 1,
            error=error or row.get("error"),
            latency_ms=round((time.monotonic() - started) * 1000),
        )
        ctx.audit.record(**row)
        return True

    @staticmethod
    async def _send(ctx: Context, event: IncomingMessage, text: str) -> str | None:
        try:
            await ctx.chatwoot.send_message(event.conversation_id, text)
        except ChatwootError as exc:
            log.error("could not send the reply: %s", exc)
            return "send_failed"
        return None

    async def _hand_off(
        self, ctx: Context, event: IncomingMessage, lang: str, reason: HandoffReason, first: bool
    ) -> str | None:
        """Tell the customer, then open the chat for people; every step is tried even if one fails."""
        cw, conv = ctx.chatwoot, event.conversation_id
        problem = await self._send(ctx, event, handoff_message(reason, lang, ctx.cfg, first))
        steps = [cw.open_conversation(conv), cw.add_labels(conv, [HANDOFF_LABEL])]
        if ctx.cfg.handoff_team_id:
            steps.append(cw.assign_team(conv, ctx.cfg.handoff_team_id))
        steps.append(cw.send_message(conv, f"Handoff reason: {reason}", private=True))
        for step in steps:
            try:
                await step
            except ChatwootError as exc:
                log.error("handoff step failed: %s", exc)
                problem = problem or "handoff_step_failed"
        return problem
