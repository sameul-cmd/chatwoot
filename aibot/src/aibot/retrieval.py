"""Finding KB entries: keyword ranking (BM25) and embedding similarity, each the fallback of the other."""

from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass
from typing import Literal

from .kb import Chunk

Mode = Literal["bm25", "vector", "hybrid", "none"]

_TOKEN = re.compile("[ঀ-৿]+|[a-z0-9]+")
_STOP = frozenset(
    "a an the of is are am was were be to in on at for and or do does did i you we it my your our this that "
    "what how when where which who can could would will please me us with from by as "
    "আমি আমার আপনি আপনার আমরা আমাদের এই সেই কি কী কে কোন কত কেন এবং ও না আছে হয় হবে".split()
)
_BN_SUFFIXES = ("গুলো", "গুলি", "দের", "ের", "টা", "টি", "কে", "তে", "র")
K1, B = 1.5, 0.75
RRF_K = 60


def tokenize(text: str) -> list[str]:
    """Lower-cased words in Bangla or Latin script, common stop words dropped, simple Bangla suffixes cut."""
    tokens = []
    for tok in _TOKEN.findall(text.lower()):
        if tok in _STOP:
            continue
        for suffix in _BN_SUFFIXES:
            if tok.endswith(suffix) and len(tok) - len(suffix) >= 2:
                tok = tok[: -len(suffix)]
                break
        tokens.append(tok)
    return tokens


class Bm25:
    def __init__(self, chunks: list[Chunk]) -> None:
        self.ids = [c.id for c in chunks]
        self.docs = [Counter(tokenize(c.search_text)) for c in chunks]
        self.lengths = [sum(d.values()) for d in self.docs]
        self.avg = (sum(self.lengths) / len(self.lengths)) if self.lengths else 0.0
        self.df: Counter[str] = Counter()
        for d in self.docs:
            self.df.update(d.keys())

    def rank(self, query: str) -> list[tuple[str, float]]:
        """(chunk id, score) for every chunk that shares at least one word with the query, best first."""
        n = len(self.docs)
        q = set(tokenize(query))
        scored = []
        for cid, doc, length in zip(self.ids, self.docs, self.lengths, strict=True):
            score = 0.0
            for tok in q:
                tf = doc.get(tok, 0)
                if not tf:
                    continue
                idf = math.log(1 + (n - self.df[tok] + 0.5) / (self.df[tok] + 0.5))
                score += idf * tf * (K1 + 1) / (tf + K1 * (1 - B + B * length / (self.avg or 1)))
            if score > 0:
                scored.append((cid, score))
        return sorted(scored, key=lambda x: -x[1])


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na, nb = math.sqrt(sum(x * x for x in a)), math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


def rank_vectors(
    query_vec: list[float], vectors: dict[str, list[float]], min_similarity: float
) -> list[tuple[str, float]]:
    scored = [(cid, cosine(query_vec, v)) for cid, v in vectors.items()]
    return sorted([s for s in scored if s[1] >= min_similarity], key=lambda x: -x[1])


@dataclass(frozen=True)
class Retrieval:
    chunks: list[Chunk]
    mode: Mode


def retrieve(
    chunks: list[Chunk],
    bm25: Bm25,
    query: str,
    *,
    query_vec: list[float] | None = None,
    vectors: dict[str, list[float]] | None = None,
    min_similarity: float = 0.35,
    top_k: int = 3,
) -> Retrieval:
    """Hybrid search: keywords alone, vectors alone when keywords find nothing, else both merged."""
    by_id = {c.id: c for c in chunks}
    keyword = bm25.rank(query)
    semantic = rank_vectors(query_vec, vectors, min_similarity) if query_vec and vectors else []
    if keyword and semantic:
        fused: dict[str, float] = {}
        for ranking in (keyword, semantic):
            for pos, (cid, _) in enumerate(ranking):
                fused[cid] = fused.get(cid, 0.0) + 1 / (RRF_K + pos + 1)
        order, mode = [cid for cid, _ in sorted(fused.items(), key=lambda x: (-x[1], x[0]))], "hybrid"
    elif keyword:
        order, mode = [cid for cid, _ in keyword], "bm25"
    elif semantic:
        order, mode = [cid for cid, _ in semantic], "vector"
    else:
        return Retrieval([], "none")
    return Retrieval([by_id[cid] for cid in order[:top_k]], mode)  # type: ignore[arg-type]
