# Phase 1 — Opskit foundation

Spec: SPEC Section 17 (Phase 1), Sections 3, 6, 13.6, 16. Rules: `.claude/CLAUDE.md`.
**Accept (from SPEC):** `opskit/bin/check` passes locally and in CI; invalid configs fail with field messages; `git diff v4.18.0 --stat` lists only our paths.

## Open questions for the owner
1. **Dev tools to install in the sandbox** (rules say ask before new dependencies): `shellcheck`, `bats`, `gettext-base` (envsubst), `rclone`, Python 3.12 via `uv`, and Python packages `fastapi httpx pydantic rank-bm25 pytest ruff mypy jsonschema`. Default: install them (dev-only, none ship to clients except the aibot runtime packages). OK?
2. **Phase 1 vs. owner device:** nothing in Phase 1 needs your accounts. Default: do it all here.
3. **Python version:** this sandbox has 3.11, the spec says 3.12. Default: use `uv` to get 3.12 so tests match production.
(If no answer, the defaults are used and logged in `docs/ASSUMPTIONS.md`.)

## Tasks

### [x] 1.1 — Tooling check and install
- **Goal:** the sandbox (and later the owner's device) has everything `check` needs.
- **Spec refs:** 4, 16
- **Files likely touched:** `opskit/bin/opskit` (doctor), `docs/ENVIRONMENT.md`
- **Acceptance checks:** `opskit doctor` lists each tool with version or a clear install hint
- **Tests required:** bats test: doctor exits non-zero and names a missing tool (simulated PATH)
- **Manual verification:** run `opskit/bin/opskit doctor`

### [x] 1.2 — Directory skeleton and ignore rules
- **Goal:** create `opskit/{bin,lib,schema,templates,agent,packs,hub,tests}`, git-ignored `clients/` `hosts/` `keys/` (already partly present), `aibot/` layout.
- **Files likely touched:** `opskit/**`, `aibot/**`, `opskit/.gitignore`
- **Acceptance checks:** tree matches TECH_ARCHITECTURE Section 2; `git diff v4.18.0 --stat` shows only our paths
- **Tests required:** bats test that fails if a tracked file outside our paths changed vs the pinned tag (path allow-list)

### [x] 1.3 — Bash library basics (`lib/`)
- **Goal:** `log.sh` (levels, never prints secrets), `confirm.sh` (`--yes`, typed client id), `validate.sh` (required env/tools), `die`, `set -euo pipefail` conventions.
- **Spec refs:** 0.9, 3.6
- **Acceptance checks:** shellcheck-clean; secret-looking values are masked in logs
- **Tests required:** bats for masking, confirm refusal without `--yes`, empty-secret abort helper

### [x] 1.4 — `client.yaml` JSON schema + validator
- **Goal:** `schema/client.schema.json` per SPEC 6; `opskit client validate <file>` prints field-path messages. `install.mode: dedicated` accepted, `shared_accounts` rejected with the text "V2". Includes the BYOK `bot.llm` block (`base_url`, `api_key_env`, `model`, `effort` none|low|medium|high|max, `effort_param`, `max_output_tokens`) per ADR-011.
- **Spec refs:** 6, 13.6, ADR-011
- **Tests required:** valid fixture passes; missing/typed-wrong fields fail with the field name; `shared_accounts` -> "V2"; bad `effort` value fails

### [x] 1.5 — `bot.yaml` schema + `pack.schema.json`
- **Goal:** schemas for per-client bot config (min_confidence 0.7, max_bot_turns 3, audit_days 30, handoff keywords bn/en, llm block) and pack files (bn/en text, `review_required`).
- **Tests required:** valid/invalid fixtures; schema documents `review_required` (default true); enforcement of "unapproved = true" is applied by `pack apply` in Phase 7 (ASSUMPTIONS A-003)

### [x] 1.6 — `opskit` CLI skeleton
- **Goal:** `opskit/bin/opskit` with subcommands wired but stubbed: `doctor`, `client validate|new`, `selftest` (prints "not available before Phase 2"), `llm models|effort` (stub, real in Phase 8). `--help` for each.
- **Tests required:** bats: unknown command exits 2 with usage; `--help` works

### [x] 1.7 — aibot skeleton (Python 3.12, FastAPI)
- **Goal:** `aibot/pyproject.toml`, `src/aibot/{app.py,config.py}`, `/health` endpoint, `config.py` loading env + `bot.yaml` with pydantic including the `llm` settings and the rule "client mode requires `AIBOT_LLM_TIER_PAID=true` or owner key" (SPEC 13.6). No LLM calls yet.
- **Spec refs:** 13, 13.6, 4
- **Tests required:** pytest: `/health` returns ok; config rejects client mode without paid flag; effort enum validated; no key value ever appears in `repr(config)`
- **Manual verification:** `uv run uvicorn aibot.app:app` then `curl :8000/health`

### [x] 1.8 — `opskit/bin/check`
- **Goal:** runs shellcheck on all `.sh` and `bin/*`, bats, aibot ruff + mypy + pytest; `--quick` skips docker integration. Non-zero on any failure, readable summary.
- **Acceptance checks:** passes on a clean tree; deliberately breaking a script makes it fail

### [x] 1.9 — CI workflow `opskit-ci.yml`
- **Goal:** GitHub Actions workflow that runs `opskit/bin/check --quick` on push/PR to our paths only (`opskit/**`, `aibot/**`, `docs/**`, workflow file). Written here; **you enable only this workflow on GitHub** (instructions given in chat).
- **Files likely touched:** `.github/workflows/opskit-ci.yml` (new file, our path)
- **Acceptance checks:** YAML valid (actionlint if available); path filters present; runs green on GitHub after you enable it

### [x] 1.10 — Ledger, sync doc and wrap-up
- **Goal:** complete `docs/UPSTREAM_CHANGES.md` (empty ledger = no upstream edits), `docs/UPSTREAM_SYNC.md` checked against reality, add `docs/HANDOVER.md` (what to run on the owner's device), update PROGRESS, run `/verify-phase`.
- **Acceptance checks:** `git diff v4.18.0 --stat` lists only our paths; verify-phase report added to PROGRESS
