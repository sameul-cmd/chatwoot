"""The bot's own small database (SQLite on the host volume): idempotency, audit rows, counts, vectors."""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path

SCHEMA_VERSION = 1
COLUMNS = frozenset(
    "at conversation_id message_id language question answer used_ids confidence action reason "
    "retrieval latency_ms sent error".split()
)
UNANSWERED_REASONS = ("off_topic", "no_snippet", "low_confidence", "invented_fact", "ai_handoff")


class AuditDb:
    def __init__(self, path: Path | str) -> None:
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.lock = threading.Lock()
        self._migrate()

    def _migrate(self) -> None:
        with self.lock, self.db:
            self.db.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
            if self.db.execute("SELECT COUNT(*) FROM schema_version").fetchone()[0] == 0:
                self.db.execute("INSERT INTO schema_version VALUES (?)", (SCHEMA_VERSION,))
            self.db.execute(
                "CREATE TABLE IF NOT EXISTS processed (message_id INTEGER PRIMARY KEY, at REAL NOT NULL)"
            )
            self.db.execute(
                "CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, "
                "conversation_id INTEGER NOT NULL, message_id INTEGER NOT NULL, language TEXT, "
                "question TEXT, answer TEXT, used_ids TEXT, confidence REAL, action TEXT NOT NULL, "
                "reason TEXT, retrieval TEXT, latency_ms INTEGER, "
                "sent INTEGER NOT NULL DEFAULT 0, error TEXT)"
            )
            self.db.execute("CREATE INDEX IF NOT EXISTS audit_conv ON audit (conversation_id)")
            self.db.execute(
                "CREATE TABLE IF NOT EXISTS kb_vectors (chunk_id TEXT NOT NULL, content_hash TEXT NOT NULL, "
                "model TEXT NOT NULL, vector TEXT NOT NULL, PRIMARY KEY (chunk_id, model))"
            )

    def claim(self, message_id: int) -> bool:
        """True the first time a message id is seen, False for a retried delivery."""
        with self.lock, self.db:
            cur = self.db.execute("INSERT OR IGNORE INTO processed VALUES (?, ?)", (message_id, time.time()))
            return cur.rowcount == 1

    def bot_turns(self, conversation_id: int) -> int:
        """How many answers the bot has sent in this conversation."""
        with self.lock:
            return int(
                self.db.execute(
                    "SELECT COUNT(*) FROM audit WHERE conversation_id = ? AND action = 'answer' AND sent = 1",
                    (conversation_id,),
                ).fetchone()[0]
            )

    def bot_spoke(self, conversation_id: int) -> bool:
        with self.lock:
            row = self.db.execute(
                "SELECT 1 FROM audit WHERE conversation_id = ? AND sent = 1 LIMIT 1", (conversation_id,)
            ).fetchone()
            return row is not None

    def record(self, **row: object) -> None:
        unknown = set(row) - COLUMNS
        if unknown:
            raise ValueError(f"unknown audit columns: {sorted(unknown)}")
        row.setdefault("at", time.time())
        used = row.get("used_ids")
        if isinstance(used, list | tuple):
            row["used_ids"] = json.dumps(list(used))
        cols = list(row)
        sql = f"INSERT INTO audit ({', '.join(cols)}) VALUES ({', '.join('?' for _ in cols)})"  # noqa: S608 (whitelisted names)
        with self.lock, self.db:
            self.db.execute(sql, tuple(row.values()))

    def prune(self, audit_days: int) -> int:
        cutoff = time.time() - audit_days * 86400
        with self.lock, self.db:
            deleted = self.db.execute("DELETE FROM audit WHERE at < ?", (cutoff,)).rowcount
            self.db.execute("DELETE FROM processed WHERE at < ?", (time.time() - 7 * 86400,))
        return int(deleted)

    def metrics(self) -> dict[str, object]:
        with self.lock:
            q = self.db.execute
            actions = dict(q("SELECT action, COUNT(*) FROM audit GROUP BY action").fetchall())
            reasons = dict(
                q("SELECT reason, COUNT(*) FROM audit WHERE action = 'handoff' GROUP BY reason").fetchall()
            )
            avg = q("SELECT AVG(latency_ms) FROM audit WHERE latency_ms IS NOT NULL").fetchone()[0]
            errors = q("SELECT COUNT(*) FROM audit WHERE error IS NOT NULL").fetchone()[0]
        return {
            "answered": actions.get("answer", 0),
            "handed_off": actions.get("handoff", 0),
            "handoff_reasons": reasons,
            "errors": errors,
            "avg_latency_ms": round(avg) if avg is not None else None,
        }

    def unanswered(self, limit: int = 50) -> list[dict[str, object]]:
        """Questions the bot could not answer, most asked first, for the monthly report and KB to-do list."""
        marks = ", ".join("?" for _ in UNANSWERED_REASONS)
        with self.lock:
            rows = self.db.execute(
                f"SELECT question, COUNT(*) AS n FROM audit WHERE action = 'handoff' AND reason IN ({marks}) "  # noqa: S608
                "AND question IS NOT NULL GROUP BY question ORDER BY n DESC, MAX(at) DESC LIMIT ?",
                (*UNANSWERED_REASONS, limit),
            ).fetchall()
        return [{"question": r[0], "count": r[1]} for r in rows]

    def load_vectors(self, model: str) -> dict[str, tuple[str, list[float]]]:
        with self.lock:
            rows = self.db.execute(
                "SELECT chunk_id, content_hash, vector FROM kb_vectors WHERE model = ?", (model,)
            ).fetchall()
        return {r[0]: (r[1], json.loads(r[2])) for r in rows}

    def save_vectors(self, model: str, items: dict[str, tuple[str, list[float]]]) -> None:
        with self.lock, self.db:
            self.db.execute("DELETE FROM kb_vectors WHERE model = ?", (model,))
            self.db.executemany(
                "INSERT INTO kb_vectors VALUES (?, ?, ?, ?)",
                [(cid, h, model, json.dumps(v)) for cid, (h, v) in items.items()],
            )
