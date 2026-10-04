# Phase 5 — Safe upgrades (Improvement 6)

Spec: SPEC Section 10, Section 17 (Phase 5), Section 3 rule 10, ADR-009, `.claude/CLAUDE.md` "Reliability rules", `docs/UPSTREAM_SYNC.md`.
**Accept (from SPEC):** upgrading a demo client from the previous to the pinned release passes staging and production smoke tests; an injected smoke failure triggers rollback with data intact. Plus (Phase 5 text): fork sync rehearsal.

## What this phase is, in plain words
A single command that moves a client from one Chatwoot version to another **safely**: it reads what changed, backs up, rehearses the upgrade on a copy made from the real backup, tests the copy, then (only in the client's quiet hours) upgrades the real system, tests it, and automatically goes back to the old version if anything fails. Nothing ever upgrades by itself; you start it.

## Facts this phase relies on (checked in the fork on 2026-10-04)
- Releases: v4.17.0, v4.17.1, v4.18.0 (pinned). CE images `chatwoot/chatwoot:v4.17.1-ce` and `v4.18.0-ce` both exist on Docker Hub.
- v4.17.1 -> v4.18.0: 123 commits, **3 new database migrations** (`backfill_missing_ai_assignee_types`, `add_geo_location_to_audits`, `add_provider_name_to_social_channels`), 1 new optional env key (`SLACK_SIGNING_SECRET`), no change to the official production compose. A good real test: after the upgrade the database has changed, so a rollback must restore the database, not only the image.
- Phase 2: `deploy` runs `db:chatwoot_prepare`; Phase 3: backups are encrypted and `restore_to_staging` builds a copy in `<id>-staging`; the restore test proves login, newest conversation and an attachment.
- GitHub release pages are not reachable from the sandbox, so "release notes" here come from the fork's own git history (commit list, migration files, env changes). You should still read the official release notes yourself before a real client upgrade.

## Open questions for the owner (plain words; defaults in bold)
1. **When may a real client be upgraded?** **Default:** only in an "off-hours window" of 01:00-05:00 in the client's time zone (changeable per client). The command refuses to upgrade a live client outside it, unless it is an outage fix and you add a special flag.
2. **What if the upgrade fails halfway?** **Default:** it goes back by itself: old version again and, if the database was changed, the database from the backup taken minutes before. The catch: customer messages that arrived in those few minutes could be lost (WhatsApp retries messages; website chat might not). You are told immediately on Telegram. Alternative: never go back by itself, only alert you. Which do you prefer?
3. **Release notes.** **Default:** the command shows what changed from the fork's git history (number of changes, database migrations, new settings) plus a checklist, and you read the official release page yourself. OK?
4. **Who starts upgrades?** **Default:** only you, by hand, per client. Nothing upgrades automatically, ever.
5. **Test the new version first on a copy.** **Default:** yes, always, built from the latest real backup, including a check that the database changes (migrations) work on real data. A real upgrade is refused if that rehearsal did not pass in the last 24 hours.
6. **The acceptance demo.** **Default:** deploy a demo client on v4.17.1, add a conversation with a photo, upgrade it to v4.18.0 (3 migrations), then repeat with a deliberately failing test to prove the automatic rollback keeps the data. This needs downloading the older ~1 GB image once (disk has room).
7. **The AI bot is not built yet (Phase 8).** **Default:** the "bot answers on the test copy" check shows "skipped (bot not built)" until Phase 8 and then becomes real. OK?

## Tasks

### [x] 5.1 — Settings and history format
- **Goal:** `client.yaml`: `upgrade_window {start,end}` (default 01:00-05:00) and typed `support`; `clients/<id>/upgrade/history.jsonl` (one JSON line per attempt: from, to, started, finished, result, backup used, rollback done?, migrations count). No message text.
- **Tests:** bats: schema field errors; history lines valid JSON

### [x] 5.2 — Release information (`opskit upgrade <id> --to <tag> --info`)
- **Goal:** from local git tags: number of changes, new/changed database migrations, `.env.example` keys added/removed, compose diff, plus the checklist; clear hint to fetch missing tags (`git fetch upstream tag <tag>`).
- **Tests:** bats on a tiny fixture git repo (known diffs); hostile tag names rejected

### [x] 5.3 — Checklist runbook (`docs/runbooks/upgrade-checklist.md`)
- **Goal:** plain-language before/during/after list (read release notes, client informed, backup fresh, window, who is on call, rollback plan, what to tell the client).

### [x] 5.4 — Preflight checks
- **Goal:** target is a CE tag (`-ce`), newer than the current one, image exists in the registry, current stack healthy, a backup < 24 h old exists or is made now, enough disk (2x the backup size), inside the off-hours window (for production), staging rehearsal passed < 24 h ago (for production).
- **Tests:** bats with fake docker/registry: every refusal has a clear message

### [x] 5.5 — Staging rehearsal on the new image
- **Goal:** `opskit upgrade <id> --to <tag> --stage`: latest backup -> `<id>-staging` running the NEW image -> `db:chatwoot_prepare` (time + migrations applied are recorded) -> smoke tests -> result file `upgrade/staging-<tag>.json` -> staging deleted.
- **Needs approval:** touches upgrade/restore logic

### [x] 5.6 — Smoke test suite (`lib/smoke.sh`)
- **Goal:** one suite used for staging and production: login, health route, widget script, websocket, background job + email, **widget message round trip** (customer message through an API inbox creates a conversation), conversation count and newest id unchanged since the backup, newest attachment checksum, bot health, bot reply (skipped until Phase 8). `OPSKIT_UPGRADE_FAIL_SMOKE=staging|production` injects a failure for tests.
- **Tests:** bats for result formatting and failure injection; live in 5.10

### [x] 5.7 — Production upgrade (`opskit upgrade <id> --to <tag> --apply --yes`)
- **Goal:** typed client id + `--yes`; window check; fresh backup; record schema version; set the new tag in `client.yaml`; render; pull; `db:chatwoot_prepare`; start; wait healthy; smoke tests; history line; Telegram message (started / succeeded / rolled back).
- **Needs approval:** touches a live client's inbox (uses the safety rules: backup -> staging -> smoke -> promote -> rollback)

### [x] 5.8 — Automatic rollback
- **Goal:** on any failure after the pre-upgrade backup: stop services, put the old tag back; if migrations changed the database restore it from the pre-upgrade backup (and uploads), start, run smoke tests on the old version, verify conversation count/newest id/attachment equal the backup, alert you critically. If rollback itself fails: stop, critical alert with exact manual steps (never loop).
- **Tests:** bats (decision logic: image-only vs database restore); live in 5.10

### [x] 5.9 — Fork sync rehearsal
- **Goal:** `opskit/bin/sync-rehearsal <old-tag> <new-tag>`: in a throw-away git worktree build "old tag + our kit", merge the new tag, report conflicts in our paths (should be none) and run the paths check; never touches the real branch; deletes the worktree. Proves `docs/UPSTREAM_SYNC.md` works before the first real sync.
- **Tests:** bats on a fixture repo; live run for v4.17.1 -> v4.18.0

### [x] 5.10 — Selftest v4 (acceptance)
- **Goal:** selftest scenario B: deploy on v4.17.1-ce, seed a conversation + photo, upgrade to v4.18.0-ce (staging + production smoke pass, data intact, tag changed, history written); scenario C: same with an injected production smoke failure -> automatic rollback to v4.17.1 with the data intact.
- **Acceptance:** both scenarios pass in `opskit selftest`

### [x] 5.11 — Docs, verification
- **Goal:** `docs/runbooks/upgrade.md` (plain language), update PROGRESS/ASSUMPTIONS/ENVIRONMENT, `/verify-phase`, security review (no secrets in history/alerts, window enforcement, no accidental production overwrite).
