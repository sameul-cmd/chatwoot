import hashlib
import hmac
import json
import logging
import time
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from aibot.app import create_app
from aibot.audit import AuditDb
from aibot.chatwoot import ChatwootClient
from aibot.config import BotConfig, EmbeddingSettings, LLMSettings
from aibot.handlers import Context
from aibot.kbstate import KbState
from aibot.llm import LlmClient

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "webhook_message_created.json").read_text())
FAQ = """
items:
  - key: delivery_time
    question: {en: "How long does delivery take?", bn: "ডেলিভারিতে কত সময় লাগে?"}
    answer: {en: "Delivery takes two to three days inside Dhaka.", bn: "ঢাকার ভেতরে ডেলিভারিতে দুই থেকে তিন দিন লাগে।"}
"""
HMAC = "hmac-secret"
GOOD = {"answer": "Delivery takes two to three days.", "confidence": 0.9, "used_ids": ["faq:delivery_time"]}


class World:
    """A fake Chatwoot and a fake AI, recording every call."""

    def __init__(self, tmp: Path, **cfg: object) -> None:
        (tmp / "kb").mkdir()
        (tmp / "kb" / "faq.yaml").write_text(FAQ, encoding="utf-8")
        self.cw: list[tuple[str, dict[str, Any]]] = []
        self.llm_calls: list[dict[str, Any]] = []
        self.llm_reply: dict[str, Any] | int = GOOD
        self.cw_fail: set[str] = set()
        self.clock = 1_000_000.0
        self.cfg = BotConfig(
            llm=LLMSettings(base_url="https://llm.example/v1", model="m", api_key="k"),  # type: ignore[arg-type]
            mode="demo",
            business_name="Demo Shop",
            kb_dir=tmp / "kb",
            data_dir=tmp,
            chatwoot_url="http://rails:3000",
            bot_token="bot-token",
            webhook_secret="s3cret",
            hmac_secret=HMAC,
            handoff_team_id=7,
            account_id=1,  # type: ignore[arg-type]
            **cfg,  # type: ignore[arg-type]
        )
        llm = LlmClient(self.cfg, httpx.AsyncClient(transport=httpx.MockTransport(self._llm)), retry_delay=0)
        cw = ChatwootClient(self.cfg, httpx.AsyncClient(transport=httpx.MockTransport(self._cw)))
        self.audit = AuditDb(tmp / "aibot.db")
        self.ctx = Context(self.cfg, self.audit, KbState(self.cfg, self.audit, llm), llm, cw)
        self.http = TestClient(create_app(self.cfg, context=self.ctx, clock=lambda: self.clock))

    def _llm(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if request.url.path.endswith("/embeddings"):
            return httpx.Response(
                200,
                json={"data": [{"index": i, "embedding": [1.0, 0.0]} for i, _ in enumerate(body["input"])]},
            )
        self.llm_calls.append(body)
        if isinstance(self.llm_reply, int):
            return httpx.Response(self.llm_reply)
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(self.llm_reply)}}]})

    def _cw(self, request: httpx.Request) -> httpx.Response:
        kind = request.url.path.rsplit("/", 1)[-1]
        self.cw.append((kind, json.loads(request.content)))
        return httpx.Response(500 if kind in self.cw_fail else 200, json={})

    def post(
        self,
        payload: dict[str, Any],
        *,
        secret: str = "s3cret",  # noqa: S107
        sig_secret: str = HMAC,
        ts: float | None = None,
    ) -> httpx.Response:
        raw = json.dumps(payload).encode()
        stamp = str(int(self.clock if ts is None else ts))
        sig = (
            "sha256=" + hmac.new(sig_secret.encode(), f"{stamp}.".encode() + raw, hashlib.sha256).hexdigest()
        )
        headers = {
            "x-chatwoot-timestamp": stamp,
            "x-chatwoot-signature": sig,
            "content-type": "application/json",
        }
        return self.http.post(f"/webhook/{secret}", content=raw, headers=headers)

    def say(self, text: str, *, mid: int, conv: int = 1, **over: Any) -> httpx.Response:
        payload = {
            **FIXTURE,
            "id": mid,
            "content": text,
            "conversation": {**FIXTURE["conversation"], "id": conv, "status": "pending"},
            **over,
        }
        return self.post(payload)

    def sent(self, kind: str = "messages") -> list[dict[str, Any]]:
        return [body for k, body in self.cw if k == kind]


@pytest.fixture
def world(tmp_path: Path) -> World:
    return World(tmp_path)


def test_the_real_payload_fixture_is_an_incoming_pending_message() -> None:
    assert FIXTURE["event"] == "message_created" and FIXTURE["message_type"] == "incoming"


def test_wrong_secret_bad_signature_and_old_timestamp_are_refused(world: World) -> None:
    assert world.post(FIXTURE, secret="nope").status_code == 404
    assert world.post(FIXTURE, sig_secret="wrong").status_code == 401
    assert world.post(FIXTURE, ts=world.clock - 600).status_code == 401
    assert world.cw == [] and world.llm_calls == []


def test_a_bot_that_is_not_wired_says_so() -> None:
    cfg = BotConfig(llm=LLMSettings(base_url="https://x.example/v1", model="m"), mode="demo")
    r = TestClient(create_app(cfg)).post("/webhook/anything", content=b"{}")
    assert r.status_code == 503 and "opskit bot enable" in r.text


@pytest.mark.parametrize(
    "over",
    [
        {"message_type": "outgoing"},
        {"message_type": "template"},
        {"private": True},
        {"event": "conversation_updated"},
        {"content": ""},
        {"account": {"id": 2}},
    ],
)
def test_events_the_bot_must_not_act_on_are_ignored(world: World, over: dict[str, Any]) -> None:
    r = world.post({**FIXTURE, "id": 50, **over})
    assert r.json()["status"] == "ignored" and world.cw == [] and world.llm_calls == []


def test_a_conversation_a_person_already_took_over_is_ignored(world: World) -> None:
    r = world.post({**FIXTURE, "conversation": {**FIXTURE["conversation"], "status": "open"}})
    assert r.json()["status"] == "ignored" and world.cw == []


def test_only_the_configured_inboxes_are_served(tmp_path: Path) -> None:
    w = World(tmp_path, inboxes=[99])
    assert w.say("How long does delivery take?", mid=1).json()["status"] == "ignored"
    assert w.cw == []


def test_kb_question_is_answered_with_the_automation_notice_first_time_only(world: World) -> None:
    assert world.say("How long does delivery take?", mid=1).json()["status"] == "accepted"
    first = world.sent()[0]
    assert (
        first["content"].startswith("Hi! I'm Demo Shop's automated assistant.") and first["private"] is False
    )
    assert (
        first["content"].endswith("Delivery takes two to three days.") and world.sent("toggle_status") == []
    )
    world.say("And how long does delivery take to Dhaka?", mid=2)
    assert "automated assistant" not in world.sent()[1]["content"]
    assert world.audit.bot_turns(1) == 2


def test_a_retried_delivery_is_answered_once(world: World) -> None:
    world.say("How long does delivery take?", mid=5)
    assert world.say("How long does delivery take?", mid=5).json()["status"] == "duplicate"
    assert len(world.sent()) == 1 and len(world.llm_calls) == 1


def test_bangla_question_gets_a_bangla_prompt(world: World) -> None:
    world.say("ডেলিভারিতে কত সময় লাগে?", mid=1)
    assert "Bangla" in world.llm_calls[0]["messages"][0]["content"]


def test_human_request_hands_off_completely(world: World) -> None:
    world.say("মানুষ চাই", mid=1)
    assert world.llm_calls == []
    text = world.sent()[0]["content"]
    assert "স্বয়ংক্রিয় সহকারী" in text and "সদস্যের" in text  # Bangla customer, Bangla reply
    assert world.sent("toggle_status") == [{"status": "open"}]
    assert world.sent("labels") == [{"labels": ["ai-handoff"]}]
    assert world.sent("assignments") == [{"team_id": 7}]
    note = world.sent()[1]
    assert note["private"] is True and note["content"] == "Handoff reason: human_request"
    assert world.audit.metrics()["handoff_reasons"] == {"human_request": 1}


def test_english_human_request_and_complaint(world: World) -> None:
    world.say("Can I talk to a human please", mid=1, conv=1)
    world.say("This is a complaint, I want a refund", mid=2, conv=2)
    assert world.audit.metrics()["handoff_reasons"] == {"human_request": 1, "upset": 1}
    assert world.llm_calls == []


def test_off_topic_is_handed_off_without_asking_the_ai(world: World) -> None:
    world.say("What is the capital of France?", mid=1)
    assert world.llm_calls == [] and "only help with questions about Demo Shop" in world.sent()[0]["content"]
    assert world.audit.metrics()["handoff_reasons"] == {"off_topic": 1}


def test_the_fourth_message_is_handed_off(world: World) -> None:
    for i in range(1, 4):
        world.say("How long does delivery take?", mid=i)
    assert world.audit.bot_turns(1) == 3 and world.sent("toggle_status") == []
    world.say("How long does delivery take?", mid=4)
    assert world.sent("toggle_status") == [{"status": "open"}]
    assert world.audit.metrics()["handoff_reasons"] == {"max_turns": 1}


@pytest.mark.parametrize(
    ("reply", "reason"),
    [
        (503, "llm_error"),
        ({**GOOD, "confidence": 0.3}, "low_confidence"),
        ({**GOOD, "answer": "Delivery takes five days."}, "invented_fact"),
        ({**GOOD, "used_ids": []}, "no_snippet"),
        ({**GOOD, "handoff": True}, "ai_handoff"),
        ({**GOOD, "upset": True}, "upset"),
    ],
)
def test_ai_failures_and_weak_answers_hand_off(
    world: World, reply: dict[str, Any] | int, reason: str
) -> None:
    world.llm_reply = reply
    world.say("How long does delivery take?", mid=1)
    assert world.audit.metrics()["handoff_reasons"] == {reason: 1}
    assert world.sent("toggle_status") == [{"status": "open"}]


def test_an_attachment_without_text_is_handed_off(world: World) -> None:
    world.post({**FIXTURE, "id": 9, "content": None, "attachments": [{"file_type": "image"}]})
    assert world.audit.metrics()["handoff_reasons"] == {"unsupported_message": 1} and world.llm_calls == []


def test_kill_switch_does_nothing(tmp_path: Path) -> None:
    w = World(tmp_path, enabled=False)
    assert w.say("How long does delivery take?", mid=1).json()["status"] == "disabled"
    assert w.cw == [] and w.llm_calls == []


def test_a_failing_chatwoot_does_not_crash_and_the_rest_of_the_handoff_still_runs(world: World) -> None:
    world.cw_fail = {"labels"}
    world.say("human please", mid=1)
    kinds = [k for k, _ in world.cw]
    assert "toggle_status" in kinds and "assignments" in kinds
    world.cw_fail = {"messages"}
    world.say("How long does delivery take?", mid=2, conv=2)
    assert world.audit.bot_turns(2) == 0  # nothing was sent, so it does not count as a bot turn


def test_no_message_text_in_any_log_line(world: World, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG)
    marker = "ZEBRA-7731-marker"
    world.say(f"How long does delivery take {marker}?", mid=1)
    world.say(f"I want a refund {marker}", mid=2, conv=2)
    world.llm_reply = 503
    world.say(f"delivery {marker}", mid=3, conv=3)
    world.cw_fail = {"messages", "toggle_status"}
    world.say(f"human {marker}", mid=4, conv=4)
    ours = "\n".join(r.getMessage() for r in caplog.records if "testserver" not in r.getMessage())
    assert marker not in ours and "bot-token" not in ours and "s3cret" not in ours


def test_metrics_numbers_and_unanswered_list_match_a_scripted_set(world: World) -> None:
    world.say("How long does delivery take?", mid=1, conv=1)
    world.say("How long does delivery take?", mid=2, conv=2)
    world.say("What is the capital of France?", mid=3, conv=3)
    world.say("What is the capital of France?", mid=4, conv=4)
    world.say("What is the capital of Spain?", mid=5, conv=5)
    world.say("talk to a human", mid=6, conv=6)
    data = world.http.get("/metrics").json()
    assert data["answered"] == 2 and data["handed_off"] == 4 and data["errors"] == 0
    assert data["handoff_reasons"] == {"off_topic": 3, "human_request": 1}
    assert data["unanswered"][0] == {"question": "What is the capital of France?", "count": 2}
    assert {u["question"] for u in data["unanswered"]} == {
        "What is the capital of France?",
        "What is the capital of Spain?",
    }


def test_audit_rows_older_than_audit_days_are_pruned(world: World) -> None:
    world.say("How long does delivery take?", mid=1)
    world.audit.record(at=time.time() - 40 * 86400, conversation_id=9, message_id=9, action="answer", sent=1)
    assert world.audit.prune(30) == 1 and world.audit.bot_turns(9) == 0 and world.audit.bot_turns(1) == 1


def test_kb_reload_picks_up_new_answers_without_a_restart(world: World, tmp_path: Path) -> None:
    assert world.http.get("/health").json()["kb_entries"] == 1
    (tmp_path / "kb" / "more.md").write_text(
        "# Opening hours\nWe are open every day from morning to evening.\n", encoding="utf-8"
    )
    assert world.http.post("/admin/reload").json() == {"kb_entries": 2}


def test_embedding_vectors_are_cached_and_failures_fall_back_to_keywords(tmp_path: Path) -> None:
    w = World(tmp_path, embeddings=EmbeddingSettings(model="emb"))
    import asyncio

    asyncio.run(w.ctx.kb.refresh_vectors())
    assert w.ctx.kb.vectors and w.audit.load_vectors("emb")
    calls = len(w.llm_calls)
    asyncio.run(w.ctx.kb.refresh_vectors())
    assert len(w.llm_calls) == calls  # nothing re-embedded; unchanged entries come from the cache
    w.ctx.llm.http = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    w.ctx.llm.retry_delay = 0
    assert asyncio.run(w.ctx.kb.search("How long does delivery take?")).mode == "bm25"
