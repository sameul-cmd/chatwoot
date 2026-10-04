# Runbook: monitoring and alerts

Plain-language guide. Each client's server watches itself and messages **your Telegram**. (No ops-hub: ADR-016.)

## One-time setup per client (on the server)
1. In Telegram talk to @BotFather: `/newbot`, copy the token (looks like `123456:ABC...`).
2. Send any message to your new bot, then open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and note the number after `"chat":{"id":`.
3. `TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... opskit/bin/opskit alerts set-telegram <id>` - saves them privately.
4. `opskit/bin/opskit alerts test <id>` - you should get a test message.
5. Strongly recommended: make a free check at healthchecks.io or UptimeRobot (heartbeat type) and set `OPSKIT_HEARTBEAT_URL` on the host. A server cannot report its own death; this service messages you when the pings stop.

## What runs and when
- Every 5 minutes: `opskit monitor run <id>` (website, services, background jobs, queue delay, failed jobs, disk, memory, restarts, certificate, bot).
- Every 15 minutes: `opskit monitor run <id> --channels` (chat channels that need re-connecting).
- Look now: `opskit monitor status <id>`.
- (The cron lines are generated in `opskit/clients/<id>/monitor.cron`; installing them on a real server is Phase 11.)

## Messages you will see and what to do
| Message | Meaning | What to do |
|---|---|---|
| 🔴 CRITICAL Website | the site or login page does not answer | check `docker compose -p <id> ps` and the server; call the client if it lasts |
| 🔴 CRITICAL Services | a container is not running | `docker compose -p <id> up -d`; look at the logs of the named service |
| 🔴 CRITICAL Background jobs (Sidekiq) | no worker: emails, notifications, bot replies are not processed | restart sidekiq: `docker compose -p <id> restart sidekiq` |
| 🟠 WARNING Job queue delay (🔴 over 15 min) | jobs wait too long | check Sidekiq and the server load |
| 🟠 WARNING Failed jobs | many jobs failing | look at the Sidekiq dashboard in Super Admin |
| 🟠 WARNING Disk space (🔴 over 95%) | disk filling up | remove old backups/logs or grow the disk |
| 🟠 WARNING Memory / Restarts | memory pressure or crash loop | look at which container restarts |
| 🟠 WARNING HTTPS certificate | expires soon | check Caddy and DNS; 🔴 under 3 days |
| 🔴 CRITICAL Channel N | a connected channel (e.g. Google email, Facebook) needs re-connecting | the client logs in and re-connects it (see the channel runbooks, Phase 6) |
| 🔁 STILL CRITICAL | a critical problem is still open after 2 hours | same as above |
| ✅ RESOLVED | the problem is gone | nothing |

## Rules the watcher follows
- The same alert is never repeated within 30 minutes; critical ones are repeated once every 2 hours.
- Warnings between 22:00 and 08:00 (client's time) wait and arrive as one summary; critical ones never wait.
- If Telegram is unreachable the alert is kept in `opskit/alerts/outbox/` and sent in the next cycle.
- Alerts never contain customer messages, contact data or secrets.

## Limits (be aware)
Channel checks only cover channel types where Chatwoot reports "needs re-connection" (Facebook, Instagram, TikTok, WhatsApp embedded sign-up, Google/Microsoft email). Plain email (IMAP/SMTP), Telegram, widget and API inboxes are covered by the Phase 6 checkers. Real Telegram delivery, real-host cron, real certificate expiry: NOT VERIFIED until Phase 11 / your device.
