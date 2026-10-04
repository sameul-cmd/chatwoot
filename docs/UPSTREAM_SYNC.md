# Upstream sync (manual, optional) — WSL

1. Read release notes for every version between the pinned tag and the target (migrations, env changes, breaking changes).
2. `git fetch upstream --tags` → `git switch main` → `git switch -c sync/<tag>` → `git merge <tag>`.
3. Resolve conflicts: upstream wins in upstream files; re-apply ledger patches; never touch `enterprise/`.
4. Re-verify Phase 0 facts the kit/bot rely on (env keys, compose services, agent-bot payloads, API endpoints, CE image method); update ADRs/ASSUMPTIONS.
5. `opskit/bin/check`, `opskit/bin/opskit selftest`; CI builds a test image.
6. Staging upgrade of the demo client; then merge to `main`, update the pin table and PROGRESS.
If anything fails: stay on the old tag and log it.
