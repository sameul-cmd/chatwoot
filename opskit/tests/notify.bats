#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR/demo"
  . "$OPSKIT_ROOT/lib/render.sh"
  . "$OPSKIT_ROOT/lib/notify.sh"
  LOG="$BATS_TEST_TMPDIR/tg.log"
  : >"$LOG"
  python3 "$BATS_TEST_DIRNAME/fake_telegram.py" "$BATS_TEST_TMPDIR/port" "$LOG" &
  FAKE_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/port" ] && break; sleep 0.1; done
  export TELEGRAM_API_BASE="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")"
  ENVF="$OPSKIT_CLIENTS_DIR/demo/alerts.env"
  printf 'TELEGRAM_BOT_TOKEN=123456:ABCDEFGHIJKLMNOPQRSTUVWX\nTELEGRAM_CHAT_ID=42\n' >"$ENVF"
}

teardown() { kill "$FAKE_PID" 2>/dev/null || true; }

@test "a message reaches Telegram with the right chat and text" {
  run telegram_send "$ENVF" "[CRITICAL] demo: test"
  [ "$status" -eq 0 ]
  [ "$(jq -r .chat_id "$LOG")" = "42" ]
  [ "$(jq -r .text "$LOG")" = "[CRITICAL] demo: test" ]
}

@test "the token never appears in output or logs" {
  run telegram_send "$ENVF" "hello"
  ! printf '%s' "$output" | grep -q "ABCDEFGHIJKLMNOPQRSTUVWX"
  printf 'TELEGRAM_BOT_TOKEN=123456:badtokenXXXXXXXXXXXXXXXXXX\nTELEGRAM_CHAT_ID=42\n' >"$ENVF"
  run telegram_send "$ENVF" "hello"
  [ "$status" -ne 0 ]
  ! printf '%s' "$output" | grep -q "badtoken"
}

@test "a rejected token fails with a clear status" {
  printf 'TELEGRAM_BOT_TOKEN=123456:badtokenXXXXXXXXXXXXXXXXXX\nTELEGRAM_CHAT_ID=42\n' >"$ENVF"
  run telegram_send "$ENVF" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTTP 401"* ]]
}

@test "an unreachable Telegram returns non-zero" {
  TELEGRAM_API_BASE="http://127.0.0.1:9" run telegram_send "$ENVF" "hello"
  [ "$status" -ne 0 ]
}

@test "missing settings: not sent, not a crash" {
  run telegram_send "$OPSKIT_CLIENTS_DIR/demo/none.env" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not sent"* ]]
}

@test "set-telegram validates input and writes a mode-600 file" {
  rm -f "$ENVF"
  TELEGRAM_BOT_TOKEN="nonsense" TELEGRAM_CHAT_ID=42 run alerts_set_telegram demo
  [ "$status" -ne 0 ]
  TELEGRAM_BOT_TOKEN="123456:ABCDEFGHIJKLMNOPQRSTUVWX" TELEGRAM_CHAT_ID="abc" run alerts_set_telegram demo
  [ "$status" -ne 0 ]
  TELEGRAM_BOT_TOKEN="123456:ABCDEFGHIJKLMNOPQRSTUVWX" TELEGRAM_CHAT_ID="-100123" run alerts_set_telegram demo
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$ENVF")" = "600" ]
  ! printf '%s' "$output" | grep -q "ABCDEFGHIJKLMNOPQRSTUVWX"
}

@test "long text is cut to 1000 characters" {
  long="$(printf 'x%.0s' $(seq 1 3000))"
  run telegram_send "$ENVF" "$long"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.text | length' "$LOG")" -le 1000 ]
}

@test "client_notify cannot be enabled yet" {
  f="$BATS_TEST_TMPDIR/c.yaml"
  sed 's/^accounts:/alerts:\n  client_notify:\n    enabled: true\naccounts:/' "$BATS_TEST_DIRNAME/fixtures/client_valid.yaml" >"$f"
  run "$OPSKIT_ROOT/bin/opskit" client validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"client_notify"* ]]
}
