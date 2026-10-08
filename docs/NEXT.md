# NEXT: where this project stands and what to do now

*Read this first, then `docs/ADOPT.md`. Keep this file short and current: update it at the end of every task (see ADOPT.md section 7). Longer history: `docs/PROGRESS.md`.*
**Last updated:** 2026-10-08 · **Last full check:** cloud 2026-10-04 (`opskit/bin/check` ALL CHECKS PASSED, 218 bats) + laptop 2026-10-08 `check --quick` ALL PASS and selftest live rows PASS through monitoring (channel rows hung under double-stack load — see PROGRESS setup report) · **Branch:** `claude/wizardly-babbage-ui2rpa` (the repo's default branch) · **Local machine:** owner's Windows laptop, WSL Ubuntu + isolated docker (ADR-018); run stack from `~/work/chatwoot-ops` only; `docs/STAGING.md` has the machine-specific lessons

## The project in three lines
A fork of Chatwoot (open-source support inbox) pinned to v4.18.0, plus **opskit** (Bash tools: deploy a client's own server, encrypted backups/restore, monitoring with Telegram alerts, safe upgrades, channel checks, industry starter packs) and **aibot** (Python AI first-reply bot that answers only from the client's FAQ in Bangla/English and hands off to humans). The owner sells this as a managed service to small businesses and is **not technical**: use plain words, give numbered steps, say honestly what is NOT verified.

## What is done (all committed and pushed)
| Phase | What | State |
|---|---|---|
| 0-7 | Fork + exploration, foundation, deploy kit, backups/restore, monitoring, safe upgrades, channel checkers and runbooks, industry packs (bn+en) | done and verified on a local Docker demo |
| 8 | aibot (AI first-reply bot), `opskit bot ...`, `opskit llm ...`, eval gate | done and verified with a **scripted fake AI**; **8.12 (real-model check) in progress: the owner has a key** |
| setup | First real local machine (owner's Windows laptop): isolated docker in WSL Ubuntu, quick check green, demo stack deployed and 5/5 checks PASS, rails healthcheck bug found+fixed (A-050), staging options researched (`docs/STAGING.md`) | done 2026-10-08; commits local-only until the owner approves a push |

## What is left
| Phase | What | Plan file | State |
|---|---|---|---|
| 8.12 | Real-model check of the bot | `docs/tasks/phase-8.md` | waiting for the owner's AI key (see below) |
| 9 | Monthly care report per client | `docs/tasks/phase-9.md` | planned; 6 owner questions with defaults, not yet asked |
| 10 | Own multi-arch images | `docs/tasks/phase-10.md` | **re-scoped**: the official `chatwoot/chatwoot:v4.18.0-ce` image already has arm64; probably only verify + digest pinning; 2 owner questions |
| 11 | Real server, remote deploy, operator guide, pricing worksheet | `docs/tasks/phase-11.md` | planned; biggest risk (everything so far ran on one local Docker host) |

## What to do right now (decision tree)
1. **Task 8.12 (current).** The owner HAS a key. Waiting on: the owner runs `opskit/bin/opskit llm set-key demo --base-url https://<host>/v1 --paid` in the Ubuntu clone (hidden prompt; or export `AIBOT_LLM_API_KEY` in their own `~/.bashrc`) and tells the agent the **base URL, chat model and embedding model** (never the key). Then: `opskit llm models demo`, one embedding call, one answer call, `opskit bot eval demo`, one demo conversation with the real model; record the score (phase-8.md 8.12).
2. After 8.12: start **Phase 9**. Open `docs/tasks/phase-9.md`, ask the owner its open questions in plain words offering the bold defaults, write their answers at the top of the file, then build task by task (ADOPT.md section 7).
3. Phase 10 is short: ask its question 1 (own images or official?), record the ADR, then follow the plan. (ADR-018 is now the docker isolation decision; the images ADR takes the next free number.)
4. Phase 11 needs the owner to provide a small server (VPS) and a domain (they have Namecheap DNS; free staging path is in `docs/STAGING.md`). Plan and build the remote layer first; the real practice run is done together with the owner.

## Waiting on the owner (never block on these; keep reminding gently)
- **8.12 details (active):** run `llm set-key` on their machine + tell the agent base URL, chat model, embedding model. - Proofread the Bangla: `opskit/bin/opskit pack review fcommerce` and the bot's fixed messages (`aibot/src/aibot/messages.py`), then "approved". - Offline backup key (`age-keygen`; commit only the public line to `opskit/keys/owner.age.pub`). - Telegram alert bot + `opskit alerts set-telegram`. - White-label decision (default: keep Chatwoot branding). - Channel tests with their own accounts (Telegram, email, WhatsApp test number, Facebook/Instagram). - For Phase 11: a VPS and a domain. - Say OK to push the local commits to the branch.

## First 10 minutes in a fresh machine
1. `git clone https://github.com/sameul-cmd/chatwoot` (default branch is the working branch). 2. `opskit/bin/dev-setup` then `opskit/bin/opskit doctor` then `opskit/bin/check --quick` (must end ALL CHECKS PASSED). 3. Read `docs/ADOPT.md` (rules, loop, lessons), then the plan file for the step above. 4. Tell the owner the phase, the task and the files you will touch **before** writing code.

## Never forget
Community Edition only. Never edit Chatwoot's own files (two approved exceptions are in `docs/UPSTREAM_CHANGES.md`). No secrets or customer text in output, logs or git. Verify against the real running stack; "done" means `opskit/bin/check` passes plus a verification report in `docs/PROGRESS.md`.
