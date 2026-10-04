# Assumptions

Decisions the agent made where `docs/SPEC.md` was silent or ambiguous. The owner reviews these regularly.

| # | Date | Phase/Task | Spec section | Assumption | Approved? |
|---|---|---|---|---|---|
| A-001 | 2026-10-04 | Phase 8 | SPEC 13.6 | "Effort max" is sent as `reasoning_effort` by default; endpoints that only know low/medium/high get `max`→`high` via configurable map, and an unsupported param is dropped with a warning instead of failing a reply. Default effort `medium` for chat latency. | pending |
| A-002 | 2026-10-04 | 1.4 | SPEC 6 | `opskit client validate` uses a small Python helper (`lib/schema_check.py`, jsonschema + pyyaml) because Bash cannot validate JSON Schema; `doctor` checks those packages. | pending |
| A-003 | 2026-10-04 | 1.5 | SPEC 12 | JSON Schema cannot apply defaults, so a Bangla item without `review_required` is treated as `true` by `pack apply` (Phase 7), not by the schema. | pending |
| A-004 | 2026-10-04 | 1.1 | SPEC 4 | Dev tools installed in the cloud sandbox with owner approval: shellcheck, bats, gettext-base, rclone, uv + Python 3.12, jsonschema, pyyaml. aibot runtime deps in Phase 1: fastapi, uvicorn, httpx, pydantic, pyyaml (rank-bm25 is added in Phase 8). | approved 2026-10-04 |
| A-005 | 2026-10-04 | 2.6 | SPEC 7.1 | `client deploy` supports only `deploy.target: local` now; remote deploys (and real-host bootstrap runs) are written/tested with a fake SSH only and verified in Phase 11 on a real VPS. | pending |
| A-006 | 2026-10-04 | 2.2, 2.9 | SPEC 7.1, ADR-008 | Caddy runs as a container in every client stack (one client = one stack = one host in V1), so `host bootstrap` does NOT install Caddy on the host (it would clash on ports 80/443). Differs from SPEC 7.1 wording "Caddy installed by host bootstrap". | pending |
| A-007 | 2026-10-04 | 2.3 | SPEC 7.3 | Empty SMTP login variables are omitted from `.env` because Chatwoot attempts SMTP login when `SMTP_USERNAME` is set but empty (verified). | approved (default) |
| A-008 | 2026-10-04 | 2.4 | SPEC 7.4 | Generated Super Admin password = random hex + `-Aa1!` to satisfy Chatwoot's complexity rules (upper, lower, digit, special; verified). | approved (default) |
| A-009 | 2026-10-04 | 2.1 | SPEC 15 | The aibot image is built on the target machine by `deploy` (`opskit-aibot:<id>`) until Phase 10 publishes images to GHCR. `OPSKIT_BUILD_CA` adds a CA bundle for restricted networks. | pending |
| A-010 | 2026-10-04 | 3.6 | SPEC 8 | `restore --target new-host` is deferred to Phase 11 (a new host is a remote deploy); only `--target staging` is built. | pending |
| A-011 | 2026-10-04 | 3.7 | SPEC 8 | The automated restore test uses the live `secrets.env` already on the host (no private key available to automation); the escrow is proven separately with `--identity` (manual, e.g. quarterly). | pending |
| A-012 | 2026-10-04 | 3.3 | SPEC 8 | Backup manifest records conversation count, newest conversation id and the newest attachment's checksum (counts/ids/checksums only, no message text) so the restore test can compare. | approved (default) |
| A-013 | 2026-10-04 | 3.10 | CLAUDE.md API rule | API calls through the public URL send the header as `api-access-token` (the underscore form is dropped by Caddy; verified). | approved |
