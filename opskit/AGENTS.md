# opskit — Chatwoot operations kit (our code)

- Follow the Architecture, Ops script, Reliability and Packs & channels rules in `.claude/CLAUDE.md`.
- `bin/` entry points; `lib/` shared Bash (incl. `chatwoot_api.sh`); `schema/`; `templates/`; `agent/` standalone host scripts; `packs/` industry data (bn + en); `hub/` ops-hub additions; `tests/`.
- `clients/` and `hosts/` hold real data: never print secrets, never commit.
