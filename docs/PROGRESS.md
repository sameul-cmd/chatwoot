# Progress

## Current status
- **Current phase:** Phase 1 — Opskit foundation (tasks 1.1-1.10 done, verification pending)
- **Current task:** run `/verify-phase`, enable the `opskit-ci` workflow on GitHub, then `/start-phase` for Phase 2
- **Last updated:** 2026-10-04

## Phases
| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | Fork, set up & explore Chatwoot | Done on cloud sandbox; owner-account tests (Telegram, email, WhatsApp, Meta) and Bengali UI check pending on owner device | cloud-verified 2026-10-04 |
| 1 | Opskit foundation | Implemented; awaiting /verify-phase and first GitHub CI run | local `opskit/bin/check` passes (18 bats, 17 pytest, shellcheck) |
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
- Repo = upstream `chatwoot/chatwoot` at v4.18.0 + our kit. Developed with Claude Code in a cloud session; branch `claude/wizardly-babbage-ui2rpa`.
- Agent rules: `.claude/CLAUDE.md` (force-added; upstream .gitignore ignores `.claude/`). Skills: `.claude/skills/`.
- Anything needing the owner's accounts (Telegram, WhatsApp, email, VPS) is coded here and proven later on the owner's device; see `docs/HANDOVER.md` (created as we go).

## Phase 0 - owner-side items (do on your own device later)
- Telegram, email (IMAP/SMTP), WhatsApp Cloud API test number, Facebook/Instagram, mobile app via ngrok, Bengali UI check.

## Known issues
<!-- Bugs or gaps found outside current task scope. -->

## Phase verification reports
<!-- Output of /verify-phase goes here. -->
