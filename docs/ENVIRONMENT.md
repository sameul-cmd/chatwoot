# Environment & Setup — Inbox Ops Kit

> Derived from `docs/SPEC.md` Sections 4, 16. SPEC wins on conflicts.

## 1. Laptop (all work in WSL2 Ubuntu)
Windows 10/11 + WSL2 Ubuntu 24.04 (WSL memory ~7–8 GB), Docker Desktop (WSL integration), VS Code Remote-WSL with Kilo Code or Factory `droid` run inside WSL, git, openssl, jq, yq, envsubst, curl, shellcheck, bats, age, rclone, ssh, Python 3.12 + uv/pip (aibot), ngrok free (HTTPS for mobile app/webhooks during exploration).

## 2. Accounts
GitHub (fork, Actions, GHCR) · Telegram bot (demo inbox + owner alerts) · test mailbox (IMAP/SMTP) · Meta developer account (WhatsApp test number / FB app, optional in Phase 0) · Gemini key (free tier for demo data; paid tier project for clients) · VPS + domains · off-server backup remote · Oracle Cloud (optional arm64 practice).

## 3. Variables
| Name | Where | Notes |
|---|---|---|
| `SECRET_KEY_BASE`, Postgres/Redis passwords | host `.env` | generated; abort if empty |
| `FRONTEND_URL` | host `.env` | `https://<domain>` |
| `ENABLE_ACCOUNT_SIGNUP=false` | host `.env` | no public signups |
| SMTP host/port/user/password, sender | host `.env` | client or owner provider |
| Meta app ids/secrets, WhatsApp verify tokens | host `.env` / Chatwoot UI | client-owned Meta apps (verify names) |
| `AIBOT_CHATWOOT_URL`, `AIBOT_BOT_TOKEN`, `AIBOT_WEBHOOK_SECRET` | aibot env | bot token from agent bot registration |
| `AIBOT_LLM_BASE_URL`, `AIBOT_LLM_MODEL`, `AIBOT_LLM_EFFORT` (none/low/medium/high/max), `AIBOT_LLM_EFFORT_PARAM`, `AIBOT_LLM_API_KEY`, `AIBOT_LLM_TIER_PAID` | aibot env | owner BYOK, any OpenAI-compatible endpoint (ADR-011); client mode requires paid/owner key |
| `OPSKIT_HUB_URL`, `OPSKIT_HUB_TOKEN`, `OPSKIT_TELEGRAM_FALLBACK_*` | host agent config | shared ops-hub + fallback |
| age public key | `opskit/keys/owner.age.pub` | private key offline only |

## 3b. opskit variables
| Name | Where | Notes |
|---|---|---|
| `OPSKIT_CLIENTS_DIR` | operator shell / tests | where `clients/<id>/` lives (default `opskit/clients`) |
| `OPSKIT_BUILD_CA` | operator shell | CA bundle path for building the aibot image behind an intercepting proxy (sandbox) |
| `SMTP_PASSWORD` | operator shell at `client render` | goes only into the stack `.env` (mode 600) |
| `OPSKIT_CONFIRM_ID` | tests/automation only | typed-id answer for destructive commands |
| `OPSKIT_HEALTH_TIMEOUT` | optional | seconds to wait for rails (default 300) |

## 4. Rules
Never commit `.env`, keys, `opskit/clients/`, `opskit/hosts/`, dumps, KBs of real clients, bot audit DBs. Rotate any leaked key. Free-tier LLM only with demo data.
