#!/usr/bin/env bats

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  export OPSKIT_ALERT_DIR="$BATS_TEST_TMPDIR/outbox"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  KEY="$BATS_TEST_TMPDIR/owner.key"
  age-keygen -o "$KEY" 2>/dev/null
  export OPSKIT_AGE_RECIPIENT="$(age-keygen -y "$KEY")"
  "$OPSKIT" client new demo --domain chat.demo.localhost --name Demo --local >/dev/null 2>&1
  CFG="$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  REMOTE="$BATS_TEST_TMPDIR/remote"
  printf 'backup:\n  remote: %s\n  retention_local: 14\n  retention_remote: 30\n' "$REMOTE" >>"$CFG"
  AGENT="$BATS_TEST_TMPDIR/fake-agent"
  cat >"$AGENT" <<'EOS'
#!/usr/bin/env bash
[ -z "${FAKE_FAIL:-}" ] || { echo "boom" >&2; exit 1; }
while [ $# -gt 0 ]; do [ "$1" = "--out" ] && out="$2"; [ "$1" = "--id" ] && id="$2"; shift; done
ts="${FAKE_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
d="$out/$id/$ts"; mkdir -p "$d"
echo dump >"$d/db.dump"; echo tar >"$d/storage.tar.gz"; echo enc >"$d/escrow.tar.age"; echo '{}' >"$d/manifest.json"
echo "$d"
EOS
  chmod +x "$AGENT"
  export OPSKIT_BACKUP_AGENT="$AGENT"
}

@test "a good run keeps a local backup, copies it off-server and verifies it" {
  run "$OPSKIT" backup run demo
  [ "$status" -eq 0 ]
  ts="$("$OPSKIT" backup list demo | tail -n1)"
  [ -s "$REMOTE/demo/$ts/db.dump" ]
  [ -s "$REMOTE/demo/$ts/escrow.tar.age" ]
  [ -z "$(ls "$OPSKIT_ALERT_DIR" 2>/dev/null)" ]
}

@test "a failing agent raises a critical alert and a non-zero exit" {
  FAKE_FAIL=1 run "$OPSKIT" backup run demo
  [ "$status" -ne 0 ]
  f="$(ls "$OPSKIT_ALERT_DIR"/*.json | head -n1)"
  [ "$(jq -r .severity "$f")" = "critical" ]
  [ "$(jq -r .check "$f")" = "backup" ]
}

@test "an unusable remote raises an alert but the local backup is kept" {
  printf 'x' >"$BATS_TEST_TMPDIR/blocker"
  sed -i "s#remote: .*#remote: $BATS_TEST_TMPDIR/blocker/sub#" "$CFG"
  run "$OPSKIT" backup run demo
  [ "$status" -ne 0 ]
  [ -n "$("$OPSKIT" backup list demo | tail -n1)" ]
  grep -q "off-server" "$(ls "$OPSKIT_ALERT_DIR"/*.json | head -n1)"
}

@test "old remote backups are pruned, the new one stays" {
  mkdir -p "$REMOTE/demo/20200101T020000Z" "$REMOTE/demo/20200102T020000Z"
  echo x >"$REMOTE/demo/20200101T020000Z/f"; echo x >"$REMOTE/demo/20200102T020000Z/f"
  run "$OPSKIT" backup run demo
  [ "$status" -eq 0 ]
  [ ! -d "$REMOTE/demo/20200101T020000Z" ]
  [ ! -d "$REMOTE/demo/20200102T020000Z" ]
  [ "$(ls "$REMOTE/demo" | wc -l)" -eq 1 ]
}

@test "without an encryption key the backup is refused and an alert is raised" {
  mkdir -p "$BATS_TEST_TMPDIR/nokeys"
  run env -u OPSKIT_AGE_RECIPIENT OPSKIT_KEYS_DIR="$BATS_TEST_TMPDIR/nokeys" "$OPSKIT" backup run demo
  [ "$status" -ne 0 ]
  [ -n "$(ls "$OPSKIT_ALERT_DIR"/*.json 2>/dev/null)" ]
}

@test "no remote configured still succeeds locally with a warning" {
  sed -i '/^backup:/,$d' "$CFG"
  run "$OPSKIT" backup run demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"no backup.remote"* ]]
}

@test "backup run is refused for a non-local target until Phase 11" {
  "$OPSKIT" client new shop --domain chat.shop.example.com --name Shop >/dev/null 2>&1
  run "$OPSKIT" backup run shop
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported yet"* ]]
}
