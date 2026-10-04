# Upstream pin & patch ledger

| Field | Value |
|---|---|
| Upstream | https://github.com/chatwoot/chatwoot |
| Pinned release tag | v4.18.0 |
| Tag SHA | 9f920b549 (merge of release/4.18.0) |
| Pinned on | 2026-10-04 |

## Patch ledger (upstream files — approval required)
| # | Date | Upstream file(s) | Why | Change summary | Re-apply steps | Test | Status |
|---|---|---|---|---|---|---|---|
| 1 | 2026-10-04 | `README.md` | An AI or person opening the repo link only sees Chatwoot's front page and cannot find the takeover guide | Prepends a 3-line fork notice pointing to docs/NEXT.md and docs/ADOPT.md | Put the notice back at the very top of `README.md` after a sync (copy it from the previous merge) | `opskit/tests/pack.bats` is unrelated; see `opskit/tests/opskit.bats` test "fork notices" | active (owner approved 2026-10-04) |
| 2 | 2026-10-04 | `AGENTS.md` | Tools that read the root AGENTS.md follow Chatwoot's guidelines and never learn about our project | Prepends a 3-line fork notice saying the file applies only to Chatwoot's own files and pointing to docs/NEXT.md and docs/ADOPT.md | Put the notice back at the very top of `AGENTS.md` after a sync | `opskit/tests/opskit.bats` test "fork notices" | active (owner approved 2026-10-04) |
