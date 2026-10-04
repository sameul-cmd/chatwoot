# Start here — Inbox Ops Kit (Claude Code version)

This package is added **on top of your fork** of Chatwoot. It never overwrites Chatwoot's own files (their `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `README.md` stay as they are). Nothing updates from upstream automatically.

All commands run in **WSL2 Ubuntu**. Open the repo in VS Code via Remote-WSL and run `claude` inside WSL.

1. On GitHub, fork https://github.com/chatwoot/chatwoot. In the fork: Settings → Actions → disable workflows.
2. In WSL: `mkdir -p ~/work && cd ~/work`
3. `git clone https://github.com/<you>/chatwoot.git chatwoot-ops && cd chatwoot-ops`
4. `git remote add upstream https://github.com/chatwoot/chatwoot.git`
5. `git remote set-url --push upstream DISABLED`
6. Check none of these exist yet: `.claude/CLAUDE.md`, `opskit`, `aibot`, `explore`, and in `docs/`: `SPEC.md`, `DECISIONS.md`, `TECH_ARCHITECTURE.md`, `USER_FLOWS.md`, `ENVIRONMENT.md`, `RESEARCH.md`, `PROGRESS.md`, `ASSUMPTIONS.md`, `UPSTREAM_CHANGES.md`, `UPSTREAM_SYNC.md`, `EXPLORATION_REPORT.md`, `docs/tasks`. If any exists, stop and tell Claude.
7. Unzip this package into the repo root (don't replace existing files).
8. `git add -A && git commit -m "docs(opskit): add specs and claude rules"`
9. In Claude Code: `/explore` (a project skill) → Phase 0: pin to the latest release, run Chatwoot CE locally, explore every feature, capture the agent-bot webhook, fill `docs/EXPLORATION_REPORT.md`.
10. Claude continues with `/start-phase` for Phase 1 (the 9 agreed improvements follow in Phases 1–11). It asks you only if something is blocked or unclear.
11. Repeat `/next-task`; end of phase: `/verify-phase` then `/security-review`. New session: `/resume`.

Community Edition only — CE image tags, nothing from `enterprise/`. Official WhatsApp Cloud API only.


**Already done (cloud session):** steps 1–8 — this repo is the fork at upstream v4.18.0 plus the kit. On a new device just `git clone` + checkout the branch.
