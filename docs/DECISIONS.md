# Architecture Decision Records

### ADR-001: Fork Chatwoot; clients run CE images (later our own)
- **Status:** accepted — **Context:** Owner wants an enhanced repo; arm64 needs own builds; bot lives in the fork. **Decision:** Fork, pin release tags, fetch-only upstream, upstream CI disabled. **Consequences:** Release syncs + image rebuilds.

### ADR-002: Community Edition only
- **Status:** accepted — **Decision:** `-ce` images; never touch `enterprise/`; no license keys; branding stays. **Consequences:** No Captain/SLA/audit logs; our bot replaces Captain.

### ADR-003: One install per client; shared-accounts mode reserved (V2)
- **Status:** accepted — **Decision:** `install.mode: dedicated`; schema keeps `shared_accounts` and `accounts[]`. **Consequences:** V2 can add shared installs without restructuring.

### ADR-004: aibot as a dedicated Python service per client stack
- **Status:** accepted — **Context:** Owner chose a dedicated service; needs low latency, isolation, tests. **Decision:** FastAPI container in the client compose network via Chatwoot Agent Bot webhooks. **Alternatives:** Activepieces flow; Chatwoot enterprise Captain. **Consequences:** Must maintain KB tooling and eval.

### ADR-005: BM25 retrieval + constrained LLM + handoff-first policy
- **Status:** accepted — **Decision:** Answer only from KB snippets with JSON confidence; hand off otherwise. **Consequences:** Fewer wrong answers; KB quality drives results; embeddings may come later (ADR then).

### ADR-006: Shared ops-hub with the Activepieces project
- **Status:** accepted — **Decision:** Same alert-router/report flows and Uptime Kuma; direct Telegram fallback. **Consequences:** Cross-project dependency; documented fallback.

### ADR-007: Bash opskit mirroring the Activepieces kit
- **Status:** accepted — **Decision:** Same structure/conventions (client.yaml, schema, templates, agent scripts, bats). **Consequences:** Skills transfer between projects; possible future shared library (ADR then).

### ADR-008: Caddy instead of the docs' Nginx + certbot
- **Status:** accepted — **Decision:** Caddy for automatic HTTPS + WebSockets, consistent with the Activepieces kit. **Consequences:** Verify ActionCable/websocket headers in Phase 2.

### ADR-009: Upgrades through staging with rollback, in client off-hours
- **Status:** accepted.

### ADR-011: BYOK OpenAI-compatible LLM adapter with model picker and effort control
- **Status:** accepted (owner, 4 Oct 2026) — **Decision:** every LLM call in aibot (and any opskit LLM use) goes through one OpenAI-compatible adapter (`base_url`, `api_key_env`, `model`, `effort` none..max). Model picker = list `/models` from the endpoint and choose (CLI `opskit llm models`; later UI if V2 portal). **Consequences:** no provider SDK lock-in; "max" effort mapping is endpoint-specific (ASSUMPTIONS A-001); tests use the fake LLM only.

### ADR-012: Allow private-network webhooks on client stacks
- **Status:** accepted (Phase 0 finding) — **Decision:** client `.env` sets `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` so Chatwoot can call `http://aibot:8000` inside the compose network; aibot also verifies `X-Chatwoot-Signature`. **Consequences:** weaker SSRF guard for that install; only dedicated stacks; revisit if shared multi-account mode (V2) is built.

### ADR-013: GitHub Actions stays disabled in the fork
- **Status:** accepted (owner, 2026-10-04) — **Decision:** no CI on GitHub for now; `opskit/bin/check` is the gate, run locally. **Consequences:** `opskit-ci.yml` is dormant; Phase 10 (multi-arch image build) needs Actions, so revisit then (disable Chatwoot's workflows per-file, or an approved ledger patch removing them).

### ADR-010: Two IDE packages share docs
- **Status:** accepted — Kilo: `AGENTS.fork.md` + `kilo.jsonc` + `.kilo/`. Factory: `.factory/AGENTS.md` + `.factory/skills/`. Claude Code (this fork): `.claude/CLAUDE.md` + `.claude/skills/`.
