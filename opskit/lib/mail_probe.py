#!/usr/bin/env python3
"""Probe a mailbox's IMAP / SMTP settings without printing any secret.

Usage: mail_probe.py imap|smtp|loopback      (JSON settings on STDIN, so passwords never appear on a command line)
Prints ONE JSON line: {"status": "...", "detail": "..."} with status one of
  ok | auth_failed | connect_failed | tls_error | timeout | error | skipped
`loopback` sends one test mail through SMTP to the inbox's own address and waits for it in the IMAP mailbox.
"""
from __future__ import annotations

import imaplib
import json
import smtplib
import socket
import ssl
import sys
import time
import uuid
from email.message import EmailMessage

TIMEOUT = 10


def out(status: str, detail: str = "") -> None:
    print(json.dumps({"status": status, "detail": detail[:200]}))


def _ctx(cfg: dict, prefix: str) -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    if str(cfg.get(f"{prefix}openssl_verify_mode", "")).lower() == "none":
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def classify(exc: BaseException) -> tuple[str, str]:
    if isinstance(exc, ssl.SSLCertVerificationError):
        return "tls_error", "certificate not trusted or does not match the host name"
    if isinstance(exc, ssl.SSLError):
        return "tls_error", "TLS/SSL negotiation failed (wrong port or SSL setting?)"
    if isinstance(exc, (smtplib.SMTPAuthenticationError,)):
        return "auth_failed", "login rejected"
    if isinstance(exc, imaplib.IMAP4.error):
        text = str(exc).lower()
        if "auth" in text or "credential" in text or "login" in text or "password" in text:
            return "auth_failed", "login rejected"
        return "error", "mail server answered with an error"
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return "timeout", "no answer in time"
    if isinstance(exc, (ConnectionError, socket.gaierror, OSError)):
        return "connect_failed", "cannot connect to the server (host, port or firewall)"
    return "error", type(exc).__name__


def imap_connect(cfg: dict) -> imaplib.IMAP4:
    host, port = cfg["imap_address"], int(cfg["imap_port"])
    if cfg.get("imap_enable_ssl"):
        conn: imaplib.IMAP4 = imaplib.IMAP4_SSL(host, port, ssl_context=_ctx(cfg, "imap_"), timeout=TIMEOUT)
    else:
        conn = imaplib.IMAP4(host, port, timeout=TIMEOUT)
    conn.login(cfg["imap_login"], cfg["imap_password"])
    return conn


def smtp_connect(cfg: dict) -> smtplib.SMTP:
    host, port = cfg["smtp_address"], int(cfg["smtp_port"])
    if cfg.get("smtp_enable_ssl_tls"):
        srv: smtplib.SMTP = smtplib.SMTP_SSL(host, port, timeout=TIMEOUT, context=_ctx(cfg, "smtp_"))
    else:
        srv = smtplib.SMTP(host, port, timeout=TIMEOUT)
        srv.ehlo()
        if cfg.get("smtp_enable_starttls_auto") and srv.has_extn("starttls"):
            srv.starttls(context=_ctx(cfg, "smtp_"))
            srv.ehlo()
    if cfg.get("smtp_login"):
        srv.login(cfg["smtp_login"], cfg.get("smtp_password", ""))
    return srv


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        cfg = json.load(sys.stdin)
    except json.JSONDecodeError:
        out("error", "settings are not valid JSON")
        return 2
    try:
        if mode == "imap":
            conn = imap_connect(cfg)
            conn.select("INBOX", readonly=True)
            conn.logout()
            out("ok", "login and INBOX access work")
        elif mode == "smtp":
            srv = smtp_connect(cfg)
            srv.quit()
            out("ok", "connection" + (" and login" if cfg.get("smtp_login") else "") + " work")
        elif mode == "loopback":
            subject = f"opskit channel test {uuid.uuid4().hex[:8]}"
            msg = EmailMessage()
            msg["From"] = cfg.get("smtp_login") or cfg["email"]
            msg["To"] = cfg["email"]
            msg["Subject"] = subject
            msg.set_content("This is an automatic test message from the channel check. You can delete it.")
            srv = smtp_connect(cfg)
            srv.send_message(msg)
            srv.quit()
            deadline = time.time() + int(cfg.get("wait_seconds", 20))
            while time.time() < deadline:
                conn = imap_connect(cfg)
                conn.select("INBOX")
                _, data = conn.search(None, "SUBJECT", f'"{subject}"')
                found = bool(data and data[0].split())
                if found:
                    for num in data[0].split():
                        conn.store(num, "+FLAGS", "\\Deleted")
                    conn.expunge()
                conn.logout()
                if found:
                    out("ok", "test mail sent and found in the mailbox (then deleted)")
                    return 0
                time.sleep(2)
            out("not_seen", "test mail sent but not found in the mailbox within the wait time")
        else:
            out("error", "mode must be imap, smtp or loopback")
            return 2
    except KeyError as exc:
        out("error", f"setting missing: {exc.args[0]}")
    except Exception as exc:  # noqa: BLE001 - every failure is classified, never raised to the caller
        status, detail = classify(exc)
        out(status, detail)
    return 0


if __name__ == "__main__":
    sys.exit(main())
