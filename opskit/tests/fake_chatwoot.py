#!/usr/bin/env python3
"""Pretend Chatwoot API for pack tests (shapes copied from a real v4.18.0 stack, see fixtures/pack_live_shapes.json).
Usage: fake_chatwoot.py PORT_FILE REQUEST_LOG [LIVE_JSON]
Serves /api/v1/accounts/1/{canned_responses,labels,automation_rules,inboxes} with GET/POST/PATCH and /api/v1/profile.
Duplicate short codes / label titles answer 422 like the real one. Every request is appended to REQUEST_LOG as 'METHOD path'.
DELETE is not implemented on purpose: packs must never call it (the server answers 405)."""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, LOG = sys.argv[1], sys.argv[2]
DATA = {"canned_responses": [], "labels": [], "automation_rules": [], "inboxes": []}
if len(sys.argv) > 3:
    live = json.load(open(sys.argv[3]))
    DATA = {"canned_responses": live["canned"], "labels": live["labels"], "automation_rules": live["rules"], "inboxes": live["inboxes"]}
NEXT = {k: max([x["id"] for x in v] + [0]) + 1 for k, v in DATA.items()}
ROUTE = re.compile(r"^/api/v1/accounts/1/(canned_responses|labels|automation_rules|inboxes)(?:/(\d+))?$")
UNIQUE = {"canned_responses": "short_code", "labels": "title"}
WRAPPED = {"labels": True, "automation_rules": True, "inboxes": True}


class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def _handle(self, method):
        open(LOG, "a").write(f"{method} {self.path}\n")
        if self.path == "/api/v1/profile":
            return self._send(200, {"accounts": [{"id": 1, "name": "Demo Shop"}]})
        m = ROUTE.match(self.path)
        if not m or method == "DELETE":
            return self._send(405 if m else 404, {"error": "not supported"})
        kind, oid = m.group(1), m.group(2)
        items = DATA[kind]
        if method == "GET":
            return self._send(200, {"payload": items} if WRAPPED.get(kind) else items)
        body = self._body()
        if kind == "canned_responses":
            body = body["canned_response"]
        if method == "POST":
            key = UNIQUE.get(kind)
            if key and any(x[key] == body.get(key) for x in items):
                return self._send(422, {"message": f"{key} has already been taken"})
            item = {"id": NEXT[kind], **body}
            NEXT[kind] += 1
            items.append(item)
            return self._send(200, item)
        item = next((x for x in items if str(x["id"]) == oid), None)
        if item is None:
            return self._send(404, {"error": "not found"})
        if kind == "inboxes" and "working_hours" in body:
            days = {d["day_of_week"]: d for d in item["working_hours"]}
            for d in body.pop("working_hours"):
                days[d["day_of_week"]] = d
            item["working_hours"] = [days[k] for k in sorted(days)]
        item.update(body)
        return self._send(200, {"payload": item} if kind == "automation_rules" else item)

    do_GET = lambda self: self._handle("GET")  # noqa: E731
    do_POST = lambda self: self._handle("POST")  # noqa: E731
    do_PATCH = lambda self: self._handle("PATCH")  # noqa: E731
    do_DELETE = lambda self: self._handle("DELETE")  # noqa: E731

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
open(PORT_FILE, "w").write(str(srv.server_address[1]))
srv.serve_forever()
