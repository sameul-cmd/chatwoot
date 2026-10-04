#!/usr/bin/env python3
"""Pretend OpenAI-compatible AI service for tests and the live demo (no real provider is ever called).
Usage: fake_llm.py PORT_FILE REQUEST_LOG [MODE_FILE] [HOST]
  GET  /v1/models            two models
  POST /v1/embeddings        deterministic word-hash vectors (similar words -> similar vectors)
  POST /v1/chat/completions  answers from the knowledge entries it is shown, following the bot's JSON contract:
      best word overlap with the customer message -> that entry's answer in the customer's script, confidence 0.9;
      no overlap -> handoff; message contains 'ANGRY-TEST' -> upset; contains 'INVENT-A-PRICE' -> an answer with a made-up number.
  MODE_FILE containing 'down' makes chat calls fail with HTTP 503 (to test the bot's fail-safe).
Every request is appended to REQUEST_LOG as one JSON line with the path and the user message (tests inspect it)."""
import hashlib
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG = sys.argv[1], sys.argv[2]
MODE_FILE = sys.argv[3] if len(sys.argv) > 3 else ""
HOST = sys.argv[4] if len(sys.argv) > 4 else "127.0.0.1"
WORD = re.compile("[ঀ-৿]+|[a-z0-9]+")
STOP = set("a an the of is are to in on for and or do does you your i we it my how what when where which can please".split())


def words(text: str) -> set[str]:
    return {w for w in WORD.findall(text.lower()) if w not in STOP and len(w) > 1}


def vector(text: str) -> list[float]:
    v = [0.0] * 32
    for w in words(text):
        v[int(hashlib.md5(w.encode()).hexdigest(), 16) % 32] += 1.0  # noqa: S324
    return v


def parse(user: str) -> tuple[list[tuple[str, str]], str]:
    entries = re.findall(r"\[([^\]\n]+)\]\n(.*?)(?=\n\n\[|\n\nCUSTOMER MESSAGE)", user, re.S)
    customer = user.split("<<<\n", 1)[-1].rsplit("\n>>>", 1)[0]
    return entries, customer


def answer_for(entries: list[tuple[str, str]], customer: str, lang: str) -> dict:
    if "ANGRY-TEST" in customer:
        return {"answer": "", "confidence": 0.5, "used_ids": [], "handoff": False, "upset": True}
    best, best_score = None, 0
    for cid, content in entries:
        questions = " ".join(re.findall(r"Q \(\w+\): (.*)", content))
        score = len(words(customer) & words(content)) + 2 * len(words(customer) & words(questions))  # the question matters most
        if score > best_score:
            best, best_score = (cid, content), score
    if not best:
        return {"answer": "", "confidence": 0.2, "used_ids": [], "handoff": True, "upset": False}
    match = re.search(rf"A \({lang}\): (.*)", best[1]) or re.search(r"A \(\w+\): (.*)", best[1])
    text = match.group(1).strip() if match else best[1]
    if "INVENT-A-PRICE" in customer:
        text += " The price is 999 taka."
    return {"answer": text, "confidence": 0.9, "used_ids": [best[0]], "handoff": False, "upset": False}


class H(BaseHTTPRequestHandler):
    def _send(self, code: int, body: object) -> None:
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _mode(self) -> str:
        try:
            return open(MODE_FILE).read().strip() if MODE_FILE else ""
        except OSError:
            return ""

    def do_GET(self):
        open(LOG, "a").write(json.dumps({"path": self.path, "auth": bool(self.headers.get("Authorization"))}) + "\n")
        self._send(200, {"data": [{"id": "fake-chat"}, {"id": "fake-embed"}]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        open(LOG, "a").write(json.dumps({"path": self.path, "body": body, "auth": bool(self.headers.get("Authorization"))}) + "\n")
        if self.path.endswith("/embeddings"):
            return self._send(200, {"data": [{"index": i, "embedding": vector(t)} for i, t in enumerate(body["input"])]})
        if self._mode() == "down":
            return self._send(503, {"error": "down for the test"})
        entries, customer = parse(body["messages"][1]["content"])
        lang = "bn" if "Answer in Bangla" in body["messages"][0]["content"] else "en"  # follows the bot's instruction
        reply = json.dumps(answer_for(entries, customer, lang), ensure_ascii=False)
        self._send(200, {"choices": [{"message": {"content": reply}}]})

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer((HOST, 0), H)
open(PORT_FILE, "w").write(str(srv.server_address[1]))
srv.serve_forever()
