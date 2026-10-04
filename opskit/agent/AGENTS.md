# opskit/agent — scripts that run on client hosts

- Standalone Bash: backup (DB + storage + encrypted .env), health (site, sidekiq, disk, certs), channels (inbox status via API), heartbeat.
- POST to `OPSKIT_HUB_URL`; direct Telegram fallback if the hub is unreachable; `flock` + idempotent; no message text or PII in payloads.
