# Runbook: upgrading a client safely

## The idea
Never upgrade the live system first. The command does it in this order: read what changed -> back up -> rehearse on a copy built from that backup (including the database changes) -> test the copy -> (only in the client's quiet hours) upgrade the live system -> test it -> if anything fails go back automatically and check that no data was lost.

## Commands
| What | Command |
|---|---|
| What would change? | `opskit/bin/opskit upgrade <id> --to v4.18.0-ce --info` |
| Rehearse on a copy | `opskit/bin/opskit upgrade <id> --to v4.18.0-ce --stage` |
| Upgrade the live client | `opskit/bin/opskit upgrade <id> --to v4.18.0-ce --apply --yes` (then type the client name) |
| Outage fix outside the window | add `--outage-fix` |
| Is a newer Chatwoot release safe for OUR code? | `opskit/bin/sync-rehearsal v4.17.1 v4.18.0` |

Only Community Edition tags (ending in `-ce`) are accepted, and only newer ones: downgrades are not supported (the rollback is the only way back).

## When can a live client be upgraded?
By default only between 01:00 and 05:00 in the client's time zone. Change it per client in `client.yaml`:
```
upgrade_window:
  start: "02:00"
  end: "04:00"
```
or `upgrade_window: {mode: anytime}` for a client who accepts upgrades at any hour. Practice stacks on your own computer are exempt.

## What "rollback" does exactly
1. Puts the old version number back and restarts the services on the old program.
2. If the database was changed by the new version (checked by its version number) it restores the database from the backup taken right before the upgrade. Uploads are kept (new files only add).
3. Runs the same tests on the old version and requires that the conversation count and newest conversation match the backup exactly.
4. Sends you a red Telegram message and writes `upgrade/history.jsonl`.
Customer messages received between the backup and the rollback are lost (typically a few minutes at night).

## Files it keeps (per client, private)
`opskit/clients/<id>/upgrade/history.jsonl` (one line per attempt), `staging-<tag>.json` (result of the last rehearsal), dated copies of `client.yaml` from before each tag change.

## Syncing the fork to a newer Chatwoot release (our code)
1. `git fetch upstream tag <new>` and `opskit/bin/sync-rehearsal <current> <new>`: builds "current release + our kit" in a throw-away folder, merges the new release, reports conflicts, checks that only our paths (or ledger-listed patches) differ. Your real branch is never touched.
2. If it says OK, follow `docs/UPSTREAM_SYNC.md` for the real merge.

## Not verified yet
Upgrades on a real server, large databases (migration time), multi-version jumps, WhatsApp/Telegram behaviour during the downtime, bot reply check (Phase 8).
