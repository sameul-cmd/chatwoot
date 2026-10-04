# Phase 4 — Monitoring & alerts via the shared ops-hub (Improvement 3)

Spec: SPEC Section 9, Section 17 (Phase 4), Section 3 rule 8, ADR-006, TECH_ARCHITECTURE sections 7 (notify.sh reuse).
**Accept (from SPEC):** stopping Sidekiq triggers a critical Telegram alert within 10 minutes; stopping the stack triggers an uptime alert; a simulated disconnected inbox is reported; hub-down fallback sends directly; de-duplication prevents repeats within 30 minutes.

## What this phase is, in plain words
A small watcher program on each client's server that checks the system every 5 minutes (and the chat channels every 15), decides how serious a problem is, and tells you on Telegram. If your shared "ops-hub" (the Activepieces + Uptime Kuma project) is reachable it goes through there; if not, the watcher messages your Telegram directly so you are never blind.

## Facts this phase relies on
- Health route: `GET /api` -> `{"version", "queue_services", "data_services"}` (Phase 0). Through Caddy it is `https://<domain>/api`.
- Chatwoot marks a broken connection in the inbox API as `reauthorization_required: true` (email, Facebook, Instagram, WhatsApp embedded sign-up); verified in the code (`app/views/api/v1/models/_inbox.json.jbuilder`, `reauthorizable.rb`). Plain Telegram/widget inboxes have no such field: for those we test reachability instead (Phase 6 checkers go deeper).
- API calls through the public URL must use the header `api-access-token` (Phase 3 finding).
- Sidekiq keeps its state in Redis (processes, queue lengths, retry/dead sets): readable with `redis-cli` inside the redis container, without starting Rails. Exact keys are verified in task 4.2 before code depends on them.
- Alert payloads + outbox + heartbeat helpers already exist (`lib/alert.sh`, Phase 3). No message text may ever appear in an alert.

## Open questions for the owner (plain words; defaults in bold)
1. **Telegram bot for alerts.** You create a bot with @BotFather (2 minutes, free) and send me nothing: later, on your own device, you put its token and your chat number into the server's private settings file. Here in the sandbox I test with a *pretend Telegram* program, so no real token is needed now. **Default: OK.**
2. **Your ops-hub.** The Activepieces/Uptime Kuma project is a separate project that is not here. **Default:** I define the exact message format the hub receives and write the hub-side instructions (what flows and monitors to add), but I can only prove the *direct Telegram fallback* here. The hub flows themselves are marked "not verified" until you set them up. Is the hub already running somewhere, or does the minimal setup need to be part of this phase (SPEC allows either)?
3. **What counts as a problem (thresholds).** **Default:** site down or login page failing = critical; Sidekiq not running = critical; background jobs waiting longer than 5 minutes = warning, longer than 15 = critical; failed-job pile growing = warning; disk above 85% = warning, above 95% = critical; memory pressure or a container restarting more than 3 times an hour = warning; HTTPS certificate expiring in under 14 days = warning, under 3 = critical; a chat channel needing re-connection = critical; the bot's health page failing = warning (critical once the bot is live).
4. **Quiet hours.** Warnings can wait for the morning; critical alerts never wait. **Default:** warnings are held between 22:00 and 08:00 in the client's time zone and sent as one summary at 08:00.
5. **Who is told.** **Default:** only you (owner) on Telegram. Telling the client's own people (their Telegram/email) is a setting prepared in `client.yaml` but off.
6. **Repeats and "all clear".** **Default:** the same problem is reported once, then at most a reminder every 2 hours for critical ones (nothing for warnings); when it clears you get one "resolved" message. The same alert is never sent twice within 30 minutes (SPEC).
7. **A read-only monitoring login.** To ask Chatwoot about channels every 15 minutes the watcher needs an API key. **Default:** deploy creates one extra administrator user `ops-monitor@<client domain>` whose key is stored only in a private file on that server (`clients/<id>/monitor.env`, mode 600). It is never put in alerts or logs. Needs your approval because it is a new secret.

## Tasks

### [x] 4.1 — Telegram sender and shared notifier (`lib/notify.sh`)
- **Goal:** one function that sends a short text to Telegram (token + chat id from a private settings file), with timeout, retry, and no secret in logs; reused later by the V2 daily digest (TECH section 7).
- **Tests:** bats against a pretend Telegram server (local program): message arrives; wrong token reported without printing it; server down = non-zero exit

### [x] 4.2 — Verify and record the Sidekiq/Redis facts
- **Goal:** on a live demo stack read: number of running Sidekiq processes, queue lengths, oldest-job age, retry and dead set sizes with `redis-cli` through the container; record exact keys in EXPLORATION_REPORT; stop Sidekiq and see what changes.
- **Acceptance:** each check below is backed by a recorded real observation

### [x] 4.3 — Check functions (host agent, `agent/health.sh`, standalone)
- **Goal:** pure functions that return `ok|warn|critical` + a short reason (no text of conversations): site/login/API (via HTTPS), Sidekiq alive, queue latency, failed-job growth, disk, memory, container restarts, certificate expiry, aibot health. Thresholds from `client.yaml` `alerts` with the defaults above.
- **Tests:** bats with fake docker/redis-cli/df/openssl outputs: every threshold boundary, "unknown" is never reported as "ok"

### [x] 4.4 — Alert state and de-duplication (`lib/alert_state.sh`)
- **Goal:** per check a small state file: first seen, last sent, last severity; rules: same alert not repeated within 30 minutes; critical reminder every 2 hours; one "resolved" message; warnings held in quiet hours and sent as one summary.
- **Tests:** bats with a fake clock: dedup window edges, reminder timing, resolved message, quiet-hours hold + release, severity upgrade (warn -> critical) sends immediately

### [x] 4.5 — Channel health poller (`agent/channels_health.sh`)
- **Goal:** every 15 minutes list inboxes through the API (header `api-access-token`) and report any `reauthorization_required: true`, plus unreachable webhook/callback URLs where the API tells us one; output only inbox name/type/id, never contact data.
- **Tests:** bats with a fake API server returning a healthy and a "disconnected" inbox; token never printed

### [x] 4.6 — Monitoring user and secrets  [needs your approval: new secret]
- **Goal:** deploy creates `ops-monitor@<domain>` (administrator) and writes its API token to `clients/<id>/monitor.env` (mode 600); idempotent; included in the encrypted backup escrow.
- **Tests:** bats: file mode, no token in logs; integration in 4.10: user exists once after two deploys

### [x] 4.7 — Orchestrator + hub payload contract (`agent/monitor.sh`, `opskit monitor run|status <id>`)
- **Goal:** runs all checks, applies dedup/quiet hours, sends via the hub when `OPSKIT_HUB_URL` works, otherwise directly to Telegram (fallback); every run also sends a heartbeat so the hub can notice a silent server. `opskit/hub/README.md` documents the JSON contract and the flows/monitors to add to the Activepieces ops-hub (Uptime Kuma monitors: `https://<domain>` and `/api` every minute).
- **Tests:** bats: hub down -> direct Telegram sent once; hub up -> no direct Telegram; fallback message contains client + check + severity, no secrets

### [x] 4.8 — Schedule templates
- **Goal:** cron lines rendered by `client render`: checks every 5 minutes (`flock`), channel poll every 15 minutes, installed on a real host in Phase 11.
- **Tests:** bats on the rendered files

### [x] 4.9 — Simulated failures (acceptance scenarios)
- **Goal:** on a live demo stack with the pretend Telegram: (a) stop Sidekiq -> critical message within 10 minutes (we run the 5-minute cycle by hand twice); (b) stop the whole stack -> uptime alert; (c) fake a disconnected inbox -> reported; (d) hub down -> direct fallback; (e) repeat runs inside 30 minutes -> no second message; (f) restart -> one "resolved" message.
- **Acceptance:** all six pass in `opskit selftest`

### [x] 4.10 — Selftest v3, runbook, docs, verification
- **Goal:** `opskit selftest` gains the monitoring rows; `docs/runbooks/monitoring.md` (what each alert means and what to do, in plain language); update PROGRESS/ASSUMPTIONS/ENVIRONMENT; `/verify-phase` + security review (token handling, no message text in alerts or logs).
