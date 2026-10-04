"""The rules that decide between answering and handing off. Pure logic: no network, no clock, no storage."""

from __future__ import annotations

import re

from .config import BotConfig
from .models import Decision, HandoffReason, LlmAnswer

_BANGLA_DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")
_NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")
_NUMBER_WORDS = frozenset(
    "one two three four five six seven eight nine ten eleven twelve twenty thirty fifty hundred thousand "
    "এক দুই তিন চার পাঁচ ছয় সাত আট নয় দশ বিশ ত্রিশ পঞ্চাশ শত হাজার".split()
)
_WORD = re.compile("[A-Za-z]+|[ঀ-৿]+")


def _contains(text: str, words: list[str]) -> bool:
    """English words match as whole words, Bangla words as parts of a word (Bangla attaches endings)."""
    low = text.casefold()
    for w in words:
        w = w.casefold()
        if w.isascii():
            if re.search(rf"\b{re.escape(w)}\b", low):
                return True
        elif w in low:
            return True
    return False


def wants_human(text: str, cfg: BotConfig) -> bool:
    return _contains(text, cfg.handoff_keywords.en + cfg.handoff_keywords.bn)


def is_upset(text: str, cfg: BotConfig) -> bool:
    return _contains(text, cfg.upset_words.en + cfg.upset_words.bn)


def pre_check(text: str, bot_turns: int, cfg: BotConfig) -> HandoffReason | None:
    """Reasons to hand off before any search or AI call, in priority order."""
    if wants_human(text, cfg):
        return "human_request"
    if is_upset(text, cfg):
        return "upset"
    if bot_turns >= cfg.max_bot_turns:
        return "max_turns"
    return None


def _numbers(text: str) -> set[str]:
    return {n.replace(",", "") for n in _NUMBER.findall(text.translate(_BANGLA_DIGITS))}


def _number_words(text: str) -> set[str]:
    return {w.casefold() for w in _WORD.findall(text) if w.casefold() in _NUMBER_WORDS}


def invented_facts(answer: str, sources: str) -> set[str]:
    """Numbers and number words in the answer that the used KB entries lack (prices, days, amounts)."""
    return (_numbers(answer) - _numbers(sources)) | (_number_words(answer) - _number_words(sources))


def post_check(result: LlmAnswer, sources: dict[str, str], cfg: BotConfig) -> Decision:
    """Gate an AI answer. `sources` maps the ids of the KB entries that were shown to the AI to their text."""
    if result.upset:
        return Decision("handoff", "upset")
    if result.handoff:
        return Decision("handoff", "ai_handoff")
    used = tuple(i for i in result.used_ids if i in sources)
    if not result.answer.strip():
        return Decision("handoff", "low_confidence")
    if result.confidence < cfg.min_confidence:
        return Decision("handoff", "low_confidence")
    if not used:
        return Decision("handoff", "no_snippet")
    if invented_facts(result.answer, "\n".join(sources[i] for i in used)):
        return Decision("handoff", "invented_fact")
    return Decision("answer", None, result.answer.strip(), used)
