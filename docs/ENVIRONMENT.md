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

| `OPSKIT_AGE_RECIPIENT` / `OPSKIT_KEYS_DIR` | operator shell | owner's PUBLIC age key (or folder holding `owner.age.pub`); private key never in the repo |
| `OPSKIT_BACKUP_AGENT`, `OPSKIT_ALERT_DIR`, `OPSKIT_NOW` | tests | override the backup script / alert folder / "now" for retention tests |
| `OPSKIT_HUB_URL`, `OPSKIT_HUB_TOKEN` | host | optional ops-hub endpoint for alerts and heartbeats (Phase 4 defines the hub side) |
| `CW_BASE_URL`, `CW_TOKEN`, `CW_RESOLVE`, `CW_INSECURE` | set by `cw_use_stack` | API helper settings; the token is never printed |

| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | operator shell, only at `opskit alerts set-telegram` | saved to `clients/<id>/alerts.env` (mode 600); `TELEGRAM_API_BASE` overrides the API URL (tests) |
| `TELEGRAM_API_BASE`, `META_GRAPH_BASE`, `META_GRAPH_VERSION` | tests / channel checks | override the Telegram API URL and the Meta Graph URL/version used by read-only channel probes (default `https://api.telegram.org`, `https://graph.facebook.com`) |
| `OPSKIT_PACKS_DIR` | tests | use another folder of packs than `opskit/packs` |
| `AIBOT_LLM_API_KEY` (name set by `bot.llm.api_key_env`) | operator shell, only at `opskit llm set-key` | the BYOK key; stored in `clients/<id>/llm.env` (mode 600), never printed; a hidden prompt is used when unset |
| `clients/<id>/llm.env`, `clients/<id>/bot.env` | written by `llm set-key` / `bot enable` | AI key; Chatwoot bot token, webhook signing secret, account and team id. Mode 600, git-ignored, merged into `stack/aibot.env`. After a restore run `bot enable` again |
| `AIBOT_MODE`, `AIBOT_CONFIG`, `AIBOT_KB_DIR`, `AIBOT_DATA_DIR`, `AIBOT_ACCOUNT_ID`, `AIBOT_HANDOFF_TEAM_ID`, `AIBOT_BUSINESS_NAME`, `AIBOT_CHATWOOT_HMAC_SECRET` | rendered into the bot container | see `aibot/src/aibot/config.py` |
| `OPSKIT_HEARTBEAT_URL` | host | external dead-man's-switch ping (healthchecks.io / UptimeRobot) called after each host monitor run |
| `OPSKIT_STATE_NOW`, `OPSKIT_NOW` | tests/selftest | fake clocks: decision clock only / all clocks |
| `OPSKIT_AIBOT_IMAGE` | operator shell | use an existing image for the bot instead of building (offline / rate-limited / Phase 10) |

| `OPSKIT_UPGRADE_FAIL_SMOKE=staging|production|rollback` | tests | injects a failing smoke row to prove the rollback |
| `OPSKIT_ENFORCE_WINDOW=1` | tests | enforce the off-hours window even on local practice stacks |
| `OPSKIT_STAGING_TAG` | set by the upgrade code | image tag for the staging copy (rehearsal) |
| `OPSKIT_SELFTEST_FROM`, `OPSKIT_SELFTEST_TO` | operator shell | releases used by `opskit selftest upgrade` (default v4.17.1-ce -> v4.18.0-ce) |

## 4. Rules
Never commit `.env`, keys, `opskit/clients/`, `opskit/hosts/`, dumps, KBs of real clients, bot audit DBs. Rotate any leaked key. Free-tier LLM only with demo data.
