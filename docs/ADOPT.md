# Adopt this project — for any AI, any IDE, any model

This file is the **one entry point**. It works with Claude Code, Cursor, Windsurf, Kilo/Roo/Cline, Copilot, Codex, Gemini or a plain chat model: it does not depend on any tool's special features. If this file and `docs/SPEC.md` ever disagree, **SPEC wins**.

## 1. Paste this to the AI (copy the whole box)

```
You are taking over an existing project from another AI. Repository: https://github.com/sameul-cmd/chatwoot
Branch: claude/wizardly-babbage-ui2rpa  (work on this branch only; never push anywhere else without asking me)

1. Clone it and check out that branch.
2. Read these fully, in order: docs/NEXT.md (short: what is done, what to do next), docs/ADOPT.md, docs/PROGRESS.md, then the plan file NEXT.md tells you to do next.
3. Follow docs/ADOPT.md exactly. I am not technical: explain in plain words, number any step I must do, and say honestly what is NOT verified.
4. Before writing any code, tell me: the phase and task you will do next, the files you will touch, and anything you need from me.
Do not trust your memory of this project: trust the files.
```

### How each tool picks this up
The repo contains small auto-loaded rule files that point to this guide, so for most tools you only have to open the folder and say **"adopt this project"**. (Chatwoot's own root `AGENTS.md` / `CLAUDE.md` are upstream's and do not describe our work: our rule files say so.)

| Tool | What it loads by itself | What you do |
|---|---|---|
| **Kilo Code** | `.kilocode/rules/` and `.kilo/rules/` (+ `/resume`, `/start-phase`, `/next-task`, `/verify-phase` workflows in `.kilocode/workflows/`) | Clone, open the folder, start a chat, paste the box above (or just type "adopt this project"); use the slash workflows to continue |
| **Cursor** | `.cursor/rules/` (always on) | Same |
| **Cline / Roo Code** | `.clinerules/`, `.roo/rules/` | Same |
| **GitHub Copilot** | `.github/copilot-instructions.md` | Same |
| **Gemini CLI** | `GEMINI.md` | Same |
| **Codex / Windsurf / others** | they read the root `AGENTS.md` (Chatwoot's), which does not know our project | **Always paste the box above** |
| **A plain chat window** (no git, no commands) | nothing | paste the contents of `docs/ADOPT.md`, `docs/PROGRESS.md` and the current phase file; it can plan and write documents but cannot run the checks |

The tool needs to be able to run shell commands and Docker for building and verifying. Model quality matters: pick the strongest coding model your tool offers, because this project has many small rules (verify before claiming, never print secrets, never edit Chatwoot's files).

## 2. What this project is (one paragraph)
A sellable "AI inbox service" for small businesses (Bangladesh first). The owner installs **one Chatwoot Community Edition per client** (open source support inbox: website chat, email, Telegram, WhatsApp, Facebook, Instagram) and adds our kit on top: **opskit** (Bash tools: deploy, backup/restore, monitoring with Telegram alerts, safe upgrades, channel checks, industry starter packs, reports) and **aibot** (Python service: an AI first-reply bot that answers only from the client's own FAQ in Bangla/English and hands off to humans). The repo is a fork of `chatwoot/chatwoot` pinned to release **v4.18.0**. Our code lives only in `opskit/`, `aibot/`, `docs/`, `.claude/`, `explore/` and `.github/workflows/opskit-*.yml`; **every other file is Chatwoot's and must not be edited** (a test enforces it). The only approved exceptions are the fork-notice banners at the top of the root `README.md` and `AGENTS.md`, listed in the patch ledger `docs/UPSTREAM_CHANGES.md`; keep them when syncing a new Chatwoot release.

## 3. Who the owner is and how to talk to them
Non-technical / semi-technical, works from several laptops, wants to sell this as a side business. Use plain words and define any jargon. Give **numbered "do this" steps** for anything they must do (never ask them to type commands unless unavoidable; then give the exact text). Say what can be skipped and what you will handle. Be honest: "verified" only if you ran it; otherwise say "NOT verified". Never ask them to paste a key or password into chat: keys go into environment settings or files on their own machine.

## 4. Hard rules (short form; the long form is `.claude/CLAUDE.md` and `docs/SPEC.md`)
1. **Community Edition only**: CE image tags (`...-ce`), never touch `enterprise/`, keep "Powered by Chatwoot".
2. **Never edit Chatwoot's own files.** Any exception needs the owner's approval, a row in `docs/UPSTREAM_CHANGES.md`, and a test. Check: `opskit/bin/check` runs the upstream-path test.
3. **One task at a time**, from the current phase file. Bugs outside the task go in `docs/PROGRESS.md` "Known issues", not silently fixed.
4. **Verify against the real thing.** Never invent Chatwoot env keys, API routes, webhook payloads or image tags: read the pinned source or run the live demo, and record the answer (`docs/EXPLORATION_REPORT.md`, `docs/ASSUMPTIONS.md`). Unit tests with fakes hide real bugs: run the real stack before calling something done.
5. **Secrets**: never read, print or commit `.env` files, `opskit/clients/**`, keys, dumps, real client data. Secrets come from `openssl rand`, files are mode 600, nothing on command lines. Logs and alerts never contain message text, phone numbers or emails.
6. **Destructive or live actions** (restore over data, delete stacks, anything on a real client host) need `--yes`, the typed client id and the owner's approval in chat. Never deploy or upgrade a client during their business hours unless it is an outage fix.
7. **The bot** answers only from the client's FAQ, discloses it is automated, never claims to be human, never states a price/policy that is not in the FAQ, hands off when unsure. Official WhatsApp Cloud API only.
8. **Ask before**: new dependencies, upstream edits, anything touching a real host or real customer data, editing `docs/SPEC.md` or anything in `.claude/`.
9. **Done means** `opskit/bin/check` passes (and `opskit/bin/opskit selftest`) and `docs/PROGRESS.md` has a verification report.
10. Conventional commits (`feat(opskit): ...`, `fix(...)`, `docs: ...`); no AI model name in commit messages or code comments. Commit per task, push to the branch above. Do not open a pull request unless the owner asks.

## 5. Machine setup (once per machine / fresh cloud session)
- Needs: Git, Docker (daemon running), Linux or WSL2 Ubuntu. Run `opskit/bin/dev-setup` (installs/starts what it can and lists what is missing), then `opskit/bin/opskit doctor`, then `opskit/bin/check --quick` (must end with `ALL CHECKS PASSED`).
- Full check including the live selftests: `opskit/bin/check` (about 20 minutes; run it in the background with output to a log file, because many tools time out at 10 minutes).
- Cloud sandboxes: the Docker daemon is not started automatically (`dev-setup` does it); Docker Hub often rate-limits (HTTP 429): set `OPSKIT_AIBOT_IMAGE=opskit-aibot:test` (a previously built image) or retry; behind an intercepting proxy set `OPSKIT_BUILD_CA=<ca bundle path>`.
- Lessons that cost hours before: quote heredocs (`<<'EOF'`); `docker compose exec` inside a `while read` loop swallows the loop's input (add `</dev/null`); **never `pkill -f` a pattern that appears in your own command line** (kill by exact PID); the API header through Caddy must be `api-access-token` (with dashes); a replaced bind-mounted file needs `up -d --force-recreate`; long runs go in the background with a log; waiting loops must not match their own command line.

## 6. State right now and what to do next
**`docs/NEXT.md` is the always-current short version of this section: read it first.** Then `docs/PROGRESS.md` for the history.

| Phase | What | State |
|---|---|---|
| 0 | Fork, pin v4.18.0, explore Chatwoot | done |
| 1 | Foundation: CLI, schemas, checks | done |
| 2 | Deploy kit: one stack per client | done |
| 3 | Backups and restore (encrypted) | done |
| 4 | Monitoring and Telegram alerts | done |
| 5 | Safe upgrades with rollback | done |
| 6 | Channel runbooks and checkers | done |
| 7 | Industry starter packs (bn + en) | done (Bangla awaits owner proofreading) |
| 8 | aibot, the AI first-reply bot | done with a pretend AI; **8.12 real-model check pending the owner's key** |
| 9 | Monthly care report | planned: `docs/tasks/phase-9.md` |
| 10 | Own multi-arch images | **re-scoped** (official CE image already has arm64): `docs/tasks/phase-10.md` |
| 11 | Field readiness: real server, remote deploy, operator guide | planned: `docs/tasks/phase-11.md` |

**Next step for a new AI:** (a) if the owner says the AI key is in the environment, do task 8.12 in `docs/tasks/phase-8.md`; (b) otherwise start Phase 9: read `docs/tasks/phase-9.md`, ask the owner its open questions (offer the bold defaults), then build task by task.

## 7. The working loop (what the Claude `/start-phase`, `/next-task`, `/verify-phase`, `/resume` commands do, in plain steps)
1. **Resume**: read `docs/PROGRESS.md` and the current `docs/tasks/phase-N.md`; read only the SPEC/doc sections they point to; tell the owner phase, task, files (flag any non-kit file).
2. **Plan a phase** (if no task file or it has unanswered questions): write/refresh `docs/tasks/phase-N.md` in the format of `docs/tasks/phase-8.md`: plain-language intro, verified facts, **open questions with bold defaults**, numbered tasks with Goal and Acceptance. Ask the owner; record their answers at the top of the file.
3. **Build** task by task: small steps, tests with the code (bats for Bash, pytest for the bot), run `opskit/bin/check --quick` after each step, tick the task in the phase file.
4. **Run it live** on the demo stack (`opskit client new demo --local ...`, `opskit client deploy demo`); fix what only the live run reveals.
5. **Verify**: `opskit/bin/check` (full) plus `opskit/bin/opskit selftest`; add selftest rows for new behaviour; do a security review (no secrets/PII printed, probes read-only, permissions).
6. **Record**: verification report in `docs/PROGRESS.md` (criterion / result / evidence, then NOT VERIFIED, then owner to-dos), ADR in `docs/DECISIONS.md` for design choices, `docs/ASSUMPTIONS.md` rows for judgement calls, `docs/ENVIRONMENT.md` for new variables, a runbook in `docs/runbooks/` for anything an operator does.
7. **Update `docs/NEXT.md`** (status table, "what to do right now", waiting-on-owner list, last check result; keep it under 80 lines), then **commit and push** to the branch and summarise for the owner in plain words with their next steps. A task is not finished until NEXT.md is current.

## 8. Map of the repo (ours)
`docs/SPEC.md` source of truth · `docs/PROGRESS.md` status and reports · `docs/DECISIONS.md` ADRs · `docs/ASSUMPTIONS.md` · `docs/TECH_ARCHITECTURE.md` · `docs/ENVIRONMENT.md` · `docs/EXPLORATION_REPORT.md` (verified Chatwoot facts) · `docs/runbooks/` (operator how-tos) · `docs/tasks/` (phase plans) · `opskit/{bin,lib,agent,templates,schema,data,packs,tests}` · `aibot/{src/aibot,tests,demo}` · `.claude/` (Claude Code's own copy of the rules and slash commands) · `.kilocode/`, `.kilo/`, `.cursor/`, `.clinerules/`, `.roo/`, `GEMINI.md`, `.github/copilot-instructions.md` (tiny auto-loaded pointers to this file for other tools).
Key commands: `opskit/bin/opskit help` lists everything (client new/deploy, backup, restore, monitor, upgrade, channels, pack, llm, bot, selftest).

## 9. Things only the owner can do (never block on these; keep a list)
1. Create the offline backup key (`age-keygen`), keep the private file offline, commit only the public `age1...` line to `opskit/keys/owner.age.pub`.
2. Create the Telegram alert bot (@BotFather) and run `opskit alerts set-telegram <id>`; a free heartbeat check (healthchecks.io/UptimeRobot) in `OPSKIT_HEARTBEAT_URL`.
3. Decide white-label (default: keep Chatwoot branding) and ask Chatwoot or a lawyer before selling.
4. Give the AI key for task 8.12 as an **environment secret** `AIBOT_LLM_API_KEY` plus the provider host in the network allow-list; tell the AI the base URL, chat model and embedding model. Then start a new session.
5. Proofread the Bangla: `opskit pack review fcommerce` and the bot's fixed messages (`aibot/src/aibot/messages.py`), then say "approved" so the AI flips the flags.
6. Test the channels with their own accounts (Telegram, email, WhatsApp test number, Facebook/Instagram) and check the Bengali UI.
7. For Phase 11: a small server (VPS) and a domain.

## 10. If you are a different AI than the previous one
Do not assume you share its memory or tools: `docs/PROGRESS.md` "Lessons for the agent", this file and the phase files are the memory. If a command from `.claude/skills/` is mentioned, open that folder's `SKILL.md` and follow it as plain instructions. If a tool you need (Docker, network) is missing, say so, do the parts that do not need it (planning, docs, pure-logic code with tests), and list the rest as "needs a machine with Docker".
