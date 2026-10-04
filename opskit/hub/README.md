# ops-hub (not used yet)

Decision ADR-016 (2026-10-04): there is **no ops-hub running**, so alerts go **directly to Telegram** from each client's server.
If a hub is set up later (Activepieces alert-router + Uptime Kuma), set `OPSKIT_HUB_URL` (+ `OPSKIT_HUB_TOKEN`) on the host:
every alert is then also POSTed as JSON, and a heartbeat is sent after backups and restore tests.

Alert payload (written to `opskit/alerts/outbox/*.json` and POSTed when a hub URL is set):
`{"severity":"info|warn|critical","client_id":"demo","check":"sidekiq","summary":"<=300 chars, no message text","timestamp":"2026-10-04T06:00:00Z"}`
Heartbeat payload: `{"type":"heartbeat","client_id":"demo","name":"backup|restore_test","timestamp":"..."}`.
The hub-side flows/monitors are NOT written or verified (no hub to test against).

## Server-dead detection (important)
A watcher running ON the server cannot tell you the server itself died. Until a hub exists, use an external "dead-man's switch":
create a free check at healthchecks.io or UptimeRobot (heartbeat monitor) and put its ping URL in `OPSKIT_HEARTBEAT_URL` on the host;
`opskit monitor run <id>` pings it every 5 minutes, and the service messages you when the pings stop.
