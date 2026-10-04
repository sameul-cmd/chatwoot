# .claude/CLAUDE.md — Inbox Ops Kit (fork of chatwoot/chatwoot)

This repo is the owner's fork of Chatwoot (open-source omnichannel support inbox, MIT Community Edition) plus **opskit** (deploy, back up, monitor, upgrade, channel checks, industry packs, care reports — one install per client), **aibot** (per-client AI first-reply agent via Chatwoot Agent Bot webhooks, Bangla + English, business-scoped, human handoff), and our own multi-arch CE images.

**Two instruction sets apply.** Upstream's `AGENTS.md`/`CLAUDE.md`/`.windsurf/rules` govern upstream code. This file (including the rules below) and `docs/SPEC.md` govern opskit and aibot. On conflict: upstream conventions for editing upstream files; SPEC for what we build.

## Document map
| File | Use it for | Authority |
|---|---|---|
| `docs/SPEC.md` | Requirements, phases (Section 17) | **Source of truth** |
| `docs/EXPLORATION_REPORT.md` | Phase 0 findings (CE matrix, agent-bot payloads, verify answers, RAM) | Informs later phases; blockers go to the owner |
| `docs/DECISIONS.md` | ADRs | Binding unless superseded |
| `docs/TECH_ARCHITECTURE.md` | Stack, repo layout, bot flow, sizing | Must follow |
| `docs/USER_FLOWS.md` | Operator/customer flows, edge cases | Derived from SPEC |
| `docs/ENVIRONMENT.md` | Tools, accounts, variables | Must follow |
| `docs/UPSTREAM_CHANGES.md` / `docs/UPSTREAM_SYNC.md` | Pin, patch ledger, sync | Must follow |
| `docs/runbooks/` | Channel, upgrade, restore runbooks (created in phases) | Must follow |
| `docs/RESEARCH.md` | Facts behind SPEC | Background |
| `docs/PROGRESS.md`, `docs/tasks/phase-N.md`, `docs/ASSUMPTIONS.md` | Status, tasks, assumptions | Update every task |

**Conflict order:** SPEC > DECISIONS > TECH_ARCHITECTURE > other docs.

## Session start
1. Read `docs/PROGRESS.md` and the current `docs/tasks/phase-N.md`.
2. Read only referenced SPEC/doc sections.
3. State: phase, task, files to touch (flag upstream files).

## Golden rules
- **Phase 0 = install & explore Chatwoot as it is** (`/explore`): no kit/bot code, no upstream changes. Then continue; ask the owner only when blocked or unclear.
- ONE task at a time. SPEC silent → simplest option consistent with SPEC 3, log in ASSUMPTIONS.
- Never invent Chatwoot env keys, API endpoints, webhook payloads or image tags: verify against the pinned source/docs/running instance; record *(verify)* answers.
- **Community Edition only**: CE images, never touch `enterprise/`, keep branding.
- **Critical live system**: backup + staging + rollback for anything touching a client's running inbox; destructive actions need `--yes`, typed client id, and owner approval.
- **WhatsApp-compliant bot**: business topics only, discloses automation, never claims to be human, hands off when unsure; official Cloud API only.
- Never mark done unless `opskit/bin/check` passes (and `opskit/bin/opskit selftest` from Phase 2).
- Never weaken tests. Don't edit SPEC or anything in `.claude/` without approval.
- Stop and ask before: new dependencies, upstream edits, anything touching a real client host or real customer data.

## Stack
Upstream: Rails + Vue, Sidekiq, Postgres, Redis (Docker, CE images). Ours: Bash opskit (shellcheck, bats, JSON schema, envsubst/yq/jq, Caddy, ufw, age, rclone); aibot Python 3.12 FastAPI (pytest, ruff, mypy); shared ops-hub (Activepieces + Uptime Kuma); GitHub Actions + GHCR. Laptop: Windows + WSL2 + Docker Desktop, 12 GB RAM — run everything in WSL.

## Repo layout (ours)
`opskit/{bin,lib,schema,templates,agent,packs,hub,tests}` · `opskit/clients`, `opskit/hosts` (git-ignored) · `aibot/` · `.github/workflows/opskit-*.yml` · `explore/` (git-ignored) · `docs/`

## Commands (WSL)
`opskit/bin/check` · `opskit/bin/check --quick` · `opskit/bin/opskit doctor` · `opskit/bin/opskit selftest` · `docker compose -p <id> ps`

## End of every task
Update PROGRESS; ADR for architecture choices; ledger for upstream edits; conventional commit.

## Rules (always apply)

### Workflow rules

#### Task loop
1. Plan: list files to create/modify and the approach (max ~10 bullets). Wait for approval if the task touches upstream (non-kit) files, dependencies, secret generation, backup/restore/upgrade logic, bot policy/handoff rules, anything destructive, or any real client host or customer data.
2. Implement in small steps. After each meaningful step, run `opskit/bin/check --quick`.
3. Verify: `opskit/bin/check`, plus the manual check described in the task file.
4. Record: update `docs/PROGRESS.md`; add an ADR to `docs/DECISIONS.md` if an architectural choice was made.

#### Scope control
- Only work on the current task in `docs/tasks/phase-N.md`.
- If you notice a bug outside scope, log it in PROGRESS.md "Known issues". Don't fix it silently.
- Features marked V2/Future in the spec: do not implement. Only keep the data model/interfaces ready.

#### Anti-hallucination
- Before using a library function, confirm it exists in the installed version (read the installed package's types/source or the official docs for that version).
- Before calling an internal function, search the codebase to confirm its name and signature. Don't assume.
- Don't claim something works unless you ran it. Say "not verified" otherwise.
- If a command fails, read the actual error output before changing code. Don't guess-and-retry repeatedly; after 3 failed attempts, stop and report.

#### Context hygiene
- When the conversation gets long, update PROGRESS.md with exact next steps and recommend starting a new task.
- Keep files under ~300 lines; split by responsibility.

### Architecture rules (mirror of SPEC Section 3)

- Our code only in `opskit/`, `aibot/`, `.github/workflows/opskit-*.yml`, `docs/`, IDE config. Everything else is upstream (`04-upstream-fork.md`).
- One client = one stack (`-p <client_id>`: rails, sidekiq, postgres, redis, aibot; own volumes, `.env`, domain, backups). `install.mode` is `dedicated` in V1; `shared_accounts` stays reserved in the schema (reject with "V2").
- `client.yaml` (JSON schema) drives rendering; never hand-edit files on servers.
- Stacks use CE image tags only; deploy/upgrade always run `db:chatwoot_prepare`; only Caddy publishes ports; `ENABLE_ACCOUNT_SIGNUP=false`.
- Configure Chatwoot through its APIs (packs, channels, bot, reports); read-only SQL only where no API exists.
- aibot runs inside the client's compose network; webhooks only from that Chatwoot (secret path), replies only via that Chatwoot's API.
- Changes to live inboxes: dry-run diff first, then apply; upgrades via staging with rollback.
- Scripts: Bash, idempotent; host agent scripts standalone. Bot: Python 3.12, pure logic separated from I/O.

### Security, privacy & license rules

#### Never read, print, or commit
- `.env` files, `opskit/clients/**`, `opskit/hosts/**`, keys, dumps, real client KBs, bot audit databases, conversation exports.

#### Always
- Secrets via `openssl rand`; abort if empty; `.env` mode 600; `.env` escrow encrypted with age.
- Destructive actions (restore over data, delete stack/volumes, drop DB) need `--yes`, typed client id, and owner approval in chat.
- Hosts: SSH keys only, ufw 22/80/443, Postgres/Redis/aibot never published.
- Super Admin credentials go to the owner's password manager; never logged.
- Logs and alerts never contain message text, customer phone numbers or emails; error excerpts ≤ 300 chars without PII.
- Client LLM calls only with paid-tier or client-owned keys (`AIBOT_LLM_TIER_PAID=true` or client key); free tier only for demo data.
- Community Edition only: CE image tags, never touch `enterprise/`, no license keys, keep "Powered by Chatwoot".
- Official WhatsApp Cloud API only; never unofficial QR-code connectors.

### Upstream fork rules

- Upstream `AGENTS.md`, `CLAUDE.md`, `.windsurf/rules` govern upstream code; follow them only for approved upstream patches.
- `main` = pinned release tag + our commits; `upstream` fetch-only; sync only via `docs/UPSTREAM_SYNC.md` when the owner asks; upstream CI disabled in the fork.
- Any upstream file change: approval + ledger row in `docs/UPSTREAM_CHANGES.md` + test, one commit.
- *(verify)* items in SPEC (env keys, compose services, CE image tags, agent-bot payloads, API endpoints, health routes) must be verified against the pinned version and recorded in `docs/ASSUMPTIONS.md` before code depends on them.

### Ops script rules

- `#!/usr/bin/env bash`, `set -euo pipefail`, shellcheck clean, `--help`, quoted variables, no `eval`, `mktemp` + `trap` cleanup, `flock` for cron jobs.
- Remote actions only via `opskit/lib/ssh.sh`; Docker commands always with `-p <client_id>`.
- Chatwoot API calls only via `opskit/lib/chatwoot_api.sh` (timeouts, retries on 429/5xx, no token echo).
- One-line step summaries (`[ok]`/`[warn]`/`[fail]`); non-zero exit on failure; templates fail on unresolved `${...}`.

### Reliability rules (critical live system)

- Backup = DB dump + storage tar + encrypted `.env`, locally and remotely, sizes > 0, heartbeat received. Monthly restore test proves login, a recent conversation and an attachment.
- Restores go into fresh stacks; never over a running one without `--overwrite --yes`.
- Critical alerts (site down, sidekiq down, channel disconnected, bot down) reach the owner's Telegram within 10 minutes; hub-down fallback sends directly.
- Upgrades: backup → staging on new image → `db:chatwoot_prepare` → smoke (login, API, widget round trip, sidekiq, bot) → client off-hours production → smoke → rollback on failure.
- Never deploy or upgrade a client during their business hours unless it's an outage fix.

### aibot rules (SPEC 13)

- Answer only from retrieved KB snippets; LLM must return JSON `{answer, confidence, used_ids, handoff}`; answer only if confidence ≥ `min_confidence` and ≥ 1 snippet used; otherwise hand off.
- Always hand off on: human request (bn/en keywords), complaint/anger, off-topic, `max_bot_turns`, LLM/API errors.
- First bot message discloses automation; never claim to be human; business topics only; no prices, delivery times, or policies unless in the KB (WhatsApp 2026 policy).
- Reply in the customer's language (Bangla script, English; banglish → client default).
- Webhook: validate secret path, account and inbox; ignore outgoing/bot/private messages; idempotent on retries (message id).
- No message text in logs; audit rows stay in the host SQLite for `audit_days`.
- Tests use a fake LLM and a fake Chatwoot; never call real providers in tests.
- Go-live only after `aibot eval` meets the gate (0 wrong prices/policies; ≥ 90% correct-or-handed-off).

### Packs & channels rules (SPEC 11, 12)

- Packs are data (`opskit/packs/<industry>/`), bn + en; Bangla texts `review_required: true` until the owner approves.
- `pack apply` is idempotent, shows a dry-run diff, never deletes client-made items.
- Channel runbooks document client-owned accounts (Meta Business, WhatsApp number, FB page, mailbox, DNS); never create accounts in the owner's name for a client.
- `channels check` reports PASS/WARN/FAIL with a fix hint per inbox; WhatsApp webhooks require valid HTTPS.

### Testing & quality rules

#### Definition of Done
- [ ] `opskit/bin/check` passes (shellcheck, bats, aibot ruff + mypy + pytest; `--quick` skips docker integration)
- [ ] From Phase 2: `opskit/bin/opskit selftest` passes (local demo client, fake LLM)
- [ ] New logic has tests; bugs get a failing test first
- [ ] PROGRESS.md updated with manual verification steps

#### What must have tests
- Secret generation, schema validation (incl. `shared_accounts` rejected as V2), rendering (CE tag, limits, signup off, ports)
- Backup → restore round trip (conversation + attachment), pruning, overwrite protection
- Health/channel checks and alert payloads, de-duplication, hub-down fallback
- Upgrade promote/rollback
- Pack apply idempotency and non-deletion
- aibot: language detection, retrieval, policy gate, every handoff trigger, disclosure, webhook validation/idempotency, no-text logging, key policy, eval scoring
- Care report numbers vs fixtures

#### Tools
shellcheck, bats-core, docker compose in WSL, pytest (+ fake Chatwoot and fake LLM), fixture data with fictional customers only.

### Git rules

- Conventional commits: `feat(opskit): …`, `feat(aibot): …`, `fix(...)`, `test: …`, `docs: …`, `chore: …`.
- Commit per completed task; branches `phase-N-name`; syncs on `sync/<tag>`.
- Never commit secrets, client registries, real KBs, dumps, audit DBs.
- Never push to `upstream`.
