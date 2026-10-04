#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/alert_state.sh"
  D=1800   # dedup 30 min
  R=7200   # reminder 2 h
}

# args: SEV PREV LAST NOTIFIED HELD NOW QUIET
act() { decide_action "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$D" "$R"; }

@test "a new critical problem is sent immediately, even in quiet hours" {
  [ "$(act critical ok 0 0 0 1000 0)" = "send" ]
  [ "$(act critical ok 0 0 0 1000 1)" = "send" ]
}

@test "a new warning is sent in the day and held in quiet hours" {
  [ "$(act warn ok 0 0 0 1000 0)" = "send" ]
  [ "$(act warn ok 0 0 0 1000 1)" = "hold" ]
}

@test "the same alert is not repeated within 30 minutes (flapping is deferred)" {
  [ "$(act critical ok 1000 1 0 $((1000 + 1799)) 0)" = "defer" ]
  [ "$(act critical ok 1000 1 0 $((1000 + 1800)) 0)" = "send" ]
}

@test "a still-open critical gets one reminder after 2 hours, not before" {
  [ "$(act critical critical 1000 1 0 $((1000 + 7199)) 0)" = "none" ]
  [ "$(act critical critical 1000 1 0 $((1000 + 7200)) 0)" = "remind" ]
}

@test "a still-open warning is never repeated" {
  [ "$(act warn warn 1000 1 0 $((1000 + 99999)) 0)" = "none" ]
}

@test "warning escalating to critical is sent at once" {
  [ "$(act critical warn 1000 1 0 1100 0)" = "send" ]
  [ "$(act critical warn 1000 1 0 1100 1)" = "send" ]
}

@test "critical dropping to warning stays silent" {
  [ "$(act warn critical 1000 1 0 1100 0)" = "none" ]
}

@test "resolved is sent once, only if the owner was told" {
  [ "$(act ok critical 1000 1 0 2000 0)" = "resolve" ]
  [ "$(act ok warn 1000 1 0 2000 0)" = "resolve" ]
  [ "$(act ok warn 0 0 1 2000 0)" = "none" ]
  [ "$(act ok ok 1000 0 0 2000 0)" = "none" ]
}

@test "a held warning is released after quiet hours and stays held during them" {
  [ "$(act warn warn 0 0 1 3000 1)" = "none" ]
  [ "$(act warn warn 0 0 1 3000 0)" = "release" ]
}

@test "quiet hours spanning midnight" {
  now_23="$(date -u -d '2026-10-04 23:00:00 UTC' +%s)"
  now_03="$(date -u -d '2026-10-05 03:00:00 UTC' +%s)"
  now_12="$(date -u -d '2026-10-04 12:00:00 UTC' +%s)"
  now_0800="$(date -u -d '2026-10-04 08:00:00 UTC' +%s)"
  now_2200="$(date -u -d '2026-10-04 22:00:00 UTC' +%s)"
  is_quiet "$now_23" UTC 22:00 08:00
  is_quiet "$now_03" UTC 22:00 08:00
  is_quiet "$now_2200" UTC 22:00 08:00
  ! is_quiet "$now_12" UTC 22:00 08:00
  ! is_quiet "$now_0800" UTC 22:00 08:00
}

@test "quiet hours use the client's time zone" {
  t="$(date -u -d '2026-10-04 17:00:00 UTC' +%s)"   # 23:00 in Dhaka (UTC+6)
  is_quiet "$t" Asia/Dhaka 22:00 08:00
  ! is_quiet "$t" UTC 22:00 08:00
}

@test "state files round-trip and unknown checks default to ok" {
  dir="$BATS_TEST_TMPDIR/state"
  state_read "$dir" sidekiq
  [ "$PREV_SEV" = "ok" ]
  state_write "$dir" sidekiq critical 100 200 1 0
  state_read "$dir" sidekiq
  [ "$PREV_SEV" = "critical" ] && [ "$PREV_SINCE" = "100" ] && [ "$PREV_LAST" = "200" ] && [ "$PREV_NOTIFIED" = "1" ]
  [ "$(state_checks "$dir")" = "sidekiq" ]
}

@test "check names cannot escape the state folder" {
  run state_write "$BATS_TEST_TMPDIR/state" "../evil" warn 1 1 0 0
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/evil.state" ]
}
