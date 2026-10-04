"""Answer a customer from the KB, or hand the conversation to a person (SPEC 13.3-13.5)."""

from __future__ import annotations

import logging
import time

from ..chatwoot import ChatwootError
from ..events import IncomingMessage
from ..lang import detect, reply_language
from ..llm import LlmError
from ..messages import answer_message, handoff_message
from ..models import Decision, HandoffReason
from ..policy import post_check, pre_check
from . import Context

log = logging.getLogger("aibot.answer")
HANDOFF_LABEL = "ai-handoff"


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
        elif reason := pre_check(event.text, ctx.audit.bot_turns(event.conversation_id), cfg):
            decision = Decision("handoff", reason)
        else:
            decision = await self._decide(event, ctx, lang, row)
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

    async def _decide(
        self, event: IncomingMessage, ctx: Context, lang: str, row: dict[str, object]
    ) -> Decision:
        found = await ctx.kb.search(event.text)
        row["retrieval"] = found.mode
        if not found.chunks:
            return Decision("handoff", "off_topic")
        try:
            result = await ctx.llm.answer(event.text, found.chunks, lang)
        except LlmError as exc:
            log.warning("handing off after an AI error: %s", exc)
            row["error"] = "llm_error"
            return Decision("handoff", "llm_error")
        row["confidence"] = result.confidence
        return post_check(result, {c.id: c.content for c in found.chunks}, ctx.cfg)

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
