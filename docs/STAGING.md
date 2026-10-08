# Staging & free hosting options — Inbox Ops Kit

> Written 2026-10-08 from the owner's Windows setup session (see PROGRESS.md same day). Records where the kit can be run and tested for free, and what was decided. SPEC wins on conflicts.

## What the owner's machine decided

| Item | Decision |
|---|---|
| Local Docker in WSL Ubuntu | **Isolated `docker.io` daemon inside Ubuntu-24.04** (ADR-018) — the Docker Desktop engine is never touched because other projects run there |
| Other Docker projects | **Never touched.** No `wsl --shutdown` unless the owner agrees, no pruning, no stopping/removing containers that are not ours. Only the kit's own containers (selftest cleans up after itself) |
| WSL VM memory | `.wslconfig` raised 3000 MB → 4608 MB (owner accepted the one-time container restart); heavy runs go alongside the owner's stack |
| Staging domain | none bought; tunnel hostnames now, the owner's Namecheap domain when going live |
| Cloud (Oracle, GCP) | excluded: Oracle free tier already used by another project; GCP ruled out by owner |

## Free staging options, researched 2026-10-08

**Finding: with Oracle and GCP excluded, no cloud offers a free always-on server that fits a Chatwoot compose stack** (Render free has no persistent disk and its free Postgres expires in 30 days; Koyeb free is 512 MB / 0.1 vCPU with a 5-hour Postgres; Railway gives $5 credit in the first month only; Fly.io has no free tier for new users and needs a card). So free staging is:

### Tier 1 — laptop-as-staging through a free public tunnel (recommended first)
The full stack runs locally in WSL Ubuntu; a tunnel gives it a public HTTPS URL so channel webhooks (Telegram, WhatsApp) can reach it while the laptop is on.
- **Tailscale Funnel** (recommended): free personal plan, stable `*.ts.net` hostname, automatic HTTPS; works well for webhooks.
- **Cloudflare quick tunnel** (`cloudflared tunnel --url ...`): no account, random `trycloudflare.com` URL each start — fine for ad-hoc webhook tests.
- **ngrok free**: one assigned dev domain, but 1 GB transfer / 20k requests / month and an interstitial page on the free domain (must be verified against real webhooks before relying on it).

### Tier 2 — GitHub Codespaces as the free off-laptop sandbox
Personal accounts: **120 core-hours/month (60 h on a 2-core machine) + 15 GB storage**, Docker works out of the box, forwarded ports give public HTTPS URLs for webhook tests during a session. Ephemeral (sleeps after idle; disk can be rebuilt) — for testing the kit, not for hosting. This mirrors the cloud sandbox the kit was built in.

### Tier 3 — go-live (not free, later)
The owner's Namecheap domain + a small VPS (Hetzner/Netcup/OVH, roughly US$4–6/month) in Phase 11. DNS can stay on Namecheap (Caddy only needs A/AAAA records), or move DNS to Cloudflare free if a named tunnel is wanted later.

### Free support services (already assumed by the kit)
Telegram alert bot (free), healthchecks.io / UptimeRobot heartbeat (`OPSKIT_HEARTBEAT_URL`, free), Let's Encrypt via Caddy (free), DuckDNS subdomain (free, only useful once a VPS exists).

## Machine-specific notes (owner's laptop, 2026-10-08)

- i5-6300U (2C/4T), 8 GB RAM host, WSL VM capped via `.wslconfig` (4608 MB, 4 vCPU, 4 GB swap).
- Two clones: `C:\Users\Sameul\Documents\Projects\Chatwoot` (editing/docs, LF enforced with `core.autocrlf=false`) and `~/work/chatwoot-ops` in Ubuntu (all runs; mode-600 secret checks work only here, not on `/mnt/c`).
- Windows git clone converted scripts to CRLF (breaks every `#!/usr/bin/env bash` under WSL): fixed with `git config core.autocrlf false` + re-checkout. Keep LF.
- Forks do not carry Chatwoot's release tags: `git remote add upstream https://github.com/chatwoot/chatwoot.git && git remote set-url --push upstream DISABLED && git fetch upstream tag v4.17.1 tag v4.18.0` (git tags have no `-ce` suffix; `-ce` is only the Docker image tag).
- Ubuntu 24.04 ships an old system `jsonschema` (no `registry=` kwarg; pulled in by apt `yq`) that shadows pip's copy and crashes `lib/schema_check.py`: fix with `pip install --break-system-packages --ignore-installed --upgrade jsonschema referencing pyyaml`.
- `python3-pip` is not preinstalled on Ubuntu 24.04; `dev-setup` fails on its first run without it.
- Cross-layer quoting (PowerShell → wsl.exe → bash) mangles `$` and quotes on Windows 10 19045: run a script file instead of inline `bash -c`.
