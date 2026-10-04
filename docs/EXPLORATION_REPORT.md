# Exploration report — Inbox Ops Kit (Chatwoot fork)

> Filled during Phase 0 (clone, set up & explore). Facts only — what actually happened on this machine. Blockers or mismatches with the SPEC go to the owner before continuing.

## 1. Setup
| Item | Value |
|---|---|
| Repo + commit/version explored | chatwoot v4.18.0 (tag SHA 9f920b549); image `chatwoot/chatwoot:v4.18.0-ce` |
| How it was installed/cloned | Upstream `docker-compose.production.yaml` with image changed to the `-ce` tag; `.env` from `.env.example`; `db:chatwoot_prepare` via one-off container; Super Admin + account created with `rails runner` (stack in git-ignored `explore/stack/`) |
| Machine (CPU/RAM/GPU/OS) | Cloud sandbox: 4 vCPU, 15 GB RAM, Linux, Docker 29.6 (NOT the owner's 12 GB WSL laptop) |
| Free path used (keys, free tiers, local models) | None needed |
| Setup time + problems hit (and fixes) | ~5 min. Docker daemon had to be started by hand (sandbox). Agent-bot webhook to a private address was blocked until `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` (see section 5/6) |

## 2. Feature walkthrough
| Feature | Tried with (sample data) | Result (works / partly / broken) | Notes, screenshots/log paths |
|---|---|---|---|
| Production compose + CE image | official compose, `-ce` tag | works | `v4.18.0-ce` tag exists. Compose also starts a pointless `base` container (it is the YAML anchor, harmless). Health route: `GET /api` -> `{"version","queue_services","data_services"}` |
| Super Admin / account creation | `rails runner` | works | Account, SuperAdmin user, AccountUser(administrator); user has `access_token` for the Application API |
| Application API | token header `api_access_token` | works | create inbox, agent bot, set_agent_bot, conversations, messages, labels, toggle_status |
| Website widget inbox + real widget in a browser | headless Chromium, page served from localhost | works | Bubble -> "Start Conversation" -> message sent -> conversation created `pending` with bot assigned. Widget also posts its own "Give the team a way to reach you / Get notified by email" template messages (message_type `template`, 3) and these reach the bot webhook as `message_updated`/`message_created` - aibot must ignore them. Widget from a non-localhost fake domain was blocked by browser CORS (test artifact only) |
| API-channel inbox + public API | `/public/api/v1/inboxes/<inbox_identifier>/contacts/...` | works | used for scripted customer messages |
| Agent Bot (webhook) | listener `explore/listener.py` | works | see `docs/captures/agent-bot-message_created.json` and section 6 |
| Bot reply | `POST /api/v1/accounts/1/conversations/:id/messages` with the bot's `access_token`, `message_type: outgoing` | works | 200 |
| Handoff | `POST .../conversations/:id/toggle_status {"status":"open"}` with bot token | works | status pending -> open, bot assignee cleared; emits conversation_status_changed / conversation_opened |
| Label via bot token | `POST .../conversations/:id/labels {"labels":["ai-handoff"]}` | works | 200 |
| Attachments (image) | 70-byte PNG via public API multipart | works | stored in `storage_data`, opens after restore |
| Backup -> restore into fresh stack | `pg_dump -Fc` + tar of storage volume; restore into project `cwrest` on port 3001 | works | 52 conversations on both; login OK; attachment byte-identical |
| Telegram, email (IMAP/SMTP), WhatsApp Cloud API, Facebook/Instagram | - | NOT TESTED | needs owner accounts; to be done on the owner's device |
| Dashboard, Settings (inboxes, agents, teams, labels, custom attributes, automation, bots, macros, canned responses, integrations), Reports, Contacts, Campaigns, Help Center | headless login + screenshots (`explore/shots/`, git-ignored) | works | all pages load, no JS errors. Help Center opens "create portal" (works, empty) |
| Super Admin console `/super_admin` | same credentials | works | Dashboard counts, Accounts, Users, Agent Bots, Platform Apps, Sidekiq Dashboard, Instance Health, Push Diagnostics - Sidekiq Dashboard and Instance Health are useful for Phase 4 monitoring |
| Integrations available in CE | Settings -> Integrations | listed | Webhooks, Dashboard Apps, OpenAI (api_key only), Dialogflow, Google Translate, Cloudflare RealtimeKit. No Captain, no Slack/Linear etc. shown (need env keys) |
| First-run onboarding | fresh DB | works | `db:chatwoot_prepare` sets Redis flag `CHATWOOT_INSTALLATION_ONBOARDING`; until completed every page redirects to `/installation/onboarding` (public form that creates the Super Admin + account, with a pre-ticked newsletter box). Kit must complete it immediately via script (or delete the flag after creating admin by `rails runner`) |
| Bengali UI | app ships `bn` locale (57 locales total) | NOT CONFIRMED | switching language was not confirmed in the headless test; needs a manual check on the owner's device |
| Macros, automation rule creation, teams, campaigns, CSAT, mobile app, ngrok | - | NOT TESTED | pages open; creating items by hand deferred (Phase 7 packs will create them via API) |

## 3. Performance on this machine
| Task | Input size | Time | Notes |
|---|---|---|---|
| Idle, 4 containers | fresh stack | - | rails 406 MB, sidekiq 476 MB, postgres 124 MB, redis 5 MB (~1.0 GB total) |
| 50 conversations via public API | 50 contacts+conversations+messages | 9.6 s | rails 408 MB, sidekiq 563 MB, postgres 133 MB (~1.1 GB); all 50 bot webhooks delivered |
| pg_dump + storage tar | 52 conversations, 1 attachment | seconds | db.dump 384 KB |
| Restore into fresh stack | same | ~1.5 min incl. boot | verified |

## 4. Output quality
Not applicable yet (no UI review done); bot answer quality is Phase 8.

## 5. Limits & risks found
- **SSRF guard blocks the planned bot wiring.** Chatwoot refuses webhook URLs whose host has no public IP ("Hostname ... has no public ip addresses"), so `http://aibot:8000/...` fails by default. Supported fix: env `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` (found in `lib/safe_fetch.rb`; no upstream code change). Risk: it relaxes the same guard for avatar/media fetching on that install. Mitigation: only on dedicated client stacks, no untrusted users can set outgoing URLs (Super Admin/admin only). Recorded as ADR-012.
- When the bot is unreachable Chatwoot flips a pending conversation to open (unless `keep_pending_on_bot_failure` is set), so a bot outage degrades to "human handles it" - good fail-safe.
- Webhook has retry behaviour for HTTP 429/500 from the bot (`RETRYABLE_AGENT_BOT_STATUSES`); aibot should return 200 quickly and process asynchronously.
- Ports 5432/6379/3000 are published on 127.0.0.1 in the official compose; our rendered compose must drop 5432/6379.

## 5b. Channel findings (Phase 6, task 6.1, verified live on a demo stack, v4.18.0)
- Widget visitor flow works end to end: `POST /api/v1/widget/config?website_token=` returns `website_channel_config.auth_token`; `POST /api/v1/widget/messages` with header `X-Auth-Token` creates a conversation. Conversations/contacts are deletable through the API (used for clean-up).
- The inbox API (administrator token) shows IMAP/SMTP settings incl. passwords for email inboxes, `bot_name` (not the token) for Telegram, `provider_config` incl. `webhook_verify_token` for WhatsApp, and `reauthorization_required` only for Facebook, Instagram, TikTok, WhatsApp embedded sign-up, Google/Microsoft email.
- Webhooks: `POST /webhooks/telegram/:bot_token`; `GET|POST /webhooks/whatsapp/:phone` (right verify token echoes the challenge, wrong one gives 401); `/webhooks/instagram` (wrong token 401); Facebook on `/bot` (wrong token still returns 200, so it cannot prove anything).
- Telegram and WhatsApp-cloud inbox creation call the real services, so the sandbox cannot create them (api.telegram.org, graph.facebook.com unreachable). The demo uses simulated inboxes written to the database.
- Instagram/Facebook app id/secret and verify token are installation configs readable by name.

## 5c. Pack findings (Phase 7, task 7.1, verified live on a demo stack, v4.18.0)
- **Saved replies** `GET|POST /api/v1/accounts/1/canned_responses` (body `{"canned_response":{"short_code","content"}}`): list is a plain JSON array; a duplicate `short_code` returns 422 "Short code has already been taken".
- **Labels** `/labels` (body `{title, description, color, show_on_sidebar}`): list is `{"payload":[...]}`; a duplicate title returns 422 "Title has already been taken".
- **Automation rules** `/automation_rules`: list and PATCH answer are wrapped in `{"payload": ...}`, create answers the bare object. A rule with several `content contains <word>` conditions joined by `query_operator: "OR"` (last one `null`) works. Names are not unique.
- **Conditions are one flat chain without brackets**, so the pack uses only content keywords joined by OR (no "incoming only" condition); a team member's own message with the word also tags the chat.
- **Keyword rule really fires**: visitor message "দাম কত?" -> conversation labelled `price`; "How much is the PRICE" -> `price` (case does not matter); "hello there" -> no label.
- **Inbox settings** `PATCH /inboxes/:id` take `greeting_enabled`, `greeting_message`, `out_of_office_message`, `csat_survey_enabled`, `working_hours_enabled`, `timezone`, `working_hours[]`. Working hours listed for a new inbox: 7 rows, hours enabled = false (Sunday closed, Monday-Friday 9-17, Saturday closed). A PATCH with fewer than seven days changes only the days sent. A closed day can come back with hours 0/0 or null, so only `closed_all_day` counts. An unknown timezone returns 422 "Timezone is not included in the list"; `Asia/Dhaka` is accepted.
- Real shapes are saved in `opskit/tests/fixtures/pack_live_shapes.json` (fictional data).

## 6. Matches the SPEC? (agent's view)
Mostly yes. Answers to *(verify)* items so far:
- CE image tag format: `chatwoot/chatwoot:v4.18.0-ce` exists.
- Health route: `GET /api`.
- Agent bot registration: Application API `POST /api/v1/accounts/:id/agent_bots` {name, outgoing_url} -> returns `access_token` (bot API token) and `secret` (webhook HMAC). Attach: `POST /inboxes/:id/set_agent_bot {"agent_bot":<id>}`.
- Webhook headers: `X-Chatwoot-Delivery`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Signature: sha256=HMAC_SHA256(secret, "<ts>.<raw body>")`. aibot should verify it in addition to the secret path token.
- Events delivered to the bot: `message_created` (incoming AND the bot's own outgoing echo), `conversation_updated`, `conversation_opened`, `conversation_status_changed`. aibot must act only on `message_created` with `message_type == "incoming"`, `private == false`, and `conversation.status == "pending"`.
- New conversation on a bot inbox starts `pending` with assignee type AgentBot (confirmed).
- Reply: bot token, `POST /conversations/:id/messages`, `message_type: outgoing` -> 200.
- Handoff: bot token `POST /conversations/:id/toggle_status {"status":"open"}` -> status open, bot assignee cleared; label via `POST /conversations/:id/labels`. Team assignment call not yet tested.
- Payload sample: `docs/captures/agent-bot-message_created.json`.
**Mismatch found:** SPEC 13.1 private-network webhook (see section 5) - needs `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`. Not a blocker; ADR-012.
- **Branding is data, not code:** branding configs are locked in the CE UI, env vars do not override them on an initialised DB, but a DB-row update works and survives `db:chatwoot_prepare` (tested, then restored). See `docs/ADDONS.md`.
- **Phase 2 findings (verified on v4.18.0-ce):** (1) user passwords must contain upper + lower + digit + special character, so a plain hex password fails user creation; (2) an EMPTY `SMTP_USERNAME` still makes Chatwoot try to log in to the SMTP server (Ruby treats "" as set), so login lines must be omitted when unused; (3) the CE image has `wget` and `ruby` but no `curl`: health checks use `wget`; (4) `rails runner -` reads the script from stdin, which keeps secrets out of command lines; (5) the websocket (`/cable`) answers 101 through Caddy over HTTP/1.1 (curl's HTTP/2 attempt gets 404); (6) the official compose's extra `base` service is not needed.
- **Phase 3 finding (verified):** through Caddy the API token header spelled `api_access_token` (as in Chatwoot docs) is silently DROPPED and Rails answers 401 with no DB lookup; the same header spelled `api-access-token` works (200). Direct to `rails:3000` both spellings work. So everything we call through the public HTTPS URL (channel-health poller, reports, client scripts) must send `api-access-token`; aibot talks to `http://rails:3000` internally. Tell clients using the API via the public URL.
- **Phase 3 findings (verified):** (1) restoring with a DIFFERENT `SECRET_KEY_BASE`: password login 200, API token 200, but previously issued signed attachment URLs return 404 (new ones work) and existing sessions are invalid; (2) `encrypts` on channel secrets (email IMAP/SMTP passwords, WhatsApp token, etc.) only applies when `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY/DETERMINISTIC_KEY/KEY_DERIVATION_SALT` are set; we do not set them yet, so channel credentials sit in PLAINTEXT inside `db.dump`; if we ever set them they must be added to the escrow; (3) a full backup + restore test of a small demo takes about 1 minute; backup folder ~0.4 MB.
- **Phase 4 findings (verified live):** (1) Sidekiq state in Redis: set `processes` (one identity per worker), hash `<identity>` with `beat` (epoch float, refreshed ~5 s), `busy`, `rss`; a graceful stop REMOVES the entry, a crash (SIGKILL) leaves it with a stale `beat`; so "alive" = a process whose beat is < 60 s old; (2) queues are listed in set `queues`; oldest job age = now - `enqueued_at` of `LINDEX queue:<name> -1` (JSON); ignore `sidekiq-alive-*` queues; `retry`, `dead`, `schedule` are sorted sets (`ZCARD`); (3) `reauthorization_required` appears in the inbox API only for Facebook, Instagram, TikTok, WhatsApp (embedded sign-up) and Google/Microsoft email, and only for administrator users; plain IMAP/SMTP email, Telegram, widget, API inboxes never show it; (4) `docker compose exec` inside a `while read` loop swallows the loop's stdin (bug found and fixed: always `</dev/null`); (5) `redis-cli` reads the password from env `REDISCLI_AUTH`, so it never appears on a command line.
- **Phase 5 findings (verified live, v4.17.1-ce -> v4.18.0-ce):** (1) 3 migrations; schema_migrations went 177 -> 180 rows, version 20260814000000 -> 20260831000000; `schema_migrations.version` is a text column (use `coalesce(max(version),'0')`); (2) rehearsal on a copy (restore + migrations + smoke) took 93 s; live upgrade ~70 s; automatic rollback with database restore ~1 min; (3) `DROP DATABASE chatwoot WITH (FORCE)` followed by `pg_restore` works for the rollback; (4) the official production compose and the required env keys did not change between the two releases (one new optional key, SLACK_SIGNING_SECRET); (5) conversations can be deleted through the API (admin), which lets the smoke test clean up after itself.
- **BYOK for built-in AI assist:** the OpenAI integration only asks for an `api_key` in the UI, but the code reads an installation setting `CAPTAIN_OPEN_AI_ENDPOINT` (lib/integrations/llm_base_service.rb) so a custom OpenAI-compatible endpoint may be possible without patching (not tested). Our bot does not depend on it.
Still open: the other *(verify)* items (sidekiq health method, channel health fields, Reports API, enterprise-free image proof) belong to later steps.

## 7. Questions for the owner (only if blocked or unclear)
