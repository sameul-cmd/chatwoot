"""`aibot eval`: run a client's test questions through the real pipeline, score them, apply the go-live gate.

Usage (inside the bot container): python -m aibot.eval [--cases /kb/eval.yaml]

Scores: correct (as expected); handed off (a safe miss: an answer was expected, a person takes it);
wrong (answered when a person should have, or the answer misses or contradicts the expected facts).
A wrong answer on a case marked `critical` (prices, delivery, returns, policies) is a "wrong price/policy".
Gate (SPEC 13.7): none of those, and at least 90% correct-or-handed-off.
The test set is written by the operator: no customer data is involved.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from .config import load_config
from .handlers.answer import decide
from .kbstate import KbState
from .lang import detect, reply_language
from .llm import LlmClient
from .models import Decision

GATE_SHARE = 0.9
MIN_CASES = 20


@dataclass(frozen=True)
class Case:
    id: str
    question: str
    expect: str  # "answer" or "handoff"
    must_include: tuple[tuple[str, ...], ...] = ()  # every group must be found; a group is any-of
    must_not_include: tuple[str, ...] = ()
    critical: bool = False
    reason: str | None = None  # expected handoff reason, optional


@dataclass
class Report:
    outcomes: dict[str, str] = field(default_factory=dict)
    details: dict[str, str] = field(default_factory=dict)
    critical_wrong: list[str] = field(default_factory=list)

    def count(self, kind: str) -> int:
        return sum(1 for v in self.outcomes.values() if v == kind)

    @property
    def total(self) -> int:
        return len(self.outcomes)

    @property
    def share_ok(self) -> float:
        return (self.count("correct") + self.count("handed_off")) / self.total if self.total else 0.0

    def gate(self) -> tuple[bool, list[str]]:
        problems = []
        if self.total < MIN_CASES:
            problems.append(f"only {self.total} test questions; at least {MIN_CASES} are needed")
        if self.critical_wrong:
            problems.append(
                f"{len(self.critical_wrong)} wrong price/policy answer(s): {', '.join(self.critical_wrong)}"
            )
        if self.share_ok < GATE_SHARE:
            problems.append(f"only {self.share_ok:.0%} correct-or-handed-off (needs {GATE_SHARE:.0%})")
        return not problems, problems


def load_cases(path: Path) -> list[Case]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    cases = []
    for raw in data.get("cases", []):
        groups = tuple(tuple([g] if isinstance(g, str) else g) for g in raw.get("must_include", []))
        cases.append(
            Case(
                id=raw["id"],
                question=raw["question"],
                expect=raw["expect"],
                must_include=groups,
                must_not_include=tuple(raw.get("must_not_include", [])),
                critical=bool(raw.get("critical", False)),
                reason=raw.get("reason"),
            )
        )
    return cases


def score(case: Case, decision: Decision) -> tuple[str, str]:
    """(outcome, detail) with outcome correct / handed_off / wrong; the caller records critical wrongs."""
    if decision.action == "handoff":
        if case.expect == "handoff":
            if case.reason and decision.reason != case.reason:
                return "wrong", f"handed off for '{decision.reason}', expected '{case.reason}'"
            return "correct", f"handed off ({decision.reason})"
        return "handed_off", f"handed off ({decision.reason}) instead of answering"
    text = decision.answer.casefold()
    if case.expect == "handoff":
        return "wrong", "answered, but a person should have taken this"
    forbidden = [w for w in case.must_not_include if w.casefold() in text]
    if forbidden:
        return "wrong", f"answer contains forbidden text {forbidden}"
    missing = [" / ".join(g) for g in case.must_include if not any(w.casefold() in text for w in g)]
    if missing:
        return "wrong", f"answer lacks the expected fact(s): {missing}"
    return "correct", "answered with the expected facts"


async def run_eval(cases: list[Case], cfg: Any, kb: KbState, llm: LlmClient) -> Report:
    report = Report()
    for case in cases:
        lang = reply_language(detect(case.question), cfg.default_language)
        decision, _, _ = await decide(cfg, kb, llm, case.question, lang, 0)
        outcome, detail = score(case, decision)
        report.outcomes[case.id], report.details[case.id] = outcome, detail
        if outcome == "wrong" and (case.critical or "forbidden text" in detail):
            report.critical_wrong.append(case.id)
    return report


def format_report(report: Report) -> str:
    c = Counter(report.outcomes.values())
    lines = [
        f"questions {report.total}  correct {c['correct']}  handed off {c['handed_off']}  "
        f"wrong {c['wrong']}  "
        f"wrong price/policy {len(report.critical_wrong)}  correct-or-handed-off {report.share_ok:.0%}"
    ]
    lines += [
        f"  {kind.upper():<10} {cid}: {report.details[cid]}"
        for cid, kind in report.outcomes.items()
        if kind != "correct"
    ]
    ok, problems = report.gate()
    lines.append("GATE PASSED" if ok else "GATE FAILED: " + "; ".join(problems))
    return "\n".join(lines)


async def _main(cases_path: Path) -> int:
    yaml_path = os.environ.get("AIBOT_CONFIG")
    cfg = load_config(os.environ, Path(yaml_path) if yaml_path else None)
    llm = LlmClient(cfg)
    from .audit import AuditDb

    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    kb = KbState(cfg, AuditDb(cfg.data_dir / "aibot.db"), llm)
    await kb.refresh_vectors()
    report = await run_eval(load_cases(cases_path), cfg, kb, llm)
    print(format_report(report))
    return 0 if report.gate()[0] else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Score the bot against a client's test questions")
    parser.add_argument("--cases", type=Path, default=Path("/kb/eval.yaml"))
    args = parser.parse_args(argv)
    if not args.cases.exists():
        print(
            f"no test questions at {args.cases}: write them first (see docs/runbooks/bot.md)", file=sys.stderr
        )
        return 2
    return asyncio.run(_main(args.cases))


if __name__ == "__main__":
    sys.exit(main())
