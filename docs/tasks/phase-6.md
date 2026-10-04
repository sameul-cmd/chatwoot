# Phase 6 — Channel runbooks & checkers (Improvement 5)

Spec: SPEC Section 11, Section 17 (Phase 6), `.claude/CLAUDE.md` "Packs & channels rules".
**Accept (from SPEC):** `channels check` reports PASS for widget/Telegram/email on the demo client and FAIL for a deliberately broken inbox with a clear fix hint; the WhatsApp runbook walked end to end with a Meta test number if available (else documented as pending the owner's Meta account).

## What this phase is, in plain words
A "channel" is a way customers reach the client: the website chat bubble, email, Telegram, WhatsApp, Facebook/Instagram. This phase delivers (1) simple step-by-step guides for connecting each one (who creates what account, what to copy where), (2) a command that **tests** each connected channel and says PASS / WARN / FAIL with a plain fix hint, and (3) a command that prints the client's own to-do list (what *they* must create: Meta account, domain records, mailbox), in English and Bangla.

## Facts this phase relies on (checked in Chatwoot v4.18.0 code, 2026-10-04)
- Inbox types creatable through the API: `web_widget, api, email, line, telegram, whatsapp, sms`. Facebook/Instagram are connected through Chatwoot's own Meta login flow, not a plain API call.
- Webhook routes Chatwoot listens on: `POST /webhooks/telegram/<bot_token>`, `GET+POST /webhooks/whatsapp/<phone_number>` (GET = Meta's verification handshake using the inbox's `webhook_verify_token`), `GET+POST /webhooks/instagram`, Facebook Messenger on `/bot`, email forwarding through Action Mailbox (needs `MAILER_INBOUND_EMAIL_DOMAIN`).
- The inbox API (administrator token) exposes: `website_token` (widget), `bot_name` (Telegram, but NOT the bot token), WhatsApp `provider_config` incl. `webhook_verify_token`, email IMAP/SMTP settings incl. login (and password for administrators), and `reauthorization_required` only for Facebook, Instagram, TikTok, WhatsApp embedded sign-up and Google/Microsoft email.
- Telegram inbox creation and WhatsApp Cloud credential validation call Telegram/Meta servers directly (hard-coded URLs, no override). **This sandbox cannot reach api.telegram.org, graph.facebook.com or whatsapp.com** (tested: connection fails). So here I can prove everything that happens on OUR side (inbox exists, webhook endpoint reachable over HTTPS, verification handshake correct, email login) but not the real Telegram/Meta side: that part is verified on the owner's device.
- Phase 3 finding: through Caddy the API header must be `api-access-token`.

## Open questions for the owner (plain words; defaults in bold)
1. **Guides written without real accounts.** I cannot log in to Meta/Telegram from here, so the guides are written from Chatwoot's code plus Meta's and Telegram's public documentation (web search), and every step is marked "not yet tried with a real account" until you or a real client has done it. **Default: OK.**
2. **Bangla.** **Default:** guides in simple English; the client's to-do list (`channels plan`) is printed in English and Bangla, with the Bangla marked "review needed" until you proofread it.
3. **Testing email without sending email.** **Default:** the email test only *logs in* to the mailbox (IMAP) and the outgoing server (SMTP) to prove the password works; it sends nothing. A real test email (`--send-test`) goes only to the client's own address and only if you add the flag.
4. **Read-only look at Telegram/Meta.** To say "Telegram can reach your server" the checker asks Telegram (`getWebhookInfo`) and Meta for status using the client's own token; it never changes anything and never prints the token. On the server it reads the Telegram token from the database read-only (Chatwoot does not show it through the API). **Default: yes.** If Telegram or Meta cannot be reached from the server the result is WARN ("could not reach"), not FAIL.
5. **WhatsApp method.** **Default:** the manual way with a permanent access token from the *client's own* Meta Business account (official Cloud API only, never QR-code tools). Chatwoot's one-click "embedded sign-up" needs a Meta app registered for Chatwoot itself and is left out for now.
6. **Which channels get a deep test in the sandbox.** Website widget, API inbox and email (with pretend mail servers) can be proven end to end here; Telegram, WhatsApp and Instagram are proven on our side (webhook endpoint, handshake) with simulated inboxes, and the real-service side is listed as "to verify on your device". **Default: OK.**
7. **Does `channels check` run by itself?** **Default:** no, you run it on demand (setup day, after a channel problem). The 15-minute monitor from Phase 4 keeps watching "needs re-connection" automatically.

## Tasks

### [ ] 6.1 — Verify the facts live, record what a demo can and cannot do
- **Goal:** on a running demo: create a widget, API and email inbox through the API; read what the inbox API returns per type; see which inboxes can be simulated offline (Telegram / WhatsApp / Instagram via the database with validations skipped, as Chatwoot's own code allows). Record in EXPLORATION_REPORT.

### [ ] 6.2 — Checker core (`lib/channels.sh`) and the PASS/WARN/FAIL table
- **Goal:** list inboxes with the monitoring user's token; one checker per type; each returns rows `inbox | check | PASS/WARN/FAIL | fix hint`; hints live in one data file; exit code non-zero on any FAIL; never prints tokens, passwords or message text.
- **Tests:** bats with a fake API: table format, exit codes, redaction

### [ ] 6.3 — Website widget checker
- **Goal:** widget page and script reachable over HTTPS, WebSocket works, and a **real round trip through the widget's own REST API** (create visitor, send a message, see the conversation, delete it again).
- **Tests:** live in the selftest; fake-API bats for the decision logic

### [ ] 6.4 — API inbox checker
- **Goal:** public API round trip (create contact + conversation + message, then clean up), same helper as the smoke test.

### [ ] 6.5 — Email checker (IMAP/SMTP + forwarding)
- **Goal:** logs in to IMAP and SMTP with the inbox's own settings (python helper, TLS handled, results only "ok / wrong password / cannot connect / certificate problem"); for forwarding inboxes checks the forwarding address exists and the inbound-email setting is on; optional `--send-test`.
- **Tests:** bats with pretend IMAP and SMTP servers (small Python programs in `tests/`): good login = PASS, wrong password = FAIL with hint, unreachable host = FAIL, certificate error = WARN with hint

### [ ] 6.6 — Telegram checker
- **Goal:** inbox exists and shows its bot name; Chatwoot's webhook endpoint answers over HTTPS; optional read-only `getWebhookInfo` (last error, pending count); WARN if Telegram cannot be reached.
- **Tests:** pretend Telegram server (extend `tests/fake_telegram.py`); live endpoint check on the demo

### [ ] 6.7 — WhatsApp Cloud API checker
- **Goal:** Meta's verification handshake performed by us against our own webhook (right token = challenge echoed, wrong token = refused), inbox settings complete (phone number, phone number id, business account id, token present), optional read-only Meta status call, 24-hour-window reminder in the output.
- **Tests:** live handshake on a simulated inbox; fake Meta server for the optional call

### [ ] 6.8 — Facebook / Instagram checker
- **Goal:** `reauthorization_required`, the Meta app settings present in the server environment (`FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN`, `IG_VERIFY_TOKEN`), verification handshake on `/webhooks/instagram` and `/bot`.
- **Tests:** live handshake; env-missing cases

### [ ] 6.9 — `opskit channels plan <id>` (client to-do list, English + Bangla)
- **Goal:** from `client.yaml` `channels[]` + domain print exactly what the CLIENT must create or verify per channel (Meta Business account and verification, WhatsApp number not on the WhatsApp app, Facebook page admin rights, mailbox app password / IMAP on, DNS records, Telegram bot) with owner/client split; Bangla lines marked `review_required` until you approve them.
- **Tests:** bats: every channel type produces its items; output has no secrets

### [ ] 6.10 — The five runbooks (`docs/runbooks/`)
- **Goal:** `website-widget.md`, `email.md`, `telegram.md`, `whatsapp-cloud-api.md`, `facebook-instagram.md`: plain-language numbered steps, who does what, costs (WhatsApp billed to the client's Meta account), common problems and the fix, each step marked verified/not yet verified. Facts from code + public docs (web search); official-doc links.

### [ ] 6.11 — Broken-inbox demo and selftest v5 (acceptance)
- **Goal:** selftest adds: widget + API + email PASS; Telegram/WhatsApp/Instagram PASS on our side; a deliberately broken email inbox (wrong password) and a WhatsApp inbox with a wrong verify token FAIL with clear hints.
- **Acceptance:** all rows as expected in `opskit selftest`

### [ ] 6.12 — Docs, verification, security review
- **Goal:** update PROGRESS/ASSUMPTIONS/ENVIRONMENT; `/verify-phase`; security review (probes are read-only, tokens/passwords never printed or logged, hints never contain secrets).
