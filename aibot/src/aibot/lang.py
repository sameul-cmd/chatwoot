"""Language detection for customer messages: Bangla script, English, or Banglish (Bangla in Latin letters)."""

from __future__ import annotations

import re
from typing import Literal

Language = Literal["bn", "en", "banglish", "unknown"]
Reply = Literal["bn", "en"]

_BANGLA = re.compile("[ঀ-৿]")
_LATIN = re.compile("[A-Za-z]")
_WORD = re.compile("[A-Za-z]+")

# Common romanised Bangla words that are not ordinary English words.
BANGLISH_WORDS = frozenset(
    "ami amar amake apni apnar apnader tumi kemon koto kobe kothay kokhon kivabe kibhabe keno koyta dam daam "
    "achhe ache nai nei lagbe chai hobe hoy jabe pabo pawa dibo bolen bolun valo bhalo ase asbe pathan "
    "pathabo "
    "pathaben kintu naki ekta kore kora korte thakbe dhonnobad dhonyobad kharap lagche".split()
)


def detect(text: str) -> Language:
    """Bangla letters win when at least as many as Latin ones; romanised Bangla is Banglish."""
    bangla = len(_BANGLA.findall(text))
    latin = len(_LATIN.findall(text))
    if bangla == 0 and latin == 0:
        return "unknown"
    if bangla >= latin:
        return "bn"
    words = [w.lower() for w in _WORD.findall(text)]
    hits = sum(1 for w in words if w in BANGLISH_WORDS)
    return "banglish" if hits >= 1 and hits * 4 >= len(words) else "en"


def reply_language(detected: Language, default: Reply) -> Reply:
    """Bangla and English are answered in kind; Banglish and unknown use the client's default language."""
    return detected if detected in ("bn", "en") else default
