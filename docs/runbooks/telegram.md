# Runbook: Telegram inbox

**Status:** our side verified in the sandbox with a simulated inbox (webhook endpoint answers, pretend-Telegram status checks). Creating a real bot and receiving a real message: **not yet tried** (the sandbox cannot reach Telegram; do it on your device).

## Who does what
- **Client:** creates the bot with their own Telegram account (the bot belongs to them) and gives us the token privately.
- **Us:** adds the inbox and tests.

## Steps
1. (Client) In Telegram open **@BotFather**, send `/newbot`, choose a display name and a username ending in `bot`. BotFather replies with a **token** (looks like `123456789:ABC...`). Keep it private: anyone with it can control the bot.
2. (Us) The client's domain must already work over HTTPS (Telegram only sends to HTTPS addresses with a valid certificate). Check with `opskit monitor status <id>`.
3. (Us) Settings > Inboxes > Add Inbox > **Telegram**, paste the token. Chatwoot registers the webhook with Telegram itself.
4. (Us) `opskit/bin/opskit channels check <id>`: rows "webhook endpoint", "Telegram -> this server" and "Telegram delivery errors" must say PASS. (The Telegram view needs the server to reach Telegram; otherwise it is a WARN.)
5. (Client) Send a message to the bot from their own phone; it must appear in Chatwoot; reply from Chatwoot.

## Common problems
| Symptom | Fix |
|---|---|
| FAIL "Telegram sends to <other host>" | the webhook points elsewhere (old server): open the inbox and save again, or remove and re-add the bot |
| FAIL "last error: ... 502 / SSL" | HTTPS/certificate/domain problem: fix it, then save the inbox again |
| FAIL "bot token rejected" | token revoked: create a new one with @BotFather (`/token`) and update the inbox |
| One bot token can only be used in ONE place | do not reuse the same bot on two servers |

## Costs
None.

## Facts checked in code
Chatwoot sets the webhook to `<server address>/webhooks/telegram/<bot token>` (`app/models/channel/telegram.rb`); the inbox API shows the bot name but never the token.

## Source
Telegram Bot documentation (core.telegram.org/bots): not opened from the sandbox; steps are the long-standing BotFather flow. **Verify.**
