#!/usr/bin/env python3
"""Pretend IMAP + SMTP servers for tests (plain text, no TLS). Usage: fake_mail.py PORTS_FILE USER PASSWORD
Writes {"imap": N, "smtp": M} to PORTS_FILE. SMTP stores accepted mail in a shared in-memory mailbox that IMAP can search."""
import base64
import json
import socketserver
import sys
import threading

PORTS_FILE, USER, PASSWORD = sys.argv[1:4]
MAILBOX: list[str] = []
LOCK = threading.Lock()


class Imap(socketserver.StreamRequestHandler):
    def send(self, text):
        self.wfile.write((text + "\r\n").encode())

    def handle(self):
        self.send("* OK fake imap ready")
        authed = False
        while True:
            line = self.rfile.readline().decode(errors="ignore").strip()
            if not line:
                return
            tag, _, rest = line.partition(" ")
            cmd = rest.split(" ")[0].upper()
            if cmd == "CAPABILITY":
                self.send("* CAPABILITY IMAP4rev1"); self.send(f"{tag} OK done")
            elif cmd == "LOGIN":
                parts = rest.split(" ")
                if len(parts) >= 3 and parts[1].strip('"') == USER and parts[2].strip('"') == PASSWORD:
                    authed = True; self.send(f"{tag} OK LOGIN completed")
                else:
                    self.send(f"{tag} NO [AUTHENTICATIONFAILED] Invalid credentials")
            elif cmd in ("SELECT", "EXAMINE") and authed:
                with LOCK:
                    n = len(MAILBOX)
                self.send(f"* {n} EXISTS"); self.send(f"{tag} OK [READ-WRITE] SELECT completed")
            elif cmd == "SEARCH" and authed:
                needle = rest.split("SUBJECT", 1)[-1].strip().strip('"').lower()
                with LOCK:
                    hits = [str(i + 1) for i, m in enumerate(MAILBOX) if needle in m.lower()]
                self.send("* SEARCH " + " ".join(hits)); self.send(f"{tag} OK SEARCH completed")
            elif cmd in ("STORE", "EXPUNGE", "NOOP", "CLOSE") and authed:
                self.send(f"{tag} OK done")
            elif cmd == "LOGOUT":
                self.send("* BYE"); self.send(f"{tag} OK LOGOUT completed"); return
            else:
                self.send(f"{tag} BAD unknown or not authenticated")


class Smtp(socketserver.StreamRequestHandler):
    def send(self, text):
        self.wfile.write((text + "\r\n").encode())

    def handle(self):
        self.send("220 fake smtp ready")
        authed = False
        while True:
            line = self.rfile.readline().decode(errors="ignore").rstrip("\r\n")
            if not line:
                return
            cmd = line.split(" ")[0].upper()
            if cmd in ("EHLO", "HELO"):
                self.send("250-fake"); self.send("250 AUTH PLAIN LOGIN")
            elif cmd == "AUTH":
                parts = line.split(" ")
                if parts[1].upper() == "PLAIN" and len(parts) > 2:
                    _, u, p = base64.b64decode(parts[2]).decode().split("\0")
                elif parts[1].upper() == "LOGIN":
                    self.send("334 VXNlcm5hbWU6"); u = base64.b64decode(self.rfile.readline().strip()).decode()
                    self.send("334 UGFzc3dvcmQ6"); p = base64.b64decode(self.rfile.readline().strip()).decode()
                else:
                    u = p = ""
                if u == USER and p == PASSWORD:
                    authed = True; self.send("235 Authentication successful")
                else:
                    self.send("535 Authentication failed")
            elif cmd in ("MAIL", "RCPT"):
                self.send("250 OK")
            elif cmd == "DATA":
                self.send("354 End data with <CR><LF>.<CR><LF>")
                body = []
                while True:
                    row = self.rfile.readline().decode(errors="ignore")
                    if row.rstrip("\r\n") == ".":
                        break
                    body.append(row)
                with LOCK:
                    MAILBOX.append("".join(body))
                self.send("250 Queued")
            elif cmd in ("NOOP", "RSET"):
                self.send("250 OK")
            elif cmd == "QUIT":
                self.send("221 Bye"); return
            else:
                self.send("502 Command not implemented")


class Srv(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


imap, smtp = Srv(("127.0.0.1", 0), Imap), Srv(("127.0.0.1", 0), Smtp)
open(PORTS_FILE, "w").write(json.dumps({"imap": imap.server_address[1], "smtp": smtp.server_address[1]}))
threading.Thread(target=imap.serve_forever, daemon=True).start()
smtp.serve_forever()
