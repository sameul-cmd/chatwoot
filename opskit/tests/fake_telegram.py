#!/usr/bin/env python3
"""Pretend Telegram Bot API for tests. Usage: fake_telegram.py PORT_FILE LOG_FILE [WEBHOOK_INFO_JSON]
Writes the chosen port to PORT_FILE, appends every sendMessage as one JSON line to LOG_FILE.
A token containing 'badtoken' gets HTTP 401; 'flaky' gets HTTP 500."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2]
WEBHOOK_INFO = sys.argv[3] if len(sys.argv) > 3 else None  # optional JSON file served for getWebhookInfo


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("content-length", 0))
        form = {k: v[0] for k, v in parse_qs(self.rfile.read(n).decode()).items()}
        code = 401 if "badtoken" in self.path else 500 if "flaky" in self.path else 200
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps({"path_has_token": "/bot" in self.path, "status": code, **form}) + "\n")
        self.send_response(code)
        self.end_headers()
        self.wfile.write(json.dumps({"ok": code == 200}).encode())

    def do_GET(self):
        code = 401 if "badtoken" in self.path else 200
        body = {"ok": False} if code != 200 else {"ok": True, "result": {}}
        if code == 200 and self.path.endswith("/getWebhookInfo") and WEBHOOK_INFO:
            body = json.loads(open(WEBHOOK_INFO).read())
        self.send_response(code)
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
open(PORT_FILE, "w").write(str(srv.server_address[1]))
srv.serve_forever()
