#!/usr/bin/env python3
"""Pretend Meta Graph API for tests. Usage: fake_meta.py PORT_FILE [DISPLAY_NUMBER]
GET /<version>/<phone_number_id>?fields=... with 'Authorization: Bearer <token>':
  token containing 'expired' -> 400 {error:{code:190}}; phone_number_id '404404' -> 404; else 200 with the display number."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE = sys.argv[1]
DISPLAY = sys.argv[2] if len(sys.argv) > 2 else "+880 1700-000001"


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("Authorization", "").replace("Bearer ", "")
        if "expired" in token:
            code, body = 400, {"error": {"code": 190, "message": "Error validating access token"}}
        elif "/404404" in self.path:
            code, body = 404, {"error": {"code": 100}}
        else:
            code, body = 200, {"display_phone_number": DISPLAY, "verified_name": "Demo Shop", "quality_rating": "GREEN"}
        self.send_response(code)
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
open(PORT_FILE, "w").write(str(srv.server_address[1]))
srv.serve_forever()
