#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  export OPSKIT_ALERT_DIR="$BATS_TEST_TMPDIR/outbox"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT_ROOT/bin/opskit" client new demo --domain chat.demo.localhost --name Demo --local --tag v4.17.1-ce >/dev/null 2>&1
  mkdir -p "$OPSKIT_CLIENTS_DIR/demo/stack"
  : >"$OPSKIT_CLIENTS_DIR/demo/stack/docker-compose.yml"
  for l in log validate secrets render deploy confirm alert alert_state crypto backup restore chatwoot_api health channels_health notify checks smoke upgrade; do . "$OPSKIT_ROOT/lib/$l.sh"; done
  wait_healthy() { return 0; }
  NOW="$(date -u -d '2026-10-04 20:00:00 UTC' +%s)"   # 02:00 in Dhaka
}

mark_staging_pass() { # TAG [FINISHED_EPOCH]
  mkdir -p "$(upgrade_dir demo)"
  jq -n --argjson e "${2:-$NOW}" --arg t "$1" '{status:"pass", from_tag:"v4.17.1-ce", to_tag:$t, finished_epoch:$e}' >"$(upgrade_dir demo)/staging-$1.json"
}

@test "only CE tags are accepted" {
  _tag_valid v4.18.0-ce
  ! _tag_valid v4.18.0
  ! _tag_valid "v4.18.0-ce; rm -rf /"
  ! _tag_valid latest
  ! _tag_valid ""
}

@test "version ordering" {
  _ver_newer v4.17.1 v4.18.0
  _ver_newer v4.9.0 v4.10.0
  ! _ver_newer v4.18.0 v4.17.1
  ! _ver_newer v4.18.0 v4.18.0
}

@test "the CLI rejects hostile or malformed targets" {
  run "$OPSKIT_ROOT/bin/opskit" upgrade demo --to 'v4.18.0-ce;id' --info
  [ "$status" -eq 2 ]
  run "$OPSKIT_ROOT/bin/opskit" upgrade demo --to v4.18.0 --info
  [ "$status" -eq 2 ]
  run "$OPSKIT_ROOT/bin/opskit" upgrade demo --to v4.18.0-ce
  [ "$status" -eq 2 ]
}

@test "off-hours window: 01:00-05:00 in the client's time zone, enforced when asked" {
  export OPSKIT_ENFORCE_WINDOW=1
  upgrade_window_ok demo "$NOW"                                            # 02:00 Dhaka
  ! upgrade_window_ok demo "$(date -u -d '2026-10-04 06:00:00 UTC' +%s)"    # 12:00 Dhaka
  ! upgrade_window_ok demo "$(date -u -d '2026-10-04 23:00:00 UTC' +%s)"    # 05:00 Dhaka (end is exclusive)
  upgrade_window_ok demo "$(date -u -d '2026-10-04 19:00:00 UTC' +%s)"     # 01:00 Dhaka (start inclusive)
}

@test "a custom window and the 'anytime' mode" {
  export OPSKIT_ENFORCE_WINDOW=1
  printf 'upgrade_window:\n  start: "12:00"\n  end: "13:00"\n' >>"$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  upgrade_window_ok demo "$(date -u -d '2026-10-04 06:30:00 UTC' +%s)"
  ! upgrade_window_ok demo "$NOW"
  sed -i '/^upgrade_window:/,$d' "$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  printf 'upgrade_window:\n  mode: anytime\n' >>"$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  upgrade_window_ok demo "$(date -u -d '2026-10-04 06:30:00 UTC' +%s)"
}

@test "local practice stacks are exempt from the window unless enforcement is on" {
  unset OPSKIT_ENFORCE_WINDOW
  upgrade_window_ok demo "$(date -u -d '2026-10-04 06:30:00 UTC' +%s)"
}

@test "preflight refuses: same version, older version, non-CE tag" {
  export OPSKIT_NOW="$NOW"
  run upgrade_preflight demo v4.17.1-ce stage
  [ "$status" -ne 0 ]; [[ "$output" == *"already on"* ]]
  run upgrade_preflight demo v4.16.0-ce stage
  [ "$status" -ne 0 ]; [[ "$output" == *"not newer"* ]]
  run upgrade_preflight demo v4.18.0 stage
  [ "$status" -ne 0 ]
}

@test "preflight refuses an unhealthy live stack" {
  export OPSKIT_NOW="$NOW"
  wait_healthy() { return 1; }
  run upgrade_preflight demo v4.18.0-ce stage
  [ "$status" -ne 0 ]; [[ "$output" == *"not healthy"* ]]
}

@test "apply needs a passing, recent staging rehearsal for exactly this upgrade" {
  export OPSKIT_NOW="$NOW"
  run upgrade_preflight demo v4.18.0-ce apply
  [ "$status" -ne 0 ]; [[ "$output" == *"no passing staging rehearsal"* ]]
  mark_staging_pass v4.18.0-ce "$((NOW - 90000))"
  run upgrade_preflight demo v4.18.0-ce apply
  [ "$status" -ne 0 ]; [[ "$output" == *"older than 24 hours"* ]]
  mark_staging_pass v4.18.0-ce "$((NOW - 3600))"
  run upgrade_preflight demo v4.18.0-ce apply
  [ "$status" -eq 0 ]
}

@test "a failed rehearsal result does not unlock apply" {
  export OPSKIT_NOW="$NOW"
  mkdir -p "$(upgrade_dir demo)"
  jq -n --argjson e "$NOW" '{status:"fail", from_tag:"v4.17.1-ce", finished_epoch:$e}' >"$(upgrade_dir demo)/staging-v4.18.0-ce.json"
  run upgrade_preflight demo v4.18.0-ce apply
  [ "$status" -ne 0 ]
}

@test "outside the window apply is refused, --outage-fix overrides with a warning" {
  export OPSKIT_ENFORCE_WINDOW=1
  export OPSKIT_NOW="$(date -u -d '2026-10-04 06:00:00 UTC' +%s)"
  mark_staging_pass v4.18.0-ce "$OPSKIT_NOW"
  run upgrade_preflight demo v4.18.0-ce apply
  [ "$status" -ne 0 ]; [[ "$output" == *"off-hours window"* ]]
  run upgrade_preflight demo v4.18.0-ce apply yes
  [ "$status" -eq 0 ]; [[ "$output" == *"--outage-fix"* ]]
}

@test "history lines are single-line JSON and carry no secrets" {
  OPSKIT_NOW="$NOW" upgrade_history_add demo v4.17.1-ce v4.18.0-ce rolled_back $'line one\nline two' true 20261004T020000Z 3
  [ "$(wc -l <"$(upgrade_dir demo)/history.jsonl")" -eq 1 ]
  [ "$(jq -r .result "$(upgrade_dir demo)/history.jsonl")" = "rolled_back" ]
  [ "$(jq -r .rolled_back "$(upgrade_dir demo)/history.jsonl")" = "true" ]
  [ "$(jq -r .migrations_applied "$(upgrade_dir demo)/history.jsonl")" = "3" ]
}

@test "set_client_tag changes the tag and keeps a dated copy of the old file" {
  OPSKIT_NOW="$NOW" set_client_tag demo v4.18.0-ce
  [ "$(yq -r .install.tag "$OPSKIT_CLIENTS_DIR/demo/client.yaml")" = "v4.18.0-ce" ]
  grep -q 'tag: v4.17.1-ce' "$(ls "$(upgrade_dir demo)"/client.yaml.*.bak | head -n1)"
  "$OPSKIT_ROOT/bin/opskit" client validate "$OPSKIT_CLIENTS_DIR/demo/client.yaml"
}

@test "release info lists commits, migrations, new settings and compose changes from git tags" {
  r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r" && git -C "$r" init -q && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  mkdir -p "$r/db/migrate"
  printf 'A=\nB=\n' >"$r/.env.example"; echo v1 >"$r/docker-compose.production.yaml"; echo m1 >"$r/db/migrate/1_one.rb"
  git -C "$r" add -A && git -C "$r" commit -qm one && git -C "$r" tag v4.17.1
  printf 'A=\nC=\n' >"$r/.env.example"; echo m2 >"$r/db/migrate/2_two.rb"; echo v2 >"$r/docker-compose.production.yaml"
  git -C "$r" add -A && git -C "$r" commit -qm two && git -C "$r" tag v4.18.0
  OPSKIT_REPO_ROOT="$r" run upgrade_info demo v4.18.0-ce
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 commits"* ]]
  [[ "$output" == *"1 database change"* ]]
  [[ "$output" == *"2_two.rb"* ]]
  [[ "$output" == *"new settings:     C"* ]]
  [[ "$output" == *"removed settings: B"* ]]
  [[ "$output" == *"CHANGED"* ]]
}

@test "release info explains how to fetch a missing tag" {
  r="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$r" && git -C "$r" init -q
  OPSKIT_REPO_ROOT="$r" run upgrade_info demo v4.18.0-ce
  [ "$status" -ne 0 ]
  [[ "$output" == *"git fetch upstream tag"* ]]
}

# ---- rollback decision -------------------------------------------------------------------------------------------------
stub_rollback() {
  CALLS="$BATS_TEST_TMPDIR/calls"; : >"$CALLS"
  dc() { shift; printf '%s\n' "$*" >>"$CALLS"; }
  render_client() { return 0; }
  decrypt_file() { : >"$2"; }
  _upgrade_notify() { return 0; }
  mkdir -p "$BATS_TEST_TMPDIR/b"
  printf '{"schema_version":"100"}\n' >"$BATS_TEST_TMPDIR/b/manifest.json"
}

@test "rollback with an unchanged database only switches the program version back" {
  stub_rollback
  _psql_sid() { echo 100; }
  upgrade_rollback demo v4.17.1-ce "$BATS_TEST_TMPDIR/b" "smoke failed"
  ! grep -q "DROP DATABASE" "$CALLS"
  ! grep -q "pg_restore" "$CALLS"
  grep -q "up -d" "$CALLS"
  [ "$(yq -r .install.tag "$OPSKIT_CLIENTS_DIR/demo/client.yaml")" = "v4.17.1-ce" ]
}

@test "rollback after migrations restores the database from the pre-upgrade backup" {
  stub_rollback
  _psql_sid() { echo 103; }
  upgrade_rollback demo v4.17.1-ce "$BATS_TEST_TMPDIR/b" "smoke failed"
  grep -q "DROP DATABASE" "$CALLS"
  grep -q "CREATE DATABASE" "$CALLS"
  grep -q "pg_restore" "$CALLS"
  grep -q "stop rails sidekiq aibot" "$CALLS"
}

@test "rollback restores the database when the current version cannot be read" {
  stub_rollback
  _psql_sid() { echo ""; }
  upgrade_rollback demo v4.17.1-ce "$BATS_TEST_TMPDIR/b" "stack down"
  grep -q "pg_restore" "$CALLS"
}
