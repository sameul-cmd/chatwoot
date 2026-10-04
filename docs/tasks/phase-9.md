# Phase 9 — Monthly care report (Improvement 8)

Spec: SPEC Section 14, Section 17 (Phase 9). Read first: `docs/ADOPT.md`, `docs/PROGRESS.md`. **Status: planned, not started. Owner questions below are unanswered: ask them (offer the bold defaults), record the answers at the top of this file, then build.**
**Accept (from SPEC):** report numbers match fixture data exactly; the bot section lists top unanswered questions; the report is delivered to a test destination.

## What this phase is, in plain words
Every month the client should see proof that the service is worth paying for: how many chats came in, how fast the team answered, how happy customers were, how much the bot handled, whether the system stayed up, that backups work, and what we changed. This phase builds `opskit report <client> --month YYYY-MM`, which collects those numbers into one data file and renders a clean page (Bangla or English headings per client) that you can send to the client. It can run by itself on the 1st of each month.

## Facts to verify first (task 9.1; none of this is checked yet)
- Chatwoot has reporting routes (`summary_reports`, `reports`, `live_reports`, CSAT survey responses). Exact parameters, which numbers they return (conversations by inbox/channel, first response time, resolution time, CSAT), their time-zone handling and whether the admin token may read them must be tested live on the demo stack. Record in `docs/EXPLORATION_REPORT.md`.
- **Monitoring history does not exist yet:** Phase 4 keeps only the current state. Uptime % and incidents need a small history file written by the monitor (task 9.2).
- The bot (Phase 8) keeps its counts and unanswered questions in its own SQLite (`/metrics`, `AuditDb.metrics()/unanswered()`); they are all-time, so they need a date range (task 9.4).
- Backups and the restore tests leave a manifest and logs per run (Phase 3); upgrades leave `history.jsonl` (Phase 5).
- No ops-hub exists (ADR-016): delivery is Telegram and/or a file.

## Open questions for the owner (plain words; defaults in bold)
1. **How is the report delivered?** **Default:** the report file is saved on the host and a short summary plus the file is sent to **your** Telegram; you forward it to the client. Alternative: email it straight to the client from their own Chatwoot mail settings (needs the client's SMTP working).
2. **What format?** **Default:** one self-contained HTML page (works offline, prints to PDF from any browser), headings in the client's languages (Bangla/English).
3. **When?** **Default:** generated automatically on the 1st of the month at 08:00 client time for the previous month (`report.day_of_month`, changeable) and also on demand.
4. **Customer questions in the report.** The "top questions the bot could not answer" are customer text. **Default:** shown (up to 10, phone numbers and emails masked) because they tell the client what to add to the FAQ; switch off per client with `report.show_unanswered: false`. The owner copy and the client copy are the same page.
5. **Hours used vs included.** **Default:** optional file `clients/<id>/changes.yaml` where you log work done for the client (date, what, hours); if it does not exist this section is left out.
6. **Targets.** **Default:** no targets or colours judging the client (just numbers and the change since last month); you decide how to talk about them.

## Tasks

### [ ] 9.1 — Verify the Chatwoot reporting numbers live
- **Goal:** on a demo stack with seeded conversations (several inboxes, replies at known times, resolved conversations, a few CSAT answers): call the reporting routes with the admin token, record parameters and shapes, check the numbers against what was seeded, and note the time-zone behaviour. Save sample responses as fixtures (fictional data only).
- **Acceptance:** findings in EXPLORATION_REPORT; fixtures committed; list of the exact numbers the report will use and where each comes from.

### [ ] 9.2 — Monitoring history
- **Goal:** `opskit monitor run` appends one line per check run to `clients/<id>/monitor-history.jsonl` (time, overall state, which checks failed; no message text, no secrets), with pruning after 400 days; `lib/` helper to compute uptime % and incident list for a month from it. Existing monitor tests must keep passing.
- **Acceptance:** bats: uptime and incidents computed exactly from a fixture history including a downtime gap and a month boundary.

### [ ] 9.3 — Collector: everything into one JSON
- **Goal:** `lib/report_collect.sh` + a Python helper produce `report-YYYY-MM.json`: chat counts by inbox/channel, first response time and resolution time (median and average), CSAT (count, average, only if enabled), bot numbers, uptime %, incidents, backups made / last restore test result, upgrades done, change hours. Each section can be missing (feature off) and the report says so instead of showing zeros.
- **Acceptance:** with the seeded demo and fixtures the JSON numbers equal the expected values exactly (pytest/bats against fixtures; one live run).

### [ ] 9.4 — Bot numbers for a date range
- **Goal:** the bot's `/metrics` accepts `since` and `until` (and the unanswered list too); numbers: answered, handed off by reason, errors, average time, top unanswered questions (masked). Pytest for exact counts across a month boundary.
- **Acceptance:** pytest and one live check on the demo bot.

### [ ] 9.5 — Renderer
- **Goal:** `lib/report_render.py`: JSON to one self-contained HTML page (no external fonts or scripts), headings in the client's languages (Bangla texts marked review-needed until the owner approves), month-on-month change, simple inline charts (SVG), print-friendly. No customer names; no message text except the optional masked unanswered questions.
- **Acceptance:** snapshot tests on a fixture JSON; page opens offline; Bangla renders (checked in a headless browser screenshot).

### [ ] 9.6 — `opskit report` command and delivery
- **Goal:** `opskit report <id> --month YYYY-MM [--send]`; a monthly cron line rendered like the backup and monitor ones; `--send` posts the summary and the file to the owner's Telegram through the existing sender; the report is stored in `clients/<id>/reports/`. Never overwrites an existing month without `--force`.
- **Acceptance:** bats with the fake Telegram: file saved, message sent, rerun refuses without `--force`.

### [ ] 9.7 — Selftest rows and live acceptance
- **Goal:** `opskit selftest` seeds data, generates a report for the current month and checks key numbers and that the file contains no message text or secrets.
- **Acceptance:** rows pass in `opskit selftest`.

### [ ] 9.8 — Docs, verification, security review
- **Goal:** `docs/runbooks/care-report.md`, ADR, ASSUMPTIONS, ENVIRONMENT, PROGRESS verification report; security review (no PII, masked questions, file permissions, upstream-path test clean).
- **Acceptance:** `opskit/bin/check` passes; report written.

## Not in this phase
A client portal or dashboard, per-agent performance, billing/invoicing, email delivery through a shared hub, comparisons between clients.
