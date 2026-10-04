import asyncio
import json
from pathlib import Path

import httpx

from aibot.audit import AuditDb
from aibot.config import BotConfig, LLMSettings
from aibot.eval import Case, Report, format_report, load_cases, run_eval, score
from aibot.kbstate import KbState
from aibot.llm import LlmClient
from aibot.models import Decision

DEMO = Path(__file__).parent.parent / "demo"


def answer(text: str) -> Decision:
    return Decision("answer", None, text, ("faq:x",))


def handoff(reason: str = "off_topic") -> Decision:
    return Decision("handoff", reason)  # type: ignore[arg-type]


def test_scoring_of_every_outcome() -> None:
    ask = Case(
        "c", "q", "answer", must_include=(("2 to 3 days", "২ থেকে ৩ দিন"),), must_not_include=("free",)
    )
    assert score(ask, answer("It takes 2 to 3 days."))[0] == "correct"
    assert score(ask, answer("৩ দিন, মানে ২ থেকে ৩ দিন"))[0] == "correct"
    assert score(ask, answer("It takes a week."))[0] == "wrong"
    assert score(ask, answer("2 to 3 days and it is free"))[0] == "wrong"
    assert score(ask, handoff()) == ("handed_off", "handed off (off_topic) instead of answering")
    hand = Case("h", "q", "handoff", reason="human_request")
    assert score(hand, handoff("human_request"))[0] == "correct"
    assert score(hand, handoff("off_topic"))[0] == "wrong"
    assert score(hand, answer("sure"))[0] == "wrong"
    assert score(Case("h2", "q", "handoff"), handoff("upset"))[0] == "correct"


def report(outcomes: dict[str, str], critical: list[str] | None = None) -> Report:
    return Report(outcomes=outcomes, details={k: "d" for k in outcomes}, critical_wrong=critical or [])


def test_gate_needs_enough_questions_no_critical_wrong_and_ninety_percent() -> None:
    twenty = {f"c{i}": "correct" for i in range(20)}
    assert report(twenty).gate() == (True, [])
    assert report({f"c{i}": "correct" for i in range(19)}).gate()[0] is False
    assert report({**twenty, "c0": "wrong"}, ["c0"]).gate()[0] is False
    ninety = {**twenty, "c0": "handed_off", "c1": "handed_off"}
    assert report(ninety).gate()[0] is True  # handed off counts as acceptable
    eighty = {**twenty, **{f"c{i}": "wrong" for i in range(3)}}
    ok, problems = report(eighty).gate()
    assert not ok and "85%" in problems[0]


def test_report_lists_misses_but_never_the_passes() -> None:
    text = format_report(report({**{f"c{i}": "correct" for i in range(20)}, "bad": "wrong"}, ["bad"]))
    assert (
        "WRONG      bad" in text
        and "c0" not in text
        and "GATE FAILED" in text
        and "wrong price/policy 1" in text
    )


def test_demo_test_set_is_valid_and_big_enough() -> None:
    cases = load_cases(DEMO / "kb" / "eval.yaml")
    assert len(cases) >= 20 and len({c.id for c in cases}) == len(cases)
    kinds = {(c.expect, c.reason) for c in cases}
    assert (
        ("handoff", "human_request") in kinds
        and ("handoff", "upset") in kinds
        and ("handoff", "off_topic") in kinds
    )


def scripted_ai(mode: str) -> LlmClient:
    """A scripted AI: 'good' answers from the first entry it is shown; 'always' invents; 'down' fails."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/embeddings"):
            return httpx.Response(500)
        if mode == "down":
            return httpx.Response(503)
        user = json.loads(request.content)["messages"][1]["content"]
        first = user.split("[", 1)[1].split("]", 1)[0]
        body = {
            "answer": "It takes 2 to 3 days. The price is 999 taka." if mode == "invent" else "2 to 3 days",
            "confidence": 0.9,
            "used_ids": [first],
        }
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(body)}}]})

    cfg = BotConfig(
        llm=LLMSettings(base_url="https://x.example/v1", model="m"),
        mode="demo",
        kb_dir=DEMO / "kb",
        data_dir=DEMO,  # replaced per test
    )
    return LlmClient(cfg, httpx.AsyncClient(transport=httpx.MockTransport(handler)), retry_delay=0)


def run(mode: str, tmp_path: Path, cases: list[Case]) -> Report:
    llm = scripted_ai(mode)
    cfg = llm.cfg.model_copy(update={"data_dir": tmp_path})
    return asyncio.run(run_eval(cases, cfg, KbState(cfg, AuditDb(tmp_path / "a.db"), llm), llm))


def test_eval_runs_the_real_pipeline_and_catches_invented_facts(tmp_path: Path) -> None:
    cases = [Case("trap", "How long does delivery take?", "handoff", critical=True)]
    # a scripted AI that invents a price: the fact guard hands off, which is what the case expects
    assert run("invent", tmp_path, cases).outcomes == {"trap": "correct"}
    # an AI that answers a trap question with a plausible answer is a critical wrong
    wrong = run("good", tmp_path, cases)
    assert wrong.outcomes == {"trap": "wrong"} and wrong.critical_wrong == ["trap"]


def test_eval_counts_an_ai_outage_as_handed_off_not_wrong(tmp_path: Path) -> None:
    cases = [
        Case("q", "How long does delivery take?", "answer", must_include=(("2 to 3 days",),), critical=True)
    ]
    r = run("down", tmp_path, cases)
    assert r.outcomes == {"q": "handed_off"} and r.critical_wrong == []
