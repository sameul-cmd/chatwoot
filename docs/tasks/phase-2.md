# Phase 2 — Client deployment kit (Improvement 1)

Spec: SPEC Section 7, Section 17 (Phase 2), Section 3 (rules 3, 4, 6), ADR-008 (Caddy), ADR-012 (private-network webhooks).
**Accept (from SPEC):** rendered stack uses the CE tag, memory limits, only Caddy exposed, `ENABLE_ACCOUNT_SIGNUP=false`; secret generation aborts on empty values (bats); `db:chatwoot_prepare` runs on first deploy and on upgrades; test email sends; re-running deploy is idempotent; `client.yaml` accepts `install.mode: dedicated` and rejects `shared_accounts` with "V2". `opskit selftest` v1: deploy -> health -> widget loads -> teardown.

## Phase 0 facts this phase relies on (verified on v4.18.0-ce)
- Image `chatwoot/chatwoot:v4.18.0-ce`; services rails, sidekiq, postgres (`pgvector/pgvector:pg16`), redis; health `GET /api`.
- Official compose publishes 3000/5432/6379 on 127.0.0.1: ours must publish nothing except Caddy.
- `db:chatwoot_prepare` sets a Redis flag that sends every page to the public `/installation/onboarding` form until completed: the deploy must finish onboarding itself right away (create Super Admin + account by `rails runner`, then clear the flag).
- The bot needs `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` in the stack `.env` (ADR-012).
- The official compose also starts a useless `base` service; ours must not.

## Open questions for the owner (answers needed before coding: secrets are involved)
1. **Secrets and the Super Admin password.** Default: generated with `openssl rand`, written to `opskit/clients/<id>/.env` (mode 600, git-ignored) and a one-time `admin-credentials.txt` (mode 600) shown once in the terminal; you save it into your password manager and delete the file. Never printed to logs. OK?
2. **Local practice without a real domain/email.** Default: use `localhost` with Caddy's internal HTTPS and a local mail catcher (Mailpit) to prove "test email sends"; real SMTP is configured later on your device. OK?
3. **Real servers.** Default: `opskit host bootstrap` and remote deploy are written and tested only with a fake SSH runner here, marked NOT VERIFIED on a real VPS until Phase 11 / your device. No real host is touched in this phase. OK?
4. **aibot in the stack.** Default: the compose includes the `aibot` container (built from a new `aibot/Dockerfile`), internal network only, with `/health` check; it does no answering until Phase 8. OK?
5. **Caddy in Docker vs on the host.** Default: Caddy runs as a container in the client stack for local practice; on real hosts the spec (Section 7) says Caddy is installed by `host bootstrap`. Both rendered from the same template. OK?

## Tasks

### [x] 2.1 — `aibot/Dockerfile` and image build check
- **Goal:** small Python 3.12 image running `uvicorn` with `/health`; non-root user.
- **Files:** `aibot/Dockerfile`, `aibot/.dockerignore`
- **Acceptance:** `docker build` ok; container answers `/health`
- **Tests:** bats (docker-gated, skipped under `--quick`)

### [x] 2.2 — Templates: compose, env, Caddy
- **Goal:** `opskit/templates/{compose.yml.tmpl,env.tmpl,Caddyfile.tmpl,client.yaml.tmpl}`; services rails, sidekiq, postgres, redis, aibot (+ optional Caddy/Mailpit profiles); named volumes `<id>_postgres/_redis/_storage/_aibot`; memory limits from `sizing` (defaults TECH_ARCHITECTURE section 6); healthchecks; only Caddy publishes ports; no `base` service; V2 optional services reserved via compose profiles.
- **Spec refs:** 7.2, 7.3, TECH 3, 6, 7

### [x] 2.3 — Renderer (`lib/render.sh`) with unresolved-variable guard
- **Goal:** envsubst-based, fails on any unresolved `${...}`; reads `client.yaml` via yq.
- **Tests:** bats: CE tag present, memory limits present, exactly one service with `ports`, `ENABLE_ACCOUNT_SIGNUP=false`, `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`, missing variable fails

### [x] 2.4 — Secret generation (`lib/secrets.sh`)  [needs your approval: secrets]
- **Goal:** generate `SECRET_KEY_BASE`, Postgres/Redis passwords, aibot webhook secret, Super Admin password; abort if any is empty; never overwrite existing values (idempotent); `.env` mode 600; nothing in logs.
- **Tests:** bats: empty value aborts; second run keeps existing secrets; file mode 600; no secret in captured output

### [x] 2.5 — `opskit client new|render`
- **Goal:** `client new <id>` scaffolds `opskit/clients/<id>/client.yaml` and validates it; `client render <id>` writes compose/.env/Caddyfile into `opskit/clients/<id>/stack/` (git-ignored).
- **Tests:** bats: `shared_accounts` rejected with "V2"; invalid id rejected; idempotent re-render produces identical files

### [x] 2.6 — `opskit client deploy <id>` (local Docker target)
- **Goal:** `docker compose -p <id>`: pull/build -> run `db:chatwoot_prepare` as a one-off container -> up -> wait for `/api` healthy (timeout, clear error) -> complete onboarding (Super Admin + account via `rails runner`, clear the Redis flag) -> save credentials once.
- **Tests:** integration (docker-gated): fresh deploy healthy; re-run is a no-op (no new admin, same secrets, containers unchanged)

### [x] 2.7 — Post-deploy checks
- **Goal:** login page reachable; widget script `/packs/js/sdk.js` loads; a Sidekiq test job runs; outgoing test email arrives in Mailpit; HTTPS and WebSocket (ActionCable) via Caddy. Output PASS/FAIL table.
- **Spec refs:** 7.5

### [x] 2.8 — `pause | resume | offboard`
- **Goal:** pause/resume = compose stop/start; offboard = destructive: needs `--yes` and typed client id; keeps backups; never touches other clients.
- **Tests:** bats with the confirm helpers (refuse without `--yes`, wrong id aborts)

### [x] 2.9 — `opskit host bootstrap <host>` (fake-runner tested only)
- **Goal:** idempotent script set run over SSH: Docker, ufw 22/80/443, unattended-upgrades, 2 GB swap, Caddy, SSH-hardening check; `--dry-run` prints steps. Remote actions only through `lib/ssh.sh`.
- **Tests:** bats with a fake `ssh` verifying commands and idempotent re-run; **NOT VERIFIED on a real host**

### [x] 2.10 — `opskit selftest` v1
- **Goal:** local demo client: deploy -> post-deploy checks -> widget loads -> teardown (always cleans up, even on failure). Wired into `opskit/bin/check` (non-quick only).
- **Acceptance:** `opskit/bin/opskit selftest` passes end to end here

### [x] 2.11 — Runbook, docs, verification
- **Goal:** `docs/runbooks/deploy.md` (plain-language steps for a new client), update PROGRESS/ASSUMPTIONS/ENVIRONMENT, run `/verify-phase` and the `security-review` skill (secrets, ports, file modes).
- **Acceptance:** verify-phase report in PROGRESS with PASS/FAIL/NOT VERIFIED per criterion
