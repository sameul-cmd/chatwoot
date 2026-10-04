# Progress

## Current status
- **Current phase:** Phase 1 — Opskit foundation (tasks 1.1-1.10 done, verification pending)
- **Current task:** `/start-phase` for Phase 2 (Phase 1 verified; GitHub Actions deliberately stays OFF, see Setup notes)
- **Last updated:** 2026-10-04

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Chatwoot | Done on cloud sandbox; owner-account tests (Telegram, email, WhatsApp, Meta) and Bengali UI check pending on owner device | cloud-verified 2026-10-04 |
| 1 | Opskit foundation | Done (verified locally; GitHub CI intentionally not enabled) | local `opskit/bin/check` passes (18 bats, 17 pytest, shellcheck) |
| 2 | Client deployment kit | Not started | — |
| 3 | Backups & restore | Not started | — |
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

