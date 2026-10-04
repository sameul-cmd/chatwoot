---
name: verify-phase
description: Check the current phase against spec acceptance criteria
---

# Verify phase

1. Read the current phase acceptance criteria in `docs/SPEC.md` (Section 17) and `docs/tasks/phase-N.md`.
2. Run `opskit/bin/check` and `opskit/bin/opskit selftest`.
3. For each acceptance criterion: state PASS / FAIL / NOT VERIFIED with evidence (test name, command output, or manual steps).
4. Compare implemented features against every SPEC section referenced by the phase. List anything missing or implemented differently.
5. Check for leftovers: TODOs, missing set -e, unquoted variables, eval, hardcoded domains/IPs/tokens, message text or PII in logs, non-CE image tags, enterprise/ changes, bot answering without KB snippets, docker commands without -p, upstream files changed without a ledger entry.
6. Write the report into `docs/PROGRESS.md` under the phase. Don't fix anything yet; ask the user which issues to fix.
