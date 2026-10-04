"""Shared small types: the AI's answer, a decision and the named reasons for handing off."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

HandoffReason = Literal[
    "human_request",
    "upset",
    "off_topic",
    "max_turns",
    "low_confidence",
    "no_snippet",
    "invented_fact",
    "ai_handoff",
    "llm_error",
    "unsupported_message",
]


class LlmAnswer(BaseModel):
    """What the AI must return (strict JSON)."""

    model_config = ConfigDict(extra="ignore")

    answer: str = ""
    confidence: float = Field(default=0.0, ge=0, le=1)
    used_ids: list[str] = Field(default_factory=list)
    handoff: bool = False
    upset: bool = False


@dataclass(frozen=True)
class Decision:
    """Either send `answer` or hand the conversation to a person for `reason`."""

    action: Literal["answer", "handoff"]
    reason: HandoffReason | None = None
    answer: str = ""
    used_ids: tuple[str, ...] = ()
