# Technical Architecture — Inbox Ops Kit (Chatwoot fork)

> Derived from `docs/SPEC.md`. SPEC wins on conflicts. Upstream internals: pinned code + official docs (verify).

## 1. System context
```mermaid
flowchart LR
  CU[Customers: widget, email, WhatsApp, FB/IG, Telegram] --> CD[Caddy https://chat.client.com]
  CD --> R[rails web + ActionCable]
  R <--> PG[(postgres)] & RD[(redis)]
  SK[sidekiq] <--> PG & RD
  R -- agent bot webhook --> AB[aibot]
  AB -- API reply/handoff --> R
  AB -- constrained prompt --> LLM[LLM provider]
  H[host cron: backup, health, channels] --> HUB[Shared ops-hub]
  HUB --> N[Telegram / email / Slack / WhatsApp]
  H --> BK[(off-server backups)]
  OP[Owner laptop WSL] -- ssh + opskit --> H
  GH[GitHub fork CI] -- images --> CD
```

## 2. Repo structure (ours)
```
opskit/
  bin/opskit, bin/check
  lib/*.sh                  logging, confirm, validate, render, ssh, docker, chatwoot_api
  schema/                   client.schema.json, bot.schema.json, pack.schema.json
  templates/                compose.yml.tmpl, env.tmpl, caddy.tmpl, cron.tmpl, client.yaml.tmpl, report/, alerts/
  agent/                    backup.sh, health.sh, channels.sh, heartbeat.sh (standalone on hosts)
  packs/<industry>/         canned_responses, labels, automations, business_hours, auto_replies, kb_starter (bn + en)
  hub/                      ops-hub additions (flows/monitors for Chatwoot clients)
  tests/                    bats + fixtures
  clients/, hosts/          git-ignored registries
aibot/
  pyproject.toml, Dockerfile
  src/aibot/{app.py, config.py, chatwoot.py, kb.py, retrieval.py, lang.py, llm.py, policy.py, handoff.py, audit.py, eval.py, metrics.py}
  tests/
.github/workflows/opskit-ci.yml, opskit-image.yml
docs/ (ours), explore/ (git-ignored)
```
Dependency direction: `opskit/bin → lib → templates/schema`; `aibot.app → policy → (retrieval, llm, handoff) → chatwoot client`; pure logic (`lang`, `retrieval`, `policy`) has no network I/O.

## 3. Client stack
Services: `rails`, `sidekiq`, `postgres`, `redis`, `aibot`; volumes `<id>_postgres`, `<id>_redis`, `<id>_storage`, `<id>_aibot`; only Caddy exposes 80/443; `aibot` reachable only on the internal network.

## 4. aibot request flow
webhook (secret path) → validate event type/account/inbox → ignore non-customer messages & bot's own → language detect → human-request/complaint check → retrieve top-k → LLM JSON → policy gate (confidence, snippet use, price/policy claims only from KB) → reply via API or handoff (message + status open + label + team) → audit row (no logs of text).

## 5. Key ops flows
Deploy, backup, restore, upgrade: same pattern as the Activepieces kit (render → deploy → verify; dump → encrypt → remote → heartbeat; fresh-stack restore; staging → promote → rollback), plus `db:chatwoot_prepare` on deploy/upgrade and storage volume in backups.

## 6. Sizing defaults (Phase 0 overrides)
rails 1.5 GB, sidekiq 1 GB (concurrency 5), postgres 1 GB, redis 256 MB, aibot 256 MB; 4 GB host + 2 GB swap minimum.
