# Phase 11 — Field readiness: a real server, remote deploy, operator guide

Spec: SPEC Section 17 (Phase 11), Sections 7, 8, 9, 10. Read first: `docs/ADOPT.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`. **Status: planned, not started. This is the biggest remaining risk: everything so far was proven on one local Docker host. Ask the owner the open questions first.**
**Accept (from SPEC):** the full practice run completes from the operator guide without undocumented steps; timings and costs are recorded; the testing checklist passes.

## What this phase is, in plain words
Up to now every command works on a stack running on the same machine as the tools. A real client is on a **remote server** with a real domain and certificate. This phase (1) teaches the tools to do everything over SSH on a remote server, (2) tests that on a pretend remote host first, (3) does the **practice run on a real small server with the owner**, and (4) writes the operator guide and a pricing worksheet so the owner can onboard a first paying client alone.

## Known gaps this phase must close (they are refused today on purpose)
- `client deploy`, `backup`, `restore`, `monitor`, `upgrade`, `pack apply`, `channels check`, `bot enable` all call `_require_local` and use `cw_use_stack` (127.0.0.1 + the local Docker). A remote target is refused (A-005, A-010, A-019).
- Host agent scripts (`opskit/agent/backup.sh`, `bootstrap.sh`) exist and were tested with a fake SSH only; `host bootstrap` was never run on a real Ubuntu server.
- Real HTTPS certificates (Let's Encrypt via Caddy), real SMTP, off-server backup copy (rclone), cron on a real host, restore to a new host, the 10-minute critical alert path and the heartbeat are NOT VERIFIED.
- Chatwoot reached through its public domain: the API header must be `api-access-token`; SSRF/private-network rules for the bot webhook (ADR-012) must be rechecked on the real stack.

## Open questions for the owner (plain words; defaults in bold)
1. **Which server?** **Default:** a small paid VPS first (about 2 vCPU / 4 GB RAM, Ubuntu 22.04/24.04, anywhere with good latency to Bangladesh, e.g. Singapore) because it is the least surprising; the free Oracle ARM server second, once the ARM check (Phase 10) is done. You create the account and pay; I never create accounts for you.
2. **Which domain?** **Default:** a cheap domain you own (or a subdomain of one) such as `chat.<yourdomain>`; you add one DNS record I tell you.
3. **Practice client:** **Default:** you (a demo business with fictional data), never a paying client, for the first full run.
4. **Off-server backups:** **Default:** a free/cheap object storage bucket (Cloudflare R2 or Backblaze B2) through rclone; you create the bucket and a key limited to it.
5. **Pricing worksheet:** **Default:** a spreadsheet with your costs (server, domain, storage, AI usage per client) and three example price levels; you decide the prices.

## Tasks

### [ ] 11.1 — Remote execution layer
- **Goal:** one place (`lib/ssh.sh` + `lib/deploy.sh dc`) that runs `docker compose -p <id> ...` and file operations on the client's host over SSH (keys only, `known_hosts` pinned, timeouts), and a way to call Chatwoot's API on the public domain (real certificate, `api-access-token`). Replace `_require_local`/`cw_use_stack` assumptions command by command; a command that cannot run remotely says why.
- **Acceptance:** bats with the existing fake SSH for every command's remote path.

### [ ] 11.2 — A pretend remote host for tests
- **Goal:** a throw-away container with sshd and Docker (or a second VM if available) used by the selftest as "the server", so remote deploy, backup cron lines, restore to a new host and upgrade can be exercised before touching a real VPS. If this is not feasible in the cloud sandbox, document it and rely on 11.5.
- **Acceptance:** `opskit selftest remote` deploys to the pretend host and passes, or the limitation is recorded.

### [ ] 11.3 — Remote deploy, backup, restore, monitor, upgrade, bot, packs
- **Goal:** each command works with `deploy.target: remote`: `host bootstrap` (Docker, ufw 22/80/443, swap, unattended upgrades, deploy user), deploy, backups run by cron on the host with off-server copy and heartbeat, `restore --target new-host`, monitor and alerts from the host, `upgrade` on the host (off-hours window), `bot enable`, `pack apply`, `channels check`.
- **Acceptance:** all green against the pretend host; remote paths covered by bats.

### [ ] 11.4 — Operator guide and pricing worksheet
- **Goal:** `docs/OPERATOR_GUIDE.md` (new client end to end in numbered plain steps with expected times and what to tell the client), `docs/runbooks/onboarding-checklist.md`, a Bangla demo script (what to show a prospect in 10 minutes), the pricing worksheet (CSV/Sheet template), the customer-facing "what we do / what we do not do / response times" one-pager (draft; owner and a lawyer review).
- **Acceptance:** a person who has never seen the project can follow the guide's steps (dry read-through recorded).

### [ ] 11.5 — Practice run on the real server (with the owner)
- **Goal:** follow the guide exactly: bootstrap, deploy with the real domain and certificate, widget + email + Telegram (+ WhatsApp test number), apply the f-commerce pack, bot with the demo KB and the owner's AI key, backup and remote copy, **restore test into a fresh stack**, upgrade dry run, care report, kill-switch test, the 10-minute critical alert test (stop Sidekiq on purpose), the heartbeat test. Record timings, costs and every undocumented step; fix the guide, not the memory.
- **Acceptance:** completes without undocumented steps; the testing checklist (SPEC roadmap section 9) passes; costs and timings recorded.

### [ ] 11.6 — Close-out
- **Goal:** final `docs/PROGRESS.md` report, update ADOPT.md for "operating" mode (what to do when a client calls, how to ship an upgrade, how to sync upstream with `docs/UPSTREAM_SYNC.md`), list V2 add-ons still reserved (`docs/ADDONS.md`).
- **Acceptance:** `opskit/bin/check` passes; owner signs off.

## Not in this phase
The V2 add-ons (order capture, booking, FAQ editor UI, agent assist, owner digest, shared multi-client accounts), white-label branding (owner decision pending), a client portal.
