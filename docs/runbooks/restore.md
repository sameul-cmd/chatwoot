# Runbook: backups and restores

Plain-language guide. Today everything is tested on a local practice stack; the same commands run on a real server from Phase 11.

## What a backup contains
One dated folder per run, e.g. `20261004T020000Z`:
- `db.dump` - the whole database (conversations, contacts, settings, users)
- `storage.tar.gz` - uploaded files (photos, documents)
- `escrow.tar.age` - the client's secrets (`secrets.env`) and settings (`client.yaml`)
- `manifest.json` - sizes, checksums and counts (no message text); the only readable file
Names: `db.dump.age` (database) and `storage.tar.gz.age` (uploads) are **encrypted**, like the escrow, to TWO keys: your public key (private key offline) and a key kept on the server (`opskit/clients/<id>/backup.key`). So a stolen off-server copy cannot be read, and the monthly self-check can still open backups by itself.
Redis is not backed up on purpose (it is only a cache and a job queue; jobs not yet processed at restore time are lost).

## The key (very important)
- You create the key pair once on your own computer: `age-keygen -o owner.key`. It prints a line starting with `age1...`: that is your PUBLIC key. Put that line in `opskit/keys/owner.age.pub`.
- `owner.key` is your PRIVATE key. Keep it OFFLINE (password manager + a printed or USB copy in a safe place). **If the server's own key is lost together with the server, your key is the only way to open the backups.** Never commit it, never send it in chat.
- The server key (`backup.key`) is created automatically and stays on that server only; it is never copied off-server.

## Everyday commands
- Back up now: `opskit/bin/opskit backup run <id>` (also prunes old backups: 14 days local; copies off-server and keeps 30 days there when `backup.remote` is set in `client.yaml`).
- List: `opskit/bin/opskit backup list <id>`
- Test that backups really work (recommended monthly): `opskit/bin/opskit backup verify <id>` - restores the newest backup into a throw-away copy, checks login, the newest conversation and one attachment, writes `clients/<id>/verify/<time>.json`, then deletes the copy. Add `--identity owner.key` now and then to also prove the escrow opens with your key.
- If a backup or the off-server copy fails, an alert file appears in `opskit/alerts/outbox/` and the command exits with an error.

## Restore (always into a NEW copy)
`opskit/bin/opskit restore <id> --from <timestamp|latest> --target staging [--identity owner.key]`
- Creates `<id>-staging` on other ports (HTTPS port + 100) with its own volumes. The live client is never touched.
- Check the copy, then decide what to do. If the staging copy already exists the command refuses; add `--overwrite --yes` and type the staging name to replace it.
- `--target new-host` (restore onto another server) arrives with remote deploys in Phase 11.

## If the secret key is lost
Tested: restoring with a different `SECRET_KEY_BASE` still works (password login and API tokens are fine) but everyone is logged out and old signed attachment links stop working. Channel secrets stored encrypted (only when Chatwoot's encryption keys are configured) could be unreadable. So keep the escrow and your private key safe.

## If the whole server is gone
1. Get a new server (Phase 11 guide), install the kit.
2. Fetch the newest folder from the off-server storage.
3. Use `owner.key` to open the files (`age -d -i owner.key escrow.tar.age | tar -x`; same for `db.dump.age` and `storage.tar.gz.age`), put `secrets.env` and `client.yaml` back under `opskit/clients/<id>/`, then restore (new-host restore is added in Phase 11).

## Not verified yet
Real off-server storage, the cron schedule on a real host, restore onto a different host, bigger data sizes.
