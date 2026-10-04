# Assumptions

Decisions the agent made where `docs/SPEC.md` was silent or ambiguous. The owner reviews these regularly.

| # | Date | Phase/Task | Spec section | Assumption | Approved? |
|---|---|---|---|---|---|
| A-001 | 2026-10-04 | Phase 8 | SPEC 13.6 | "Effort max" is sent as `reasoning_effort` by default; endpoints that only know low/medium/high get `max`→`high` via configurable map, and an unsupported param is dropped with a warning instead of failing a reply. Default effort `medium` for chat latency. | pending |
