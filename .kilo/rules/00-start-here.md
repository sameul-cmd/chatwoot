# START HERE: Inbox Ops Kit takeover (read before doing anything)

This repository is a fork of Chatwoot (pinned to v4.18.0) plus our own kit: `opskit/` (Bash ops tools), `aibot/` (Python AI first-reply bot) and `docs/`.

**The root `AGENTS.md` / `CLAUDE.md` / `.windsurf/rules` belong to Chatwoot upstream. They apply ONLY if you edit Chatwoot's own files, which this project never does.** Everything we build lives in `opskit/`, `aibot/`, `docs/`.

Before any work, in this order:
1. Read `docs/ADOPT.md` completely (rules, setup, working loop, what is done, what is next).
2. Read `docs/PROGRESS.md` and the phase file that ADOPT.md section 6 names.
3. Tell the owner, in plain words (they are not technical): the phase and task you will do next, the files you will touch, and anything you need from them. Then wait for a go-ahead if the task touches Chatwoot's files, dependencies, secrets, backup/restore/upgrade logic, bot policy, or anything on a real server.

Never print or commit secrets, `.env` files, `opskit/clients/**`, keys. Never edit Chatwoot's own files. Work only on branch `claude/wizardly-babbage-ui2rpa`. Say "NOT verified" unless you ran it.
