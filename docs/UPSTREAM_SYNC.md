# Upstream sync (manual, optional) — WSL

1. Read release notes for every version between the pinned tag and the target (migrations, env changes, breaking changes).
2. `git fetch upstream --tags` → `git switch main` → `git switch -c sync/<tag>` → `git merge <tag>`.
3. Resolve conflicts: upstream wins in upstream files; re-apply ledger patches; never touch `enterprise/`.
4. Re-verify Phase 0 facts the kit/bot rely on (env keys incl. `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`, compose services, agent-bot payloads + `X-Chatwoot-Signature`, first-run onboarding flag, API endpoints, CE image method; see `docs/EXPLORATION_REPORT.md`); update ADRs/ASSUMPTIONS.
5. `opskit/bin/check`, `opskit/bin/opskit selftest`; CI builds a test image.
6. Staging upgrade of the demo client; then merge to `main`, update the pin table and PROGRESS.
If anything fails: stay on the old tag and log it.

Note: this fork currently develops on the branch named in `docs/PROGRESS.md` (Claude cloud session); use that branch wherever these steps say `main` until a `main` is set.
