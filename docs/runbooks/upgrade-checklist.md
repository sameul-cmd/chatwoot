# Upgrade checklist (print or copy per upgrade)

Use this for every real client upgrade. Nothing here is automatic: you start the upgrade yourself.

## Before (the day before if possible)
- [ ] Read the official release notes for every version between the client's current one and the target (GitHub releases page of chatwoot/chatwoot). Look for: breaking changes, removed features, new required settings.
- [ ] `opskit upgrade <id> --to <tag> --info` - read the number of changes, **database migrations**, new/removed settings, and whether the official compose changed. If the compose changed, stop and review our templates first.
- [ ] Tell the client when it will happen (a few minutes of downtime in their quiet hours) and what to do if something looks wrong.
- [ ] `opskit upgrade <id> --to <tag> --stage` - rehearsal on a copy made from the latest backup. It must say PASSED. (A real upgrade is refused without a passing rehearsal from the last 24 hours.)
- [ ] Check the Telegram alerts are working (`opskit alerts test <id>`) and that you can be reached during the upgrade.
- [ ] Check there is disk space and a recent healthy backup (`opskit backup list <id>`); the real upgrade takes a fresh one anyway.

## During (in the client's off-hours window, default 01:00-05:00 their time)
- [ ] `opskit upgrade <id> --to <tag> --apply --yes` (type the client name when asked). It: takes a fresh backup, upgrades, runs the tests, and goes back by itself if anything fails.
- [ ] Watch the table of checks. Every row should say PASS (the bot row says "skipped" until the bot exists).
- [ ] You get Telegram messages: started, then finished OR rolled back.

## After
- [ ] Open the client's Chatwoot in a browser: log in, open a recent conversation, open an attachment, send a test reply.
- [ ] `opskit monitor status <id>` - everything ok.
- [ ] Update `docs/UPSTREAM_CHANGES.md` / PROGRESS if this changes the pinned release for new clients.
- [ ] Tell the client it is done. Keep the pre-upgrade backup for at least 14 days (the normal retention does this).

## If it was rolled back
You are told on Telegram. The old version is running again with the pre-upgrade data (checked automatically). Customer messages that arrived during the few minutes of the attempt may be missing (WhatsApp usually retries). Then: read `opskit/clients/<id>/upgrade/history.jsonl`, look at what failed, fix, and try the rehearsal again. If the rollback itself failed you get a double-red alert: restore manually from the pre-upgrade backup (`docs/runbooks/restore.md`).

## Outage fix (not a normal upgrade)
Only for a real outage: `--outage-fix` lets the command run outside the quiet window. Say why in the client chat afterwards.
