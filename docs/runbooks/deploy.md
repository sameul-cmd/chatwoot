# Runbook: deploy a client stack

Plain-language steps. Today only the **local** target is supported (practice on your laptop or here). Real servers arrive with Phase 11; the commands below are the same.

## Practice run (local)
1. Check your tools: `opskit/bin/opskit doctor`.
2. Create the client: `opskit/bin/opskit client new demo --domain chat.demo.localhost --name "Demo Store" --local`
   (`*.localhost` addresses work on your own computer without DNS).
3. Deploy: `opskit/bin/opskit client deploy demo`
   - It builds the bot image, prepares the database, starts everything, waits until it is healthy and creates the first admin.
   - The admin login is shown once in the terminal and saved in `opskit/clients/demo/admin-credentials.txt` (private file). Move it into your password manager, then delete the file.
4. Open `https://chat.demo.localhost:8443` (accept the browser warning: it uses a local test certificate).
5. Check it: `opskit/bin/opskit client check demo` (5 checks, all should say PASS).
6. Test mails land in the local mail catcher, not in real inboxes.
7. Pause / continue: `client pause demo` / `client resume demo`.
8. Remove everything (destructive): `client offboard demo --yes` and type the client id when asked.

## Re-running is safe
`client deploy` can be run again at any time. It keeps the same secrets, does not create a second admin, re-runs `db:chatwoot_prepare` and only recreates what changed.

## What lives where (never commit these)
`opskit/clients/<id>/client.yaml` (settings), `secrets.env` (generated secrets), `stack/` (rendered files), `admin-credentials.txt` (one-time login). All are git-ignored and private (mode 600 for secret files).

## Real email (later)
Add `smtp: {host, port, user, sender}` to `client.yaml` and run `SMTP_PASSWORD=... opskit client render <id>`. Without a user name no login lines are written (see EXPLORATION_REPORT).

## Sandbox note
In a network with its own certificate (like this cloud sandbox) set `OPSKIT_BUILD_CA=/path/to/ca-bundle.crt` so the bot image build can reach the Python package server. Normal machines need nothing.

## Not done yet
Remote deploy to a real VPS, real HTTPS certificates, real SMTP, `host bootstrap` on a real server: all NOT VERIFIED until Phase 11 / your device.
