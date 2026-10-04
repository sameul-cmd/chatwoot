"""The loaded KB with its search indexes; reloadable without a restart."""

from __future__ import annotations

import hashlib
import logging

from .audit import AuditDb
from .config import BotConfig
from .kb import Chunk, load_kb
from .llm import LlmClient, LlmError
from .retrieval import Bm25, Retrieval, retrieve

log = logging.getLogger("aibot.kb")
BATCH = 64


def _hash(chunk: Chunk) -> str:
    return hashlib.sha256(chunk.search_text.encode()).hexdigest()[:16]


class KbState:
    def __init__(self, cfg: BotConfig, audit: AuditDb, llm: LlmClient) -> None:
        self.cfg, self.audit, self.llm = cfg, audit, llm
        self.chunks: list[Chunk] = []
        self.bm25 = Bm25([])
        self.vectors: dict[str, list[float]] = {}
        self.load()

    def load(self) -> None:
        self.chunks = load_kb(self.cfg.kb_dir)
        self.bm25 = Bm25(self.chunks)
        self.vectors = {}

    async def refresh_vectors(self) -> None:
        """Embed new or changed entries (cached by content), never fatal: keyword search keeps working."""
        if not self.cfg.embeddings or not self.chunks:
            return
        model = self.cfg.embeddings.model
        cached = self.audit.load_vectors(model)
        keep = {c.id: cached[c.id] for c in self.chunks if c.id in cached and cached[c.id][0] == _hash(c)}
        todo = [c for c in self.chunks if c.id not in keep]
        try:
            for i in range(0, len(todo), BATCH):
                batch = todo[i : i + BATCH]
                for chunk, vec in zip(
                    batch, await self.llm.embed([c.search_text for c in batch]), strict=True
                ):
                    keep[chunk.id] = (_hash(chunk), vec)
        except LlmError as exc:
            log.warning("embedding the KB failed (%s); keyword search only", exc)
        self.audit.save_vectors(model, keep)
        self.vectors = {cid: vec for cid, (_, vec) in keep.items()}

    async def search(self, question: str) -> Retrieval:
        qvec = None
        if self.cfg.embeddings and self.vectors:
            try:
                qvec = (await self.llm.embed([question]))[0]
            except LlmError as exc:
                log.warning("embedding the question failed (%s); keyword search only", exc)
        min_sim = self.cfg.embeddings.min_similarity if self.cfg.embeddings else 0.35
        return retrieve(
            self.chunks, self.bm25, question, query_vec=qvec, vectors=self.vectors, min_similarity=min_sim
        )
