---
name: security-review
description: Review changed code for security and permission problems
---

# Security review

Review all files changed in the current phase (`git diff main...HEAD`). Check against the security, reliability and aibot rules in `.claude/CLAUDE.md`:

1. No secrets, `.env`, keys, dumps, real KBs, audit DBs or `opskit/clients|hosts` content committed or printed.
2. Secret generation aborts on empty values; `.env` mode 600; escrow encrypted with age.
3. Destructive commands require `--yes` + typed client id; restores never overwrite a running stack by default.
4. Hosts: SSH key-only, ufw 22/80/443; Postgres, Redis and aibot not published; signups disabled.
5. Logs/alerts/metrics contain no message text, phone numbers or emails.
6. aibot: webhook secret + account/inbox validation, idempotent, answers only from KB, discloses automation, hands off correctly; client mode requires paid-tier or client-owned LLM key.
7. CE images only; nothing from `enterprise/` used or changed; branding intact; no unofficial WhatsApp connectors.
8. Upstream files unchanged unless ledgered and approved; upstream remote push disabled.

Output a table: issue, file:line, severity (high/medium/low), fix suggestion. Don't change code until the user approves.
