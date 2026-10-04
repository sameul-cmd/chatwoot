# Assumptions

Decisions the agent made where `docs/SPEC.md` was silent or ambiguous. The owner reviews these regularly.

| # | Date | Phase/Task | Spec section | Assumption | Approved? |
|---|---|---|---|---|---|
| A-001 | 2026-10-04 | Phase 8 | SPEC 13.6 | "Effort max" is sent as `reasoning_effort` by default; endpoints that only know low/medium/high get `max`→`high` via configurable map, and an unsupported param is dropped with a warning instead of failing a reply. Default effort `medium` for chat latency. | pending |
| A-002 | 2026-10-04 | 1.4 | SPEC 6 | `opskit client validate` uses a small Python helper (`lib/schema_check.py`, jsonschema + pyyaml) because Bash cannot validate JSON Schema; `doctor` checks those packages. | pending |
| A-003 | 2026-10-04 | 1.5 | SPEC 12 | JSON Schema cannot apply defaults, so a Bangla item without `review_required` is treated as `true` by `pack apply` (Phase 7), not by the schema. | pending |
| A-004 | 2026-10-04 | 1.1 | SPEC 4 | Dev tools installed in the cloud sandbox with owner approval: shellcheck, bats, gettext-base, rclone, uv + Python 3.12, jsonschema, pyyaml. aibot runtime deps in Phase 1: fastapi, uvicorn, httpx, pydantic, pyyaml (rank-bm25 is added in Phase 8). | approved 2026-10-04 |
