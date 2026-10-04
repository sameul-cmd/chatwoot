#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  export OPSKIT_ALERT_DIR="$BATS_TEST_TMPDIR/outbox"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT_ROOT/bin/opskit" client new demo --domain chat.demo.localhost --name Demo --local >/dev/null 2>&1
  for l in log validate secrets render deploy alert alert_state health channels_health notify monitor; do . "$OPSKIT_ROOT/lib/$l.sh"; done
  LOG="$BATS_TEST_TMPDIR/tg.log"
  : >"$LOG"
  python3 "$BATS_TEST_DIRNAME/fake_telegram.py" "$BATS_TEST_TMPDIR/port" "$LOG" &
  FAKE_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/port" ] && break; sleep 0.1; done
  export TELEGRAM_API_BASE="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")"
  printf 'TELEGRAM_BOT_TOKEN=123456:ABCDEFGHIJKLMNOPQRSTUVWX\nTELEGRAM_CHAT_ID=42\n' >"$OPSKIT_CLIENTS_DIR/demo/alerts.env"
  RESULTS="$BATS_TEST_TMPDIR/results"
  health_checks() { cat "$RESULTS"; }
  # 2026-10-04 06:00 UTC = 12:00 in Dhaka (not quiet); 16:00 UTC = 22:00 Dhaka (quiet)
  T0="$(date -u -d '2026-10-04 06:00:00 UTC' +%s)"
  TQ="$(date -u -d '2026-10-04 17:00:00 UTC' +%s)"
}

teardown() { kill "$FAKE_PID" 2>/dev/null || true; }

run_at() { OPSKIT_NOW="$1" monitor_run demo "${@:2}"; }
sent() { wc -l <"$LOG" | tr -d ' '; }
text() { jq -r .text "$LOG" | sed -n "${1}p"; }

@test "stopping Sidekiq: one critical message at the first check, none for repeats" {
  echo "sidekiq|critical|no Sidekiq worker is running" >"$RESULTS"
  run_at "$T0"
  [ "$(sent)" = "1" ]
  [[ "$(text 1)" == *"CRITICAL [demo] Background jobs (Sidekiq)"* ]]
  run_at "$((T0 + 300))"
  run_at "$((T0 + 600))"
  [ "$(sent)" = "1" ]
}

@test "a critical still open after 2 hours gets one reminder" {
  echo "sidekiq|critical|down" >"$RESULTS"
  run_at "$T0"
  run_at "$((T0 + 7199))"
  [ "$(sent)" = "1" ]
  run_at "$((T0 + 7200))"
  [ "$(sent)" = "2" ]
  [[ "$(text 2)" == *"STILL CRITICAL"* ]]
  run_at "$((T0 + 7500))"
  [ "$(sent)" = "2" ]
}

@test "recovery sends exactly one resolved message" {
  echo "sidekiq|critical|down" >"$RESULTS"
  run_at "$T0"
  echo "sidekiq|ok|fine" >"$RESULTS"
  run_at "$((T0 + 600))"
  [ "$(sent)" = "2" ]
  [[ "$(text 2)" == *"RESOLVED [demo] Background jobs (Sidekiq)"* ]]
  run_at "$((T0 + 900))"
  [ "$(sent)" = "2" ]
}

@test "flapping inside 30 minutes is deferred, then sent once the window has passed" {
  echo "site|critical|down" >"$RESULTS"; run_at "$T0"
  echo "site|ok|up" >"$RESULTS"; run_at "$((T0 + 300))"
  [ "$(sent)" = "2" ]
  echo "site|critical|down" >"$RESULTS"; run_at "$((T0 + 600))"
  [ "$(sent)" = "2" ]
  run_at "$((T0 + 300 + 1800))"
  [ "$(sent)" = "3" ]
}

@test "a warning in quiet hours is held, then sent once as a summary" {
  printf 'disk|warn|disk is 88%% full\nmemory|warn|9%% of memory available\n' >"$RESULTS"
  run_at "$TQ"
  [ "$(sent)" = "0" ]
  run_at "$((TQ + 600))"
  [ "$(sent)" = "0" ]
  run_at "$(date -u -d '2026-10-05 03:00:00 UTC' +%s)"
  [ "$(sent)" = "1" ]
  [[ "$(text 1)" == *"WARNINGS [demo]"* ]]
  jq -r .text "$LOG" | grep -q "Disk space"
  jq -r .text "$LOG" | grep -q "Memory"
  run_at "$(date -u -d '2026-10-05 03:30:00 UTC' +%s)"
  [ "$(sent)" = "1" ]
}

@test "a critical is never held by quiet hours" {
  echo "site|critical|down" >"$RESULTS"
  run_at "$TQ"
  [ "$(sent)" = "1" ]
}

@test "a warning that clears during quiet hours disappears without any message" {
  echo "disk|warn|88%" >"$RESULTS"; run_at "$TQ"
  echo "disk|ok|fine" >"$RESULTS"; run_at "$((TQ + 600))"
  run_at "$(date -u -d '2026-10-05 03:00:00 UTC' +%s)"
  [ "$(sent)" = "0" ]
}

@test "warning escalating to critical is sent immediately" {
  echo "queue_latency|warn|6 min" >"$RESULTS"; run_at "$T0"
  echo "queue_latency|critical|16 min" >"$RESULTS"; run_at "$((T0 + 300))"
  [ "$(sent)" = "2" ]
  [[ "$(text 2)" == *"CRITICAL"* ]]
}

@test "Telegram down: nothing is lost, the alert is delivered on the next cycle" {
  echo "site|critical|down" >"$RESULTS"
  TELEGRAM_API_BASE="http://127.0.0.1:9" run run_at "$T0"
  [ "$status" -eq 3 ]
  [[ "$output" == *"HTTP 000"* ]]
  [[ "$output" != *"HTTP 000000"* ]]
  [ "$(sent)" = "0" ]
  [ -n "$(ls "$OPSKIT_ALERT_DIR")" ]
  run_at "$((T0 + 300))"
  [ "$(sent)" = "1" ]
}

@test "no Telegram settings: alerts go to the outbox, no crash" {
  rm -f "$OPSKIT_CLIENTS_DIR/demo/alerts.env"
  echo "site|critical|down" >"$RESULTS"
  run run_at "$T0"
  [ "$(sent)" = "0" ]
  [[ "$output" == *"outbox only"* ]]
  [ -n "$(ls "$OPSKIT_ALERT_DIR")" ]
}

@test "a simulated disconnected inbox is reported, then resolves when fixed" {
  printf 'channels_api|ok|readable\nchannel-7|critical|Inbox "Support Email" (Email) needs to be re-connected\n' >"$RESULTS"
  channels_health() { cat "$RESULTS"; }
  run_at "$T0" --channels
  [ "$(sent)" = "1" ]
  [[ "$(text 1)" == *'Inbox "Support Email" (Email) needs to be re-connected'* ]]
  printf 'channels_api|ok|readable\nchannel-7|ok|connected\n' >"$RESULTS"
  run_at "$((T0 + 900))" --channels
  [ "$(sent)" = "2" ]
  [[ "$(text 2)" == *"RESOLVED"* ]]
}

@test "an inbox that disappears resolves its alert" {
  channels_health() { cat "$RESULTS"; }
  printf 'channels_api|ok|r\nchannel-9|critical|needs re-connect\n' >"$RESULTS"
  run_at "$T0" --channels
  printf 'channels_api|ok|r\n' >"$RESULTS"
  run_at "$((T0 + 900))" --channels
  [ "$(sent)" = "2" ]
}

@test "alert text never contains the token or message text, and the outbox file has the fields" {
  echo "sidekiq|critical|down" >"$RESULTS"
  run_at "$T0"
  ! grep -rq "ABCDEFGHIJKLMNOPQRSTUVWX" "$LOG" "$OPSKIT_ALERT_DIR"
  f="$(ls "$OPSKIT_ALERT_DIR"/*.json | head -n1)"
  [ "$(jq -r .severity "$f")" = "critical" ]
  [ "$(jq -r .client_id "$f")" = "demo" ]
}

@test "the heartbeat URL is pinged on host runs only" {
  : >"$BATS_TEST_TMPDIR/hb.log"
  python3 "$BATS_TEST_DIRNAME/fake_telegram.py" "$BATS_TEST_TMPDIR/hbport" "$BATS_TEST_TMPDIR/hb.log" &
  HB_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/hbport" ] && break; sleep 0.1; done
  echo "site|ok|fine" >"$RESULTS"
  channels_health() { cat "$RESULTS"; }
  export OPSKIT_HEARTBEAT_URL="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/hbport")/ping/x"
  run_at "$T0" --channels
  [ ! -s "$BATS_TEST_TMPDIR/hb.log" ]
  kill "$HB_PID"
}

@test "status lists the known checks" {
  echo "site|critical|down" >"$RESULTS"
  run_at "$T0"
  run monitor_status demo
  [[ "$output" == *"Website"* ]]
  [[ "$output" == *"critical"* ]]
}

@test "inbox JSON parsing: connected, needs re-connection, hostile names" {
  json='{"payload":[{"id":1,"name":"Web","channel_type":"Channel::WebWidget"},{"id":2,"name":"Mail\u0007box","channel_type":"Channel::Email","reauthorization_required":true}]}'
  run bash -c ". '$OPSKIT_ROOT/lib/log.sh'; . '$OPSKIT_ROOT/lib/channels_health.sh'; printf '%s' '$json' | parse_inboxes_json"
  [[ "$output" == *'channel-1|ok|Inbox "Web" (WebWidget) connected'* ]]
  [[ "$output" == *'channel-2|critical|Inbox "Mailbox" (Email) needs to be re-connected'* ]]
}

@test "render writes the monitoring cron lines" {
  "$OPSKIT_ROOT/bin/opskit" client render demo >/dev/null 2>&1
  f="$OPSKIT_CLIENTS_DIR/demo/monitor.cron"
  grep -qE '^\*/5 \* \* \* \* root flock -n /var/lock/opskit-monitor-demo.lock .* monitor run demo ' "$f"
  grep -qE '^\*/15 \* \* \* \* root flock .* monitor run demo --channels ' "$f"
  grep -q '^CRON_TZ=Asia/Dhaka$' "$f"
}
