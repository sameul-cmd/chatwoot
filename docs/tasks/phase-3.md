# Phase 3 — Backups & restore (Improvement 2)

Spec: SPEC Section 8, Section 17 (Phase 3), Section 3 (rules 6, 8, 10), `.claude/CLAUDE.md` "Reliability rules".
**Accept (from SPEC):** restore of a demo client with conversations and an image attachment into a new stack shows both; `.env` escrow decrypts; pruning exact (fixture); overwrite protection works; failed backup raises an alert payload.

## Facts from Phase 0 / 2 this phase relies on
- Backup = `pg_dump -Fc` (via the postgres container) + tar of the `<id>_storage` volume + the client's secrets. Phase 0 proved a restore into a fresh stack: 52 conversations back, login works, an attachment byte-identical.
- Chatwoot's database and sessions depend on `SECRET_KEY_BASE`: a restore without the original secrets is not a working restore, so the encrypted secrets escrow (`secrets.env` + stack `.env` files) is part of every backup. Task 3.6 verifies and records exactly what breaks without it.
- Redis holds only cache and queued jobs (not backed up on purpose; queued-but-unprocessed jobs are lost on restore: document it).
- Stack/volume names are `<id>_*` and compose projects are always `-p <id>`; a restore stack uses project `<id>-staging` with its own volumes and ports so it can never touch production.
- Tools present: `age` 1.1.1, `rclone` 1.60. `opskit/keys/owner.age.pub` does not exist yet.

## Open questions for the owner (answers needed: backup/restore logic and secret handling need approval)
1. **Encryption key.** Default: you create the key pair on your own device (`age-keygen -o owner.key`), keep `owner.key` OFFLINE (password manager), and give me only the public line (`age1...`), which I save as `opskit/keys/owner.age.pub` (public, safe to commit). Here in the sandbox the tests use throw-away keys that are deleted afterwards. I will never see your private key. OK?
2. **Off-server copy.** Default: built and tested here against a *local-folder* rclone remote that behaves like a remote; you pick and configure the real storage (Backblaze B2, Cloudflare R2, Google Drive, S3 ...) later on your device. Decision needed from you only then. OK?
3. **Schedule and retention.** Default (SPEC): nightly at 02:00 in the client's time zone, keep 14 days locally and 30 days on the remote. The cron/timer file is generated here but only installed on a real host in Phase 11. OK?
4. **Consistency.** Default: the database dump is a consistent snapshot while the stack runs; the uploads tar is taken live (tiny chance a file written during the tar is missing). No downtime for the client. OK?
5. **Restore targets.** Default: `--target staging` (same machine, project `<id>-staging`, different ports) and `--target new-host` (fresh stack on another machine, fake-SSH tested only until Phase 11). Restoring onto the running production stack needs `--overwrite --yes` + typed client id + your approval in chat. OK?
6. **Monthly restore test.** Default: a job restores the latest backup into a throw-away staging stack, checks login, that the most recent conversation exists and that one attachment opens, writes a JSON result for the care report (Phase 9), then deletes the staging stack. OK?
7. **Alerts.** Default: until the ops-hub exists (Phase 4) a failed backup writes an alert JSON file (`opskit/alerts/outbox/`, git-ignored) and exits non-zero; a heartbeat is sent only if `OPSKIT_HUB_URL` is set. No message text in any alert or log. OK?

## Tasks

### [x] 3.1 — Encryption helpers (`lib/crypto.sh`)
- **Goal:** `encrypt_file IN OUT` using `opskit/keys/owner.age.pub` (or `OPSKIT_AGE_RECIPIENT`); `decrypt_file IN OUT IDENTITY`; refuses to run without a recipient; output mode 600.
- **Tests:** bats with a throw-away key: round trip equals original; missing recipient aborts; wrong identity fails; no plaintext left next to the `.age` file

### [x] 3.2 — Backup settings in the schema
- **Goal:** `client.schema.json` `backup` becomes typed: `local_dir`, `schedule` (cron), `retention_local` (14), `retention_remote` (30), `remote` (rclone remote:path). Defaults per SPEC.
- **Tests:** bats: bad retention / unknown key rejected with field name

### [x] 3.3 — Backup agent script (`agent/backup.sh`), standalone on the host
- **Goal:** one run creates `<local_dir>/<id>/<UTC timestamp>/` with `db.dump`, `storage.tar.gz`, `secrets.age` (encrypted escrow), `manifest.json` (tag, sizes, sha256, timestamps). Written to a `.partial` folder and renamed only when every file has size > 0; `flock` against overlapping runs; `set -euo pipefail`; no message text in logs.
- **Tests:** bats with a fake `docker` (dump/tar stubs): success layout; zero-size dump fails and leaves no complete backup; second concurrent run refuses

### [x] 3.4 — `opskit backup run <id>` and retention pruning (`lib/prune.sh`)
- **Goal:** wrapper reading `client.yaml`; prune keeps exactly the newest N days/backups (never the only complete backup).
- **Tests:** fixture folder with dated backups -> exactly the expected set remains; a `.partial` folder is never counted as a backup

### [x] 3.5 — Off-server copy with rclone
- **Goal:** after a local backup, `rclone copy` to `backup.remote`, verify sizes match (`rclone check --size-only`), prune the remote by `retention_remote`.
- **Tests:** bats against a local-folder rclone remote: copy verified, remote pruning exact, an unreachable remote returns non-zero and raises the alert (3.8)

### [x] 3.6 — `opskit restore <id> --from <ts> --target staging|new-host`  [needs your approval: restore logic]
- **Goal:** restore into a FRESH stack (`<id>-staging`, new volumes, other ports): decrypt escrow (identity file given by `--identity`), create volumes, `pg_restore`, unpack storage, start, wait healthy. Refuses if the target stack already exists unless `--overwrite --yes` + typed id. `--from latest` allowed. Verify and record in EXPLORATION_REPORT what breaks when `SECRET_KEY_BASE` differs.
- **Tests:** bats: overwrite protection (running target refused, wrong typed id refused); decrypt failure aborts before touching anything; integration (docker-gated) in 3.10

### [x] 3.7 — Restore test job (`opskit backup verify <id>`)
- **Goal:** latest backup -> throw-away staging stack -> checks: login via API, most recent conversation present, one attachment opens and matches its recorded checksum -> JSON result file -> staging deleted (always, even on failure). Result format reusable by the care report (Phase 9).
- **Tests:** integration (docker-gated); unit tests for the result JSON

### [x] 3.8 — Failure alert payload + heartbeat (`lib/alert.sh`)
- **Goal:** one function builds an alert JSON (`severity`, `client_id`, `check`, `summary` <= 300 chars, timestamp, no message text); written to `opskit/alerts/outbox/`; optional POST to `OPSKIT_HUB_URL` with token; success heartbeat after each good backup. Phase 4 reuses it (`lib/notify.sh` per TECH_ARCHITECTURE section 7).
- **Tests:** bats: payload fields and size limit; secrets never present; failed backup produces the file; hub unset = skipped, not failed

### [x] 3.9 — Schedule template
- **Goal:** `templates/backup.cron.tmpl` (nightly 02:00 in the client's time zone, `flock`), rendered by `client render`; install on a real host is Phase 11.
- **Tests:** bats: rendered cron line correct, time zone applied, no unresolved variables

### [x] 3.10 — Seed data, API helper and selftest v2
- **Goal:** `lib/chatwoot_api.sh` (timeouts, retries on 429/5xx, no token echo); selftest additionally creates a conversation + image attachment, runs backup -> restore into staging -> verify, and proves overwrite protection; always cleans up.
- **Acceptance:** `opskit selftest` shows backup + restore PASS rows

### [x] 3.11 — Runbook, docs, verification
- **Goal:** `docs/runbooks/restore.md` (plain-language, includes "where is my private key" and "what if the server is gone"), update PROGRESS/ASSUMPTIONS/ENVIRONMENT, run `/verify-phase` and the security review (key handling, file modes, no plaintext secrets left behind).
