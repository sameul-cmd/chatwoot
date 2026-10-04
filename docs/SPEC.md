# Inbox Ops Kit (Chatwoot fork) — Product & Technical Specification (V1.0)

> **Omnichannel customer inbox + business-scoped AI first replies, hosted and cared for — on Chatwoot Community Edition.**
> **Source of truth:** this SPEC. The owner's roadmap `06-chatwoot-roadmap.md` (25 Sep 2026) is a **reference only**. Binding owner decisions (27 Sep 2026): fork `chatwoot/chatwoot`; Community Edition (MIT, `-ce` images) only; hosting = one install per client now, with the data model ready for a shared multi-account install later; AI bot = dedicated service in the fork; scope C — all 9 improvements (Section 2.1), built only after Phase 0; languages Bangla + English; alerts and reports through the **shared ops-hub** of the owner's Activepieces project (roadmap 05). Research: `docs/RESEARCH.md`.

---

## 0. Instructions for the AI coding agent (READ FIRST)

1. **This repo is a fork of `chatwoot/chatwoot`.** Upstream's `AGENTS.md`/`CLAUDE.md`/`.windsurf/rules` govern upstream code. Our product rules are this SPEC, the IDE entry file (`AGENTS.fork.md` for Kilo, `.factory/AGENTS.md` for Factory) and the rules they load.
2. **Phase 0 installs and explores Chatwoot as it is:** fork, run it locally in WSL2 (official Docker production path, CE image), try every feature, observe the agent-bot webhook, fill `docs/EXPLORATION_REPORT.md`. No kit/bot code, no upstream changes. Then continue — ask the owner **only** if something blocks the plan.
3. **Build phase by phase** (Section 17); each phase passes acceptance before the next.
4. **Community Edition only.** Use `-ce` image tags; never enable, import, copy or modify anything in `enterprise/` (commercial license); never add a license key; never remove "Powered by Chatwoot" branding.
5. **Upstream files change only via the patch ledger** (`docs/UPSTREAM_CHANGES.md`). Our code: `opskit/`, `aibot/`, `.github/workflows/opskit-*.yml`, `docs/`, IDE config.
6. **Critical live system:** every change that can affect a client's running inbox needs a backup first, staging validation, and a rollback path. Destructive commands need explicit owner approval in chat.
7. **WhatsApp compliance:** the AI bot answers only the client's business topics, discloses it is automated, never claims to be human, and hands off to a person on request or when unsure. Official WhatsApp Cloud API only — never unofficial QR-code connectors.
8. **Client data:** conversations are confidential. Client LLM calls use the paid-tier or client-owned keys; the Gemini free tier is for demo data only. No message content in logs outside the client host.
9. All ops commands run in Linux (WSL2 locally, Ubuntu 24.04 on servers). Bash scripts `set -euo pipefail`, shellcheck-clean. The bot is Python 3.12.
10. When this spec is ambiguous, pick the simplest option consistent with Section 3, record it in `docs/ASSUMPTIONS.md`, continue. *(verify)* items must be checked against the pinned version and recorded.
11. Features marked **V2** must NOT be built.

---

## 1. Product overview

**Inbox Ops Kit** is the owner's fork of Chatwoot plus:
- **opskit** — deploy, back up, monitor, upgrade, configure channels, apply industry packs, and report on one Chatwoot install per client.
- **aibot** — a per-client AI first-reply agent connected through Chatwoot's Agent Bot webhooks: answers from the client's knowledge base in Bangla or English, stays on business topics, hands off to humans.
- **Own CE images** (amd64 + arm64) built by CI from the pinned release.

**Buyers (roadmap):** f-commerce/e-commerce stores (Bangladesh, South Asia), clinics/diagnostic centers, travel agencies/education consultants, small SaaS/service companies, agencies. Best first market: the owner's time zone.

**Positioning (research):** Chatwoot Cloud costs $19–$99 per agent/month; self-hosted CE has no per-agent fee. Captain AI isn't in CE, so the owner's bot is the AI product. Cheap marketplace installs often exclude WhatsApp/Facebook; the service sells channels + AI + Bangla + reliability.

### Glossary
| Term | Meaning |
|---|---|
| Upstream | `github.com/chatwoot/chatwoot`; remote `upstream`, fetch-only. Stable = release tags (`master`), dev = `develop`. |
| Pinned release | Upstream release tag our `main` is based on. |
| Client stack | One Chatwoot install for one client: rails, sidekiq, postgres, redis, aibot, storage volume, Caddy site. |
| Account | Chatwoot's tenant inside an install (V1: one per install; V2 shared mode: many). |
| Inbox / channel | Website widget, email, WhatsApp Cloud API, Facebook, Instagram, Telegram, etc. |
| Agent bot | Chatwoot's webhook-based bot attached to inboxes (CE feature). |
| aibot | Our bot service; one container per client stack. |
| KB | Client knowledge base: `kb/*.md|yaml` FAQs + optional Help Center articles. |
| Pack | Industry starter pack: canned responses, labels, automation rules, business hours, auto-reply texts (bn + en). |
| Ops-hub | Shared with the Activepieces project: Activepieces alert-router/report flows + Uptime Kuma. |

---

## 2. Scope

### 2.1 Agreed improvements (owner, scope C, 27 Sep 2026) — all built after Phase 0
| # | Improvement | Phase |
|---|---|---|
| 1 | Client deployment kit (CE image, HTTPS, SMTP, firewall, sizing, automatic migrations) | 2 |
| 2 | Backups + restore (DB, uploads, secrets escrow, off-server, tested restores) | 3 |
| 3 | Monitoring + alerts via shared ops-hub (uptime, sidekiq, channel health, disk) | 4 |
| 6 | Safe upgrades (staging, migrations, rollback) | 5 |
| 5 | Channel setup runbooks + checkers (WhatsApp, Facebook/Instagram, email, widget, Telegram) | 6 |
| 7 | Industry starter packs (bn + en) | 7 |
| 4 | AI first-reply bot (aibot) | 8 |
| 8 | Monthly care report | 9 |
| 9 | Own CE images incl. arm64 | 10 |

### V2 (design for, don't build)
**Owner-selected add-ons (4 Oct 2026), to be built only after the first client is live (details and difficulty: `docs/ADDONS.md`; wiring: `docs/TECH_ARCHITECTURE.md` section 7; ADR-014):** order capture in chat (sheet + Telegram alert), order-status lookup, auto-labels + angry-customer flag, after-hours replies + review/CSAT requests, daily owner digest on Telegram, agent assist (reply drafts, summaries, translation), self-service FAQ editor, appointment booking. White-label (`brand`) stays an owner decision, default off.
Shared multi-account install for small clients (`install.mode: shared_accounts`; Section 6 keeps fields ready), client self-service portal, bot analytics dashboard, voice channels, custom Chatwoot UI changes, white-label mobile app.

### Never (license/policy)
Enterprise features without a license (Captain, SLA, audit logs, branding removal); unofficial WhatsApp connectors (WAHA, Evolution API, QR-code bridges); general-purpose chatbot behavior.

---

## 3. Architecture rules (non-negotiable)

1. **Fork layout.** Our paths only: `opskit/`, `aibot/`, `.github/workflows/opskit-*.yml`, `docs/` (our files), IDE config, `README-START-HERE.md`, `explore/` (git-ignored scratch).
2. **Pinned releases, manual sync**; `upstream` fetch-only; upstream CI disabled in the fork; syncs via `docs/UPSTREAM_SYNC.md`.
3. **CE images only**: official `chatwoot/chatwoot:<tag>-ce` *(verify tag format)* until Phase 10, then our `ghcr.io/<owner>/chatwoot:<tag>-ce-ops.<n>` (amd64 + arm64).
4. **One client = one stack** (compose project `-p <client_id>`, volumes, `.env`, domain, backups, aibot). `client.yaml` keeps `install.mode` (`dedicated` now; `shared_accounts` reserved) and `accounts[]` so V2 needs no restructuring.
5. **Config as data**: `client.yaml` validated by JSON schema drives rendering; packs and bot config are data (`opskit/packs/`, per-client `bot.yaml`, `kb/`).
6. **Secrets never in git**; generated with `openssl rand`, abort if empty; `.env` mode 600; escrow encrypted with `age`.
7. **API first for Chatwoot configuration**: packs, channel checks, bot registration and reports use Chatwoot's Application/Platform APIs *(verify endpoints)*; read-only SQL only where no API exists, via a read-only role.
8. **Observability through the shared ops-hub**; if the hub is unreachable, host scripts alert the owner directly via Telegram bot API.
9. **aibot is isolated**: runs in the client's compose network, receives webhooks only from that client's Chatwoot (secret path token + internal network), talks back only to that Chatwoot's API with the bot token, and to the configured LLM provider.
10. **Change safety**: backup → staging → smoke → promote → rollback for upgrades; config changes to live inboxes are applied with a dry-run diff first.

---

## 4. Tech stack & environment

| Area | Choice |
|---|---|
| Base | Fork of `chatwoot/chatwoot` (MIT CE), pinned to the latest release tag in Phase 0 (v4.15.1 on 27 Sep 2026) |
| Upstream stack | Rails + Vue, Sidekiq, PostgreSQL (pgvector image in official compose *(verify)*), Redis, ActiveStorage (local volume or S3-compatible) |
| Hosts | Ubuntu 24.04 VPS, ≥ 2 vCPU / 4 GB RAM per client (roadmap + vendor guidance); swap enabled |
| Proxy | Caddy (automatic HTTPS, WebSockets for ActionCable) |
| Firewall | ufw 22/80/443 |
| Email | Client SMTP (or owner's transactional provider) for notifications/password reset; email inbox via IMAP/SMTP or forwarding |
| Backups | `pg_dump` + tar of storage volume + `age`-encrypted `.env` + `rclone` off-server |
| Monitoring | Shared ops-hub (Activepieces flows + Uptime Kuma), UptimeRobot for the hub |
| aibot | Python 3.12, FastAPI, httpx, pydantic, rank-bm25 (retrieval), SQLite (per-client audit/cache), pytest, ruff, mypy; LLM: **owner-supplied key (BYOK) through any OpenAI-compatible endpoint** (ADR-011); Gemini/OpenAI-direct are just presets of the same adapter |
| Laptop | Windows + WSL2 Ubuntu + Docker Desktop, 12 GB RAM (WSL ~7–8 GB) |
| CI | GitHub Actions: `opskit-ci.yml` (shellcheck, bats, aibot tests), `opskit-image.yml` (multi-arch CE images → GHCR) |

---

## 5. Actors & permissions
| Action | Owner | Client admin | Client agents |
|---|---|---|---|
| Deploy/upgrade/restore/backups/alerts | ✅ | ❌ | ❌ |
| Super Admin console | ✅ only | ❌ | ❌ |
| Account admin (inboxes, agents, automations) | ✅ | ✅ | ❌ |
| Reply to conversations | optional | ✅ | ✅ |
| Own Meta/WhatsApp/Facebook, email, domain accounts | helps set up | ✅ owns | — |
| Edit bot KB | ✅ | via owner (V1) | — |

---

## 6. Client registry
`opskit/clients/<client_id>/client.yaml`: `client_id`, `name`, `contact`, `timezone`, `languages: [bn, en]`, `domain` (e.g. `chat.client.com`), `host` {name, ip, ssh_user}, `install` {`mode: dedicated` (V1) | `shared_accounts` (V2), `image`, `tag`}, `accounts[]` {`account_id`, `name`} (V1: exactly one), `sizing` {rails/sidekiq memory limits, sidekiq concurrency}, `smtp` {host, port, user, sender} (password in `.env` only), `storage` {`local|s3`}, `channels[]` {type, name, status}, `pack` (industry id), `bot` {enabled, inboxes[], handoff_team, `llm` {`base_url`, `api_key_env`, `model`, `effort`: `none|low|medium|high|max`, `effort_param`, `max_output_tokens`}}, `alerts` {channels, targets, quiet_hours}, `support` {hours, response_hours: 12, outage_hours: 2}, `backup` {schedule, retention_local: 14, retention_remote: 30, remote}, `report` {recipients, day_of_month: 1}, `status`.

---

## 7. Deployment kit (Improvement 1)
1. `opskit client new|render|deploy|pause|resume|offboard <id>`; `opskit host bootstrap <host>` (Docker, ufw, unattended upgrades, swap, Caddy, agent scripts, SSH hardening check).
2. Rendered compose from the pinned upstream production compose *(verify services)* with: CE image tag, `rails` + `sidekiq` + `postgres` + `redis` + `aibot`, memory limits, healthchecks, named volumes `<id>_postgres`, `<id>_redis`, `<id>_storage`, only Caddy publishing ports.
3. `.env` from the pinned `.env.example` *(verify required keys)*: `SECRET_KEY_BASE`, `FRONTEND_URL=https://<domain>`, Postgres/Redis credentials, `ENABLE_ACCOUNT_SIGNUP=false`, SMTP settings, `ACTIVE_STORAGE_SERVICE`, `RAILS_ENV=production`, `INSTALLATION_ENV` as documented, Meta app IDs when channels need them; secrets generated, abort if empty.
4. Deploy runs `db:chatwoot_prepare` via a one-off rails container *(official step)*, starts services, waits for health, creates the Super Admin + account on first deploy (credentials delivered to the owner's password manager, never logged), verifies HTTPS and WebSockets.
5. Post-deploy checks: login page, widget script loads, sidekiq processing a test job, outgoing email test.

## 8. Backups & restore (Improvement 2)
Nightly: `pg_dump` (via postgres container) + tar of `<id>_storage` (if local storage) + `age`-encrypted `.env` → local (14 days) + `rclone` remote (30 days) → heartbeat to ops-hub. `opskit restore <id> --from <ts> --target staging|new-host` into a fresh stack; never over a running stack without `--overwrite --yes`. Monthly automated restore test (login + recent conversation visible + attachment opens) reported in the care report.

## 9. Monitoring & alerts (Improvement 3)
Ops-hub (shared) receives: uptime checks of `https://<domain>` and the API endpoint *(verify health route)* every minute (Uptime Kuma); host cron every 5 min: sidekiq alive + queue latency/size *(verify method)*, failed jobs growth, disk > 85%, memory pressure, container restarts, cert expiry < 14 days; channel health every 15 min via API: inboxes needing reauthorization or erroring *(verify fields)*; bot health (aibot `/health`, error rate, handoff rate spike). Severities `info|warn|critical`; critical (site down, sidekiq down, channel disconnected) → owner Telegram immediately + client channels per config; quiet hours for non-critical. Fallback: direct Telegram if the hub is unreachable.

## 10. Safe upgrades (Improvement 6)
`opskit upgrade <id> --to <tag>`: show release notes + checklist (`docs/runbooks/upgrade-checklist.md`) → backup → staging stack restored from backup on the new image → `db:chatwoot_prepare` → smoke tests (login, API, widget message round trip, sidekiq job, bot reply on staging inbox) → schedule production upgrade in the client's off-hours → production upgrade → smoke → rollback (previous tag + DB restore if migrations ran) on failure → record history.

## 11. Channel runbooks & checkers (Improvement 5)
Runbooks in `docs/runbooks/`: `website-widget.md`, `email.md` (IMAP/SMTP + forwarding), `telegram.md`, `whatsapp-cloud-api.md` (client-owned Meta Business account, phone number not on the WhatsApp app, verification, webhook URL + verify token, templates, 24-hour window, costs billed to client), `facebook-instagram.md` (self-hosted Meta app setup per official docs, app review notes). `opskit channels check <id>`: lists inboxes via API, flags disconnected/reauthorization-needed, verifies webhook endpoints reachable over HTTPS, sends a test message where a test path exists (widget, Telegram, email loopback), outputs a PASS/WARN/FAIL table. `opskit channels plan <id>` prints the client's to-do list (what they must create/verify in Meta, domain DNS, mailbox).

## 12. Industry starter packs (Improvement 7)
`opskit/packs/<industry>/` for `fcommerce`, `clinic`, `travel`, `education`, `service` (+ `generic`): `canned_responses.yaml` (short code, bn text, en text), `labels.yaml`, `automations.yaml` (auto-assign by inbox, business-hours auto-reply, keyword labels like "order/অর্ডার", "price/দাম"), `business_hours.yaml`, `auto_replies.yaml` (out-of-office, greeting), `kb_starter/` (FAQ skeleton for the bot). `opskit pack apply <id> <industry> [--dry-run]`: idempotent create/update via API with a diff first; never deletes client-made items. Bangla texts are written/proofread by the owner (native speaker) — the agent drafts, marks `review_required: true` until approved.

## 13. aibot — AI first-reply bot (Improvement 4)
1. **Wiring:** per client, an Agent Bot registered in Chatwoot pointing to `http://aibot:8000/webhook/<secret>` inside the compose network *(verify registration via Super Admin/Platform API and webhook payloads)*; attached to selected inboxes. New conversations start with the bot *(verify: pending status flow)*.
2. **Knowledge:** `kb/` Markdown/YAML FAQs per client (+ optional import of Chatwoot Help Center articles via API); chunked; BM25 retrieval (bn + en tokenization; banglish handled by also matching transliterated keywords list in KB).
3. **Answering:** detect reply language (Bangla script, English, banglish → Bangla or English per client default); retrieve top-k; LLM prompt restricted to retrieved snippets + business profile; must return JSON `{answer, confidence, used_ids, handoff}`; answer only if confidence ≥ `bot.min_confidence` (default 0.7) and at least one snippet used.
4. **Handoff:** on low confidence, off-topic, human request ("agent", "human", "মানুষ", "এজেন্ট", configurable), complaint/anger keywords, `max_bot_turns` (default 3), or LLM error → post handoff message (bn/en), set conversation to open for humans, add label `ai-handoff`, assign team per config *(verify API calls)*.
5. **Policy guardrails (WhatsApp 2026):** business topics only; first bot message discloses automation (e.g. "I'm {business}'s automated assistant"); never claims to be human; no prices/promises unless present in KB; refuses general questions with an offer to connect a person; replies only to inbound messages.
6. **Data / LLM (BYOK, ADR-011):** the owner supplies the key and endpoint; aibot calls any OpenAI-compatible `/chat/completions` API (custom `base_url`). `opskit llm models <client>` lists the endpoint's `/models` and lets the operator pick one (writes `bot.llm.model`); `opskit llm effort <client>` sets reasoning effort `none|low|medium|high|max`, sent as `reasoning_effort` (name configurable via `effort_param`; value mapping configurable per endpoint because "max" is not universal; unsupported → fall back to the highest accepted value and log a warning, never fail the reply). Default effort `medium` (chat latency); `max` is selectable. Key lives in the env var named by `api_key_env`, never in git. Client-data rule: the key must be paid-tier/owner-owned (flag `AIBOT_LLM_TIER_PAID=true`); free tiers only for demo data. SQLite audit (question, answer, used KB ids, confidence, handoff reason) kept `audit_days: 30`, stays on the host; logs contain no message text.
7. **Evaluation gate:** `aibot eval <client>` runs the client's test set (≥ 20 questions incl. off-topic, Bangla, banglish, human request) and reports correct / handed-off / wrong; go-live requires 0 wrong prices/policies and ≥ 90% correct-or-handed-off (roadmap: 20 test questions, correct handoff when unsure).
8. **Ops:** `/health`, metrics (answers, handoffs, errors, latency) pushed to ops-hub daily; kill switch `bot.enabled: false` detaches the bot without redeploying Chatwoot.

## 14. Monthly care report (Improvement 8)
`opskit report <id> --month YYYY-MM`: conversations (by inbox/channel), first response time, resolution time, CSAT (if enabled) via Reports API *(verify)*; bot stats (answered, handed off, top unanswered questions → KB to-do); uptime %; backups + last restore test; upgrades; incidents; change hours used vs included. HTML (bn/en headings per client) delivered by the ops-hub email flow on `report.day_of_month`.

## 15. Own CE images incl. arm64 (Improvement 9)
`opskit-image.yml`: build from the pinned tag with `docker buildx` for `linux/amd64,linux/arm64` using upstream's Dockerfile *(verify path)* **in CE form** — reproduce how upstream produces `-ce` images (e.g. build without `enterprise/`) *(verify)*; push `ghcr.io/<owner>/chatwoot:<tag>-ce-ops.<n>`; smoke-test the image in CI (boot, migrations on empty DB, health). Deployment kit switches to these images after acceptance.

## 16. Commands & environment
Laptop: WSL Ubuntu. `opskit/bin/check` (shellcheck + bats + aibot ruff/mypy/pytest; `--quick` skips docker integration), `opskit/bin/opskit doctor`, `opskit/bin/opskit selftest` (local demo client: deploy → pack apply → widget message → bot answers from demo KB → handoff → backup → restore → teardown; uses a fake LLM). Details: `docs/ENVIRONMENT.md`.

---

## 17. Build phases

Each phase: implement → `opskit/bin/check` → (from Phase 2) `opskit/bin/opskit selftest` → acceptance → update `docs/PROGRESS.md` → continue.

### Phase 0 — Fork, set up & explore Chatwoot (as it is, no changes)
Fork; clone in WSL (`~/work/chatwoot-ops`); `upstream` fetch-only; pin `main` to the latest release tag (record tag + SHA); disable upstream GitHub Actions in the fork. Install locally with the **official Docker production** path using the **CE image tag**, run `db:chatwoot_prepare`, create Super Admin + account. Explore: Super Admin console; account settings; website inbox + widget test page; email inbox (test mailbox via IMAP/SMTP); Telegram inbox (free bot); WhatsApp Cloud API with Meta's test number if the owner has a Meta developer account *(verify availability; free)*; Facebook/Instagram — document requirements only unless easy; conversations, assignments, private notes, labels, canned responses, macros, automations, business hours, teams, auto-assignment, contacts/segments, campaigns, help center portal, reports, CSAT; UI language Bengali; integrations list (what CE offers); Application/Platform API tokens and a few calls; **Agent Bot**: create one, point it at a local listener (`explore/` script), capture payloads for a new conversation and replies, reply via API, test handoff (status change) — record exact fields; mobile app login via ngrok HTTPS; local backup (pg_dump + storage) → restore into a fresh stack; RAM/CPU at idle and with 50 test conversations (roadmap load check). Fill every section of `docs/EXPLORATION_REPORT.md` including answers to all *(verify)* items and a CE feature matrix. No kit/bot code.
**Accept:** CE instance runs locally; widget + one more channel round-trip works; agent-bot payloads and reply/handoff API calls documented from real captures; backup → restore proven; RAM numbers recorded; blockers logged and owner asked before continuing.

### Phase 1 — Opskit foundation
Structure (`opskit/bin`, `lib`, `schema`, `templates`, `agent`, `packs`, `tests`, `clients`+`hosts` git-ignored), `aibot/` skeleton (FastAPI app, config, tests), `bin/check`, `doctor`, `opskit-ci.yml`, schemas for `client.yaml`/`bot.yaml`, docs ledger/sync completed.
**Accept:** `opskit/bin/check` passes locally and in CI; invalid configs fail with field messages; `git diff <pinned-tag> --stat` lists only our paths.

### Phase 2 — Client deployment kit (Improvement 1)
Commands and templates per Section 7, local WSL practice host, `selftest` v1 (deploy → health → widget loads → teardown).
**Accept:** rendered stack uses the CE tag, memory limits, only Caddy exposed, `ENABLE_ACCOUNT_SIGNUP=false`; secret generation aborts on empty values (bats); `db:chatwoot_prepare` runs on first deploy and upgrades; test email sends; re-running deploy is idempotent; `client.yaml` accepts `install.mode: dedicated` and rejects `shared_accounts` with "V2".

### Phase 3 — Backups & restore (Improvement 2)
Per Section 8 + monthly restore test job.
**Accept:** restore of a demo client with conversations and an image attachment into a new stack shows both; `.env` escrow decrypts; pruning exact (fixture); overwrite protection works; failed backup raises an alert payload.

### Phase 4 — Monitoring & alerts via shared ops-hub (Improvement 3)
Host agent checks, channel-health poller, ops-hub flows/monitors (added to the Activepieces ops-hub), fallback direct Telegram.
**Accept:** stopping sidekiq triggers a critical Telegram alert within 10 min; stopping the stack triggers an uptime alert; a simulated disconnected inbox is reported; hub-down fallback sends directly; de-duplication prevents repeats within 30 min.

### Phase 5 — Safe upgrades (Improvement 6)
Per Section 10 + checklist runbook + fork sync rehearsal.
**Accept:** upgrading a demo client from the previous to the pinned release passes staging and production smoke tests; injected smoke failure triggers rollback with data intact.

### Phase 6 — Channel runbooks & checkers (Improvement 5)
Runbooks + `channels check/plan`.
**Accept:** `channels check` reports PASS for widget/Telegram/email on the demo client and FAIL for a deliberately broken inbox with a clear fix hint; WhatsApp runbook walked end to end with a Meta test number if available (else documented as pending owner's Meta account).

### Phase 7 — Industry starter packs bn + en (Improvement 7)
Packs per Section 12 + `pack apply` with dry-run diff.
**Accept:** applying `fcommerce` to a fresh demo account creates the listed items; re-applying changes nothing; client-made items are untouched; Bangla texts flagged `review_required` until the owner approves.

### Phase 8 — aibot (Improvement 4)
Service per Section 13, registration, KB tooling, eval command, metrics, kill switch.
**Accept:** on the demo client, the bot answers a KB question in Bangla and in English, hands off on "মানুষ চাই"/"talk to a human", on an off-topic question, and after 3 bot turns; first message discloses automation; `aibot eval` on the demo test set meets the gate; client-mode refuses to start without `AIBOT_LLM_TIER_PAID=true` or a local/client key; no message text in logs (test).

### Phase 9 — Monthly care report (Improvement 8)
Per Section 14.
**Accept:** report numbers match fixture data exactly; bot section lists top unanswered questions; email delivered via ops-hub to a test inbox.

### Phase 10 — Own CE images incl. arm64 (Improvement 9)
Per Section 15.
**Accept:** CI publishes a multi-arch CE image; it boots and migrates in CI; the demo client runs on it; image contains no enterprise features (verified per the method recorded in Phase 0/ADR).

### Phase 11 — Field readiness
Practice production run on a real VPS (Oracle Always Free arm64 with our image if capacity allows, else a small paid VPS): bootstrap → deploy with real domain → widget + email + Telegram (+ WhatsApp test number) → pack → bot with demo KB → backup → remote copy → restore test → upgrade dry run → care report; Bangla demo script (roadmap), `docs/OPERATOR_GUIDE.md`, pricing worksheet.
**Accept:** full run completes from the operator guide without undocumented steps; timings/costs recorded; roadmap testing checklist (Section 9 of roadmap) passed.

---

## 18. Notes for the owner
- Start with clients in your time zone; put support hours and response times in every agreement (defaults: reply within 12 h, outages within 2 h during business hours).
- Clients own their Meta Business, WhatsApp numbers, Facebook pages, domains and mailboxes; WhatsApp message costs are billed to the client's Meta account.
- The ops-hub is shared with the Activepieces project; if that project's Phase 4 isn't done yet, this project's Phase 4 includes a minimal hub setup or uses the direct-Telegram fallback until it is.
- "Powered by Chatwoot" stays (removing it needs a paid license).

## Appendix A — Roadmap items changed by research or owner decisions
| # | Roadmap said | Spec does | Why |
|---|---|---|---|
| R1 | Install via script or Docker | Fork + pinned release + CE images (own multi-arch images later) | Owner wants enhanced repo; default image includes enterprise code; arm64 not official |
| R2 | AI via Activepieces webhook | Dedicated aibot service per client | Owner decision; reliability, latency, testability |
| R3 | "Captain" not mentioned | Captain is paid; CE uses our bot | License |
| R4 | Backups of Postgres | + uploads volume + `.env` escrow + off-server + restore tests | Attachments and secrets matter |
| R5 | UptimeRobot only | Shared ops-hub with sidekiq/channel/bot health | Critical live system |
| R6 | Oracle free VM practice | Needs arm64 image → Phase 10 builds it | Official images amd64-only |

## Appendix B — Open questions for the owner
1. Business name and demo domain (e.g. `chat.yourbrand.com`) for the demo instance?
2. Do you have (or will you create) a Meta developer account for WhatsApp/Facebook testing?
3. Default LLM for client bots: **decided 4 Oct 2026 — owner BYOK via custom OpenAI-compatible endpoint, model picker, effort up to max (ADR-011).**
4. Which industry pack first (f-commerce recommended)?
