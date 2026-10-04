# Progress

## Current status
- **Current phase:** Phase 3 - Backups & restore (planned)
- **Current task:** Phase 3 plan written (`docs/tasks/phase-3.md`); waiting for owner approval of its 7 open questions (backup/restore logic + secrets), then start 3.1
- **Last updated:** 2026-10-04

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Chatwoot | Done on cloud sandbox; owner-account tests (Telegram, email, WhatsApp, Meta) and Bengali UI check pending on owner device | cloud-verified 2026-10-04 |
| 1 | Opskit foundation | Done (verified locally; GitHub CI intentionally not enabled) | local `opskit/bin/check` passes (18 bats, 17 pytest, shellcheck) |
| 2 | Client deployment kit | Done locally (real host / real SMTP / real HTTPS NOT VERIFIED) | `opskit/bin/check` (non-quick) passes incl. selftest, 2026-10-04 |
| 3 | Backups & restore | Planned (task file ready, awaiting owner approval) | — |
| 4 | Monitoring & alerts via shared ops-hub | Not started | — |
| 5 | Safe upgrades | Not started | — |
| 6 | Channel runbooks & checkers | Not started | — |
| 7 | Industry starter packs bn + en | Not started | — |
| 8 | aibot | Not started | — |
| 9 | Monthly care report | Not started | — |
| 10 | Own CE images incl. arm64 | Not started | — |
| 11 | Field readiness | Not started | — |

## Task log
<!-- Newest first. For each task: date, task, files changed, how to verify manually, notes. -->
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
- White-label (Option 3, default off) and which add-ons to build: see `docs/ADDONS.md`. Nothing is built for these yet.

## Known issues
<!-- Bugs or gaps found outside current task scope. -->

## Phase verification reports
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

