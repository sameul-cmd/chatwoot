"""The client's knowledge base: kb/faq.yaml (question + answer, bn + en) and optional kb/*.md notes."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import yaml

MAX_CHUNK = 1200


@dataclass(frozen=True)
class Chunk:
    id: str
    search_text: str  # what retrieval matches against (questions, aliases, answers)
    content: str  # what the AI is allowed to use and what the fact guard compares against


def _faq_chunks(path: Path) -> list[Chunk]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    chunks: list[Chunk] = []
    for item in data.get("items", []):
        answer = item.get("answer") or {}
        if not any((answer.get(lang) or "").strip() for lang in ("bn", "en")):
            continue  # nobody wrote an answer: the bot must never answer from it
        question = item.get("question") or {}
        lines = []
        for lang in ("en", "bn"):
            if (answer.get(lang) or "").strip():
                lines.append(f"Q ({lang}): {question.get(lang, '')}\nA ({lang}): {answer[lang].strip()}")
        aliases = " ".join(item.get("aliases") or [])
        search = " ".join(
            [
                question.get("en", ""),
                question.get("bn", ""),
                aliases,
                answer.get("en") or "",
                answer.get("bn") or "",
            ]
        )
        chunks.append(Chunk(id=f"faq:{item['key']}", search_text=search, content="\n".join(lines)))
    return chunks


def _split_long(text: str) -> list[str]:
    pieces, current = [], ""
    for para in re.split(r"\n\s*\n", text):
        if current and len(current) + len(para) > MAX_CHUNK:
            pieces.append(current)
            current = ""
        current = f"{current}\n\n{para}".strip()
    return pieces + ([current] if current else [])


def _markdown_chunks(path: Path) -> list[Chunk]:
    sections: list[str] = []
    current: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") and current:
            sections.append("\n".join(current))
            current = []
        current.append(line)
    sections.append("\n".join(current))
    chunks: list[Chunk] = []
    for section in sections:
        for piece in _split_long(section):
            if len(piece.strip()) >= 20:
                chunks.append(
                    Chunk(id=f"{path.stem}#{len(chunks)}", search_text=piece, content=piece.strip())
                )
    return chunks


def load_kb(kb_dir: Path) -> list[Chunk]:
    """Every answerable chunk of the KB; a missing folder gives an empty KB."""
    chunks: list[Chunk] = []
    faq = kb_dir / "faq.yaml"
    if faq.exists():
        chunks += _faq_chunks(faq)
    for md in sorted(kb_dir.glob("*.md")):
        chunks += _markdown_chunks(md)
    return chunks
