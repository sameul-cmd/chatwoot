# Progress

## Current status
- **Current phase:** Phase 6 done locally; next: Phase 7 (industry packs) when the owner says go
- **Current task:** Phase 7 plan written (`docs/tasks/phase-7.md`); waiting for the owner's answers, then start 7.1
- **Last updated:** 2026-10-04

## How we work with the owner (read this first in a new chat)
- The owner is non-technical / semi-technical: explain in plain words, define any technical term, give numbered "do this" steps for anything the owner must do, say what can be skipped and what you will handle yourself. Never ask the owner to type commands unless unavoidable; then give the exact text and what it does.
- Rhythm per phase: write `docs/tasks/phase-N.md` with open questions in plain words and **bold defaults**, wait for the owner ("all defaults ok" or changes), then build task by task, run `opskit/bin/check`, write the verification report here, commit + push to branch `claude/wizardly-babbage-ui2rpa`, then summarize in plain words and ask about the next phase. Report honestly what is NOT verified.
- Binding owner decisions so far: BYOK OpenAI-compatible LLM (ADR-011); whole backup encrypted to owner key + host key (ADR-015); Telegram-only alerts, no hub (ADR-016); GitHub Actions stays OFF (ADR-013); white-label = owner decision pending, default Chatwoot branding (docs/ADDONS.md); the 8 add-ons in docs/ADDONS.md are V2 (after the first client is live); live upgrades only in the client's off-hours window by default (configurable per client).
- Never edit Chatwoot's own files (0 files differ from v4.18.0; enforced by a test); never touch `enterprise/`.

## Owner to-do list (none of it blocks the next phases; collect results on the owner's own device)
1. Create the offline backup key on the owner's device (`age-keygen -o owner.key`), keep `owner.key` offline, send/commit only the public `age1...` line to `opskit/keys/owner.age.pub`. Real backups refuse to run without it.
2. Create the Telegram alert bot (@BotFather) and run `opskit alerts set-telegram <id>` on the server; optionally a free heartbeat check (healthchecks.io / UptimeRobot) in `OPSKIT_HEARTBEAT_URL` so a dead server is noticed.
3. White-label decision (default: keep Chatwoot branding) and, before a paying client, ask Chatwoot / a lawyer about the "Powered by" footer.
4. Channel tests that need the owner's accounts: Telegram inbox, email (IMAP/SMTP), WhatsApp Cloud API test number, Facebook/Instagram, mobile app; Bengali UI check. Real LLM key/endpoint for the bot (Phase 8).
5. A real VPS + domain for Phase 11.

## Lessons for the agent (hard-won; avoid repeating)
- Always quote heredocs (`<<'EOF'`) when the text contains backticks or `$`; an unquoted one executed commands once.
- `docker compose exec` inside a `while read` loop swallows the loop's stdin: add `</dev/null`.
- Unit tests with fake docker/psql hide real bugs (a text-column `coalesce` bug): run the real stack before calling something done.
- Do not use `pkill -f` patterns that can match your own command line; kill by exact PID.
- Cloud sandbox: the Docker daemon is not started automatically (`opskit/bin/dev-setup` does it); behind the proxy use `OPSKIT_BUILD_CA=/root/.ccr/ca-bundle.crt`; Docker Hub rate limits (HTTP 429) are common: use `OPSKIT_AIBOT_IMAGE=opskit-aibot:test` (built earlier) or retry; a restarted sandbox keeps the disk but not running containers.
- The API header must be `api-access-token` (with dashes) through Caddy.
- Long runs (> 8 min) must go in the background with a log file and polling; the tool time limit is 10 minutes.

## Machine setup (new session / new machine)
`opskit/bin/dev-setup` installs/starts everything needed (system tools, Python libs, uv + Python 3.12, aibot deps, Docker daemon) and ends with `opskit/bin/opskit doctor`. Then `opskit/bin/check --quick` (1 min) or `opskit/bin/check` (about 13 min, includes both selftests).

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Chatwoot | Done on cloud sandbox; owner-account tests (Telegram, email, WhatsApp, Meta) and Bengali UI check pending on owner device | cloud-verified 2026-10-04 |
| 1 | Opskit foundation | Done (verified locally; GitHub CI intentionally not enabled) | local `opskit/bin/check` passes (18 bats, 17 pytest, shellcheck) |
| 2 | Client deployment kit | Done locally (real host / real SMTP / real HTTPS NOT VERIFIED) | `opskit/bin/check` (non-quick) passes incl. selftest, 2026-10-04 |
| 3 | Backups & restore | Done locally (real off-server storage / real host cron / new-host restore NOT VERIFIED) | `opskit/bin/check` (non-quick) passes incl. selftest v2, 2026-10-04 |
| 4 | Monitoring & alerts (Telegram-only, ADR-016) | Done locally (real Telegram / real-host cron / hub NOT VERIFIED) | opskit/bin/check (non-quick) passes incl. 8 monitoring scenarios, 2026-10-04 |
| 5 | Safe upgrades | Done locally (real server / real client data / bot check NOT VERIFIED) | opskit/bin/check (non-quick) passes incl. selftest upgrade, 2026-10-04 |
| 6 | Channel runbooks & checkers | Done locally (real Telegram / WhatsApp / Meta / Gmail side NOT VERIFIED) | full `opskit/bin/check` was still running when this was pushed: bats suites passed, selftests PENDING (update this row when it finishes) |
| 7 | Industry starter packs bn + en | Planned (task file `docs/tasks/phase-7.md`, awaiting owner answers to 8 questions) | — |
| 8 | aibot | Not started | — |
| 9 | Monthly care report | Not started | — |
| 10 | Own CE images incl. arm64 | Not started | — |
| 11 | Field readiness | Not started | — |

## Task log
<!-- Newest first. For each task: date, task, files changed, how to verify manually, notes. -->
- 2026-10-04 Phase 6 (6.1-6.12): opskit/lib/{channels,channels_social,channel_hints}.sh, lib/{mail_probe,channel_plan}.py, data/channel_plan.yaml, schema channel_plan + typed `channels[]`, templates/rails/read_channel_secret.rb, tests/{fake_mail,fake_meta}.py + sim_channels.rb/sim_email.rb, commands `channels check|plan`, runbooks website-widget/email/telegram/whatsapp-cloud-api/facebook-instagram. Verify: `opskit/bin/opskit channels check <id>`, `opskit selftest`
- 2026-10-04 Phase 5 (5.1-5.11): opskit/lib/{upgrade,smoke}.sh, opskit/bin/sync-rehearsal, schema upgrade_window + support, backup manifest schema_version, command `upgrade <id> --to <tag> --info|--stage|--apply`, `client new --tag`, selftest upgrade, bats upgrade/sync_rehearsal, docs/runbooks/upgrade.md + upgrade-checklist.md. Verify: opskit/bin/check -> ALL CHECKS PASSED incl. SELFTEST UPGRADE PASSED.
- 2026-10-04 Phase 4 (4.1-4.10): opskit/lib/{notify,alert_state,health,channels_health,monitor}.sh, templates/rails/ensure_monitor.rb, templates/monitor.cron.tmpl, schema alerts, commands monitor run|status and alerts set-telegram|test, selftest v3 (8 monitoring rows), bats notify/alert_state/health/monitor, tests/fake_telegram.py, docs/runbooks/monitoring.md, opskit/hub/README.md. Verify: opskit/bin/check -> ALL CHECKS PASSED incl. the monitoring rows.
- 2026-10-04 Phase 3 (3.1-3.11): `opskit/{lib/{crypto,alert,prune,backup,restore,chatwoot_api}.sh, agent/backup.sh, templates/backup.cron.tmpl}`, schema `backup`, commands `backup run|list|verify`, `restore`, selftest v2, bats `backup_lib/backup_agent/backup_run`, `docs/runbooks/restore.md`. Verify: `OPSKIT_BUILD_CA=... opskit/bin/check` -> ALL CHECKS PASSED incl. SELFTEST PASSED (backup + restore test + overwrite protection rows).
- 2026-10-04 Phase 2 (2.1-2.11): `aibot/Dockerfile`, `opskit/templates/*`, `opskit/lib/{secrets,render,deploy,checks,ssh}.sh`, `opskit/agent/bootstrap.sh`, `opskit/bin/opskit` (client new/render/deploy/check/pause/resume/offboard, host bootstrap, selftest), bats `render.bats` + `host.bats`, `docs/runbooks/deploy.md`. Verify: `OPSKIT_BUILD_CA=/root/.ccr/ca-bundle.crt opskit/bin/check` (sandbox) or `opskit/bin/check` (normal machine) -> ALL CHECKS PASSED incl. SELFTEST PASSED; manual: runbook `docs/runbooks/deploy.md`.
- 2026-10-04 Phase 1 (1.1-1.10): `opskit/{bin,lib,schema,tests}`, `aibot/{pyproject.toml,src/aibot,tests}`, `.github/workflows/opskit-ci.yml`, `docs/HANDOVER.md`. Verify: `opskit/bin/check --quick` -> ALL CHECKS PASSED; `opskit/bin/opskit doctor`; `opskit/bin/opskit client validate opskit/tests/fixtures/client_shared.yaml` -> "V2" message. Not verified: the CI workflow itself (needs enabling on GitHub).

## Setup notes
- **GitHub Actions is intentionally DISABLED for the whole fork (owner decision, 2026-10-04).** GitHub cannot enable a single workflow while Actions is off, and enabling it would also start Chatwoot's own scheduled workflows (hourly/nightly/daily). So `.github/workflows/opskit-ci.yml` exists but never runs; the same checks run locally via `opskit/bin/check`. Do NOT ask the owner to "enable opskit-ci". Revisit at Phase 10 (image builds) with one of: per-workflow disable of Chatwoot's workflows, or an approved patch-ledger entry removing them. Until then every "CI passes" criterion is checked locally.
- Repo = upstream `chatwoot/chatwoot` at v4.18.0 + our kit. Developed with Claude Code in a cloud session; branch `claude/wizardly-babbage-ui2rpa`.
- Agent rules: `.claude/CLAUDE.md` (force-added; upstream .gitignore ignores `.claude/`). Skills: `.claude/skills/`.
- Anything needing the owner's accounts (Telegram, WhatsApp, email, VPS) is coded here and proven later on the owner's device; see `docs/HANDOVER.md` (created as we go).

## Phase 0 - owner-side items (do on your own device later)
- Telegram, email (IMAP/SMTP), WhatsApp Cloud API test number, Facebook/Instagram, mobile app via ngrok, Bengali UI check.

## Open owner decisions
- (resolved 2026-10-04) Backup encryption scope: owner chose A - whole backup encrypted to owner key + host key (ADR-015).
- White-label (Option 3, default off) and which add-ons to build: see `docs/ADDONS.md`. Nothing is built for these yet.

## Known issues
<!-- Bugs or gaps found outside current task scope. -->

## Phase verification reports
### Phase 6 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| `channels check` PASS for widget / email / Telegram on the demo client | PASS (our side) | live demo: 16 PASS rows; widget round trip, API inbox round trip, email IMAP+SMTP login (fake mail server) and loopback, Telegram webhook endpoint + `getWebhookInfo` (fake Telegram), WhatsApp settings + verify handshake + wrong-token refusal (fake Meta) |
| FAIL with a plain fix hint for broken inboxes | PASS | 7 FAIL rows on deliberately broken/dead inboxes (wrong email password -> "mail server rejected the login ... APP PASSWORD"; incomplete WhatsApp settings; dead Telegram webhook), each with a `fix:` line; command exits 1 |
| No secrets printed | PASS | selftest asserts no token/password in output; tokens go to curl through stdin config, mail prober never prints passwords; probes are read-only |
| `channels plan <id>` client/owner to-do list en + bn | PASS | bats `channel_plan.bats` (7); Bangla flagged `review_required` |
| Runbooks (5) | WRITTEN, not yet tried with real accounts | `docs/runbooks/*`; facts from Chatwoot code + public docs (web search) |
| `opskit selftest` incl. channel rows | PASSED earlier in the session (before wording edits); final full-check run PENDING | update when `opskit/bin/check` finishes |
| Upstream files unchanged | PASS | upstream-path bats test: 0 files differ from v4.18.0 |
Bugs found and fixed during the phase: `docker exec` stdin swallowing, status-code concatenation ("000000"), subshell-lost status variables, fake IMAP lacking `EXAMINE`, patched-upstream gap in `sync-rehearsal`.
NOT VERIFIED: anything that needs the real Telegram, Meta/WhatsApp, Facebook/Instagram or Gmail/Microsoft servers (sandbox cannot reach them) - the WhatsApp runbook has NOT been walked with a Meta test number (pending the owner's Meta account); Gmail/Workspace OAuth wording and WhatsApp billing change of 1 Oct 2026 come from web research (A-029, *(verify)*); the Bangla texts need proofreading.

### Phase 5 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| Upgrading a demo client from the previous to the pinned release passes staging and production smoke tests | PASS | live + selftest upgrade: v4.17.1-ce -> v4.18.0-ce; rehearsal on a copy (93 s, 3 migrations applied) then live upgrade (~70 s); both smoke suites 9/9 PASS + 1 WARN (bot reply skipped); version 4.18.0, migrations 177 -> 180, conversation + attachment intact |
| Injected smoke failure triggers rollback with data intact | PASS | OPSKIT_UPGRADE_FAIL_SMOKE=production: rolled back to v4.17.1-ce, database restored (version changed), smoke tests on the old version PASS with exact data match (strict), 177 migrations and the conversation restored, critical alert written, history line `rolled_back` |
| Fork sync rehearsal | PASS | `sync-rehearsal v4.17.1 v4.18.0` on the real repo: kit applied on v4.17.1, v4.18.0 merged cleanly, only our paths differ; real HEAD unchanged, no worktree left; bats covers conflicts + ledger rule |
| Preflight refusals | PASS (bats) | same/older/non-CE tag, unhealthy stack, missing/failed/stale (24 h) rehearsal, outside the window (+ --outage-fix override) |
| Off-hours window | PASS (bats, fake clock) | 01:00 inclusive - 05:00 exclusive in the client time zone, custom window, anytime mode, local stacks exempt |
| Release information | PASS | live: 123 commits, 3 migrations, new setting SLACK_SIGNING_SECRET, compose unchanged; bats on a fixture repo |
| History + safety | PASS | one JSON line per attempt (no secrets); typed client id + `--yes` for the live upgrade; dated client.yaml copies |
Bugs found and fixed during the phase: `coalesce(max(version),0)` on a text column (backup failed on a real database while the fake-docker unit test passed); rehearsal initially ignored patched upstream files; apply-failure message for non-applying kit.
NOT VERIFIED: upgrade on a real server/large database, multi-version jumps, WhatsApp/Telegram behaviour during the downtime, the bot reply check (Phase 8), real Telegram messages for started/finished/rolled back.
Test totals: 142 bats tests, 19 pytest, shellcheck clean.

### Phase 4 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| Stopping Sidekiq triggers a critical Telegram alert within 10 minutes | PASS (pretend Telegram) | selftest: sidekiq container stopped -> CRITICAL message at the first 5-minute cycle |
| Stopping the stack triggers an uptime alert | PASS | selftest: whole stack stopped -> CRITICAL Website + Services |
| A simulated disconnected inbox is reported | PASS | selftest: Google-style email inbox with missing credentials -> CRITICAL "needs to be re-connected"; fixed -> RESOLVED |
| Hub-down fallback sends directly | PASS (by design: Telegram-only, ADR-016) | no hub exists; Telegram unreachable -> alert kept in outbox, exit 3, delivered next cycle |
| De-duplication prevents repeats within 30 minutes | PASS | bats: exact 30-min boundary, flapping deferred; selftest: no repeat at +5 min; critical reminder at 2 h; one RESOLVED |
| Quiet hours | PASS (bats, fake clock) | warnings held and released as one summary, spans midnight, uses client time zone; critical never held |
| No secrets / message text in alerts | PASS | bats: token absent from logs and outbox; token passed to curl via stdin config, never argv; inbox names stripped of control characters |
Bugs found and fixed during the phase: docker exec swallowing stdin inside a read loop (Sidekiq check wrongly critical), "HTTP 000000" status concatenation, image-build dependency on a rate-limited registry (now OPSKIT_AIBOT_IMAGE).
NOT VERIFIED: real Telegram delivery, cron on a real host, certificate-expiry check on a real domain, hub flows (none exist), channel types without a reauthorization_required flag (Phase 6), "server dead" detection without an external heartbeat service (see opskit/hub/README.md).
Test totals: 119 bats tests, 19 pytest, shellcheck clean.

### Phase 3 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| Restore of a demo client with conversations and an image attachment into a new stack shows both | PASS | live: seeded 1 conversation + PNG; `backup verify` and selftest: conversations pass (count + newest id equal manifest), attachment pass (MD5 + size match), login pass; ~65 s |
| `.env` escrow decrypts | PASS | `--identity`: "decrypts-and-matches-live"; bats round trip, wrong key fails without output |
| Pruning exact (fixture) | PASS | bats: exact keep/delete set at the 14-day boundary, newest never deleted, `.partial`/junk ignored, on-disk prune; remote prune exact |
| Overwrite protection works | PASS | live: existing staging refused; `--overwrite` without `--yes` refused; wrong typed id refused (stack untouched); production untouched; correct id replaces staging |
| Failed backup raises an alert payload | PASS | bats: failing agent, unusable remote, missing key each write a critical alert JSON (<=300-char summary, no secrets) and exit non-zero |
| Off-server copy | PASS (local-folder remote) | rclone copy + size check + remote prune; real storage NOT VERIFIED |
| Backup integrity | PASS | zero-size/unreadable dump aborts and leaves no complete folder; lock refuses concurrent runs |
Findings recorded: SECRET_KEY_BASE experiment, plaintext channel secrets in the dump, `api-access-token` header through Caddy (EXPLORATION_REPORT). Bugs fixed: image build now retries on registry 429; password no longer passed on a command line.
NOT VERIFIED: real off-server storage (B2/R2/...), cron on a real host (Debian cron `CRON_TZ` support), restore onto another host (deferred, A-010), large data sizes, restore across Chatwoot versions.
Follow-up done: whole backup encrypted (ADR-015); selftest row "backup is encrypted (no plaintext)" PASS; restore reads with host key or owner key.
Test totals: 73 bats tests, 19 pytest, shellcheck clean.

### Phase 2 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| Rendered stack uses CE tag, memory limits, only Caddy exposed, signup off | PASS | bats `render.bats` 3-5 (tag `chatwoot/chatwoot:v4.18.0-ce`, 7+ `mem_limit`, exactly one `ports:` = Caddy, `ENABLE_ACCOUNT_SIGNUP=false`, no `base` service); live stack: only Caddy bound to host |
| Secret generation aborts on empty values | PASS | bats: fake `openssl` returning nothing aborts; `require_secret`; generated secrets non-empty, mode 600 |
| `db:chatwoot_prepare` on first deploy and on re-deploys | PASS (first deploy + every re-run); real version upgrade flow is Phase 5 | deploy log "running db:chatwoot_prepare" on each run |
| Test email sends | PASS locally (Sidekiq `deliver_later` -> SMTP -> Mailpit); real SMTP NOT VERIFIED | post-deploy check 5/5 |
| Re-running deploy is idempotent | PASS | live re-run: same secrets, "Super Admin already exists", bats idempotent re-render |
| `client.yaml` accepts `dedicated`, rejects `shared_accounts` with "V2" | PASS | bats (validate + render) |
| `selftest` v1: deploy -> health -> widget loads -> teardown | PASS | `SELFTEST PASSED` in ~85 s; 0 containers/volumes/tmp left |
| Post-deploy checks (login, widget script, /api, websocket via Caddy, sidekiq + email) | PASS 5/5 | `client check demo` |
Bugs found and fixed during the phase: admin password complexity (A-008), empty SMTP login lines (A-007), silent exit under `pipefail` in `ensure_admin`.
NOT VERIFIED: `host bootstrap` on a real server (fake-SSH + dry-run only), remote deploy (refused by design until Phase 11, A-005), real HTTPS certificate issuance (local uses Caddy internal CA), real SMTP, Caddy-on-host variant (A-006 deviation), arm64.
Security review: no secrets in tracked files, in compose, or on command lines (`-e NAME` only); secret/env files mode 600 and git-ignored; aibot container runs non-root; upstream-path check clean (0 non-kit files changed, `enterprise/` untouched).
Known limits: the aibot image is built on the target (A-009); `restart: always` containers come back when the sandbox Docker restarts.

### Phase 1 verification (2026-10-04, cloud sandbox)
| Criterion | Result | Evidence |
|---|---|---|
| `opskit/bin/check` passes locally | PASS | ALL CHECKS PASSED: shellcheck, bats (18 tests), aibot ruff + mypy --strict + pytest (17 tests); a deliberately broken script made it fail (exit 1) |
| `opskit/bin/check` passes in CI | NOT APPLICABLE (by owner decision) | `.github/workflows/opskit-ci.yml` written (YAML parsed) but Actions is off for the fork; checked locally instead. `doctor` test assumes docker/yq on the runner (GitHub ubuntu has both) |
| Invalid configs fail with field messages | PASS | bats: missing timezone, bad domain, bad `bot.llm.effort`, `min_confidence` 1.5, bad pack industry each name the field; `shared_accounts` -> "V2" message |
| `git diff <pinned-tag> --stat` lists only our paths | PASS | `opskit/lib/check_upstream_paths.sh` (also a bats test); proven to catch a stray `Gemfile` edit; 0 files in `enterprise/` changed |
| BYOK config (ADR-011) | PASS | schema + pydantic: effort none..max, `api_key_env`, paid-tier rule, key never in repr/JSON/health (tests) |
| `opskit selftest` | N/A | placeholder until Phase 2 (exit 3) |
Leftover scan: no TODO/eval, all scripts `set -euo pipefail`/`-uo pipefail` (check script intentionally continues), no tokens in code, no pycache/.venv tracked.
Differences from SPEC to note: schema validation uses a small Python helper (A-002); pack `review_required` default applied in Phase 7 (A-003); tag `v4.18.0` could not be pushed to the fork, so the path check falls back to the pinned commit SHA.
Not done on purpose: no LLM calls, no webhook, no docker integration tests (later phases).

