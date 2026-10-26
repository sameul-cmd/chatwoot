# MACHINE HANDOFF — laptop migration (written 2026-10-26)

> Purpose: this file lets any AI agent (Claude Code, Factory Droid, Kilo Code, Antigravity, Codex…) or human continue this project on a NEW laptop exactly where it stood on the old one. Read this first, then `docs/NEXT.md` (one-page current state) and `docs/ADOPT.md` (rules + loop). Keep it after migration — it is a migration record.

## 1. What this project is

A fork of Chatwoot pinned to upstream release **v4.18.0**, plus the owner's **Inbox Ops Kit**: `opskit/` (Bash: client-server deploy with Caddy, age-encrypted backups, monitoring with Telegram alerts, safe upgrades, channel checkers, bn+en industry packs, 218 bats tests) and `aibot/` (Python 3.12 FastAPI first-reply bot, FAQ-only answers, confidence ≥ 0.7 + fact guard, handoff-first per ADR-017). Business: the owner sells managed Chatwoot hosting to small businesses; owner is non-technical — use plain words, numbered steps, honest verification. Community Edition only; never edit Chatwoot's own files (2 ledgered exceptions in `docs/UPSTREAM_CHANGES.md`).

## 2. Where work stands (as of 2026-10-26, old laptop)

- **Branch:** `claude/wizardly-babbage-ui2rpa` (the repo's default branch) @ `2967d78` — remote tip `26aacaf` + **3 local commits** (Windows laptop setup docs/ADR-018, rails healthcheck fix A-050, setup verification report). They are pushed as part of this migration (owner-approved).
- **Status:** Phases 0–8 done and verified. Setup phase done on 2026-10-08 (first local machine).
- **Next step (current task 8.12, per `docs/NEXT.md`):** real-model check of the bot — owner runs `opskit/bin/opskit llm set-key demo --base-url https://<host>/v1 --paid` in the Ubuntu clone and tells the agent the base URL + chat model + embedding model (never the key); then `opskit llm models demo`, one embedding call, one answer call, `opskit bot eval demo`, one real conversation; record the score in `docs/tasks/phase-8.md`.
- Then: Phase 9 (monthly care report) → Phase 10 (re-scoped: verify + digest-pin official `chatwoot/chatwoot:v4.18.0-ce` arm64 image) → Phase 11 (real VPS + domain — biggest risk; free-staging options in `docs/STAGING.md`).

## 3. Old machine's environment (recreate what matters on the new laptop)

| Thing | Old value |
|---|---|
| OS / user | Windows 10, user `Sameul`; Windows *editing clone* lived at `C:\Users\Sameul\Documents\Projects\Chatwoot` |
| **Where runs happen** | **WSL2 Ubuntu-24.04 clone at `~/work/chatwoot-ops`** (all `opskit`/docker execution; the Windows copy is for editing only — ADR-018) |
| WSL2 | Ubuntu-24.04, isolated `docker.io` daemon inside WSL; Docker Desktop engine never touched; `.wslconfig`: memory=4608MB, processors=4, swap=4GB |
| git | 2.54.0.windows.1 on Windows; **`core.autocrlf=false` on Windows clones** (A-048-era lesson) |
| Toolchain | Node 24.13.0, pnpm 11.7.0, Python 3.12 via uv 0.12.19, Docker 29.4.2 |
| Known fixes on a fresh machine | `sudo apt install python3-pip` + jsonschema force-upgrade (A-048), docker-buildx + compose-v2 plugins (A-049), `OPSKIT_HEALTH_TIMEOUT=720` on the 2-core laptop (A-050 healthcheck fix already in the repo), `opskit/bin/check` channel rows can hang under double-stack load on weak hardware |

## 4. How to resume in each IDE

| Agent | Entry surface | First action |
|---|---|---|
| Claude Code (primary) | `.claude/CLAUDE.md` + `.claude/skills/` | open WSL clone → `claude` → `/resume` |
| Factory Droid / Kilo / Antigravity / any AGENTS.md reader | `docs/ADOPT.md` (paste-in prompt + current state) → `docs/NEXT.md` → current `docs/tasks/phase-N.md` | follow ADOPT.md section 7 loop |

## 5. NOT in git — restore before working

- The **WSL clone `~/work/chatwoot-ops`** — it is a separate git checkout inside Ubuntu and does not travel with the Windows folder. On the new laptop: recreate per §6 below (or copy `~/.bashrc` exports privately).
- `~/.bashrc` secrets in WSL (e.g. `AIBOT_LLM_API_KEY` if set), the **offline backup age private key** (only the public `opskit/keys/owner.age.pub` is committed), **Telegram alert bot token** — none are in git; copy privately.
- `opskit/clients/`, `opskit/hosts/` — git-ignored per-client data (none created yet).
- Nothing else: the working tree is clean, no stashes; the 3 setup commits are now pushed.

## 6. Fresh-laptop setup checklist (mirrors README-START-HERE "new device" note)

1. Windows: git + VS Code; set `core.autocrlf=false`. WSL: `wsl --install -d Ubuntu-24.04`; install docker.io inside Ubuntu (isolated daemon, ADR-018); set `.wslconfig` as above.
2. In WSL: `mkdir -p ~/work && cd ~/work && git clone https://github.com/sameul-cmd/chatwoot chatwoot-ops` (default branch is the working branch).
3. `opskit/bin/dev-setup` → `opskit/bin/opskit doctor` → `opskit/bin/check --quick` (must end ALL CHECKS PASSED).
4. Read `docs/ADOPT.md`, then `docs/NEXT.md` decision tree (task 8.12), then the plan file. Tell the owner phase/task/files before writing code.
5. Windows clone (optional, for editing only): clone the same repo; never run the stack from it.

## 7. Remotes after migration

- `origin` = `https://github.com/sameul-cmd/chatwoot` (public). Fast-forward push only — no force, no tags (forks don't carry upstream tags).
- GitHub Actions stay disabled in this repo (ADR-013) — verify after migration: repo Settings → Actions.
- Upstream sync only via `docs/UPSTREAM_SYNC.md`.
