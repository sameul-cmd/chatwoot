#!/usr/bin/env bats

setup() {
  AGENT="$BATS_TEST_DIRNAME/../agent/backup.sh"
  KEY="$BATS_TEST_TMPDIR/owner.key"
  age-keygen -o "$KEY" 2>/dev/null
  REC="$(age-keygen -y "$KEY")"
  ESC="$BATS_TEST_TMPDIR/esc"
  mkdir -p "$ESC" "$BATS_TEST_TMPDIR/fakebin" "$BATS_TEST_TMPDIR/storage/ab" "$BATS_TEST_TMPDIR/out"
  printf 'SECRET_KEY_BASE=topsecret123\n' >"$ESC/secrets.env"
  printf 'client_id: demo\n' >"$ESC/client.yaml"
  printf 'hello' >"$BATS_TEST_TMPDIR/storage/ab/blob1"
  touch "$BATS_TEST_TMPDIR/compose.yml"
  cat >"$BATS_TEST_TMPDIR/fakebin/docker" <<'EOS'
#!/usr/bin/env bash
all="$*"
case "$all" in
  *pg_dump*) [ -n "${FAKE_EMPTY_DUMP:-}" ] || printf 'PGDMP-fake-dump-content' ;;
  *pg_restore*) [ -z "${FAKE_BAD_DUMP:-}" ] || exit 1; cat >/dev/null ;;
  *"count(*) FROM conversations"*) echo 7 ;;
  *"max(id)"*) echo 42 ;;
  *"count(*) FROM active_storage_attachments"*) echo 1 ;;
  *active_storage_blobs*) echo "ab12|Yh1x==|5" ;;
  *"tar czf"*) tar czf - -C "$FAKE_STORAGE" . ;;
  *) echo "fake docker: unhandled: $all" >&2; exit 9 ;;
esac
EOS
  chmod +x "$BATS_TEST_TMPDIR/fakebin/docker"
  export PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" FAKE_STORAGE="$BATS_TEST_TMPDIR/storage"
}

run_backup() {
  "$AGENT" --id demo --compose-file "$BATS_TEST_TMPDIR/compose.yml" --out "$BATS_TEST_TMPDIR/out" \
    --recipient "$REC" --escrow-dir "$ESC" --escrow-file secrets.env --escrow-file client.yaml --tag v4.18.0-ce "$@"
}

@test "successful backup creates the full layout with a manifest" {
  run run_backup
  [ "$status" -eq 0 ]
  dest="$(printf '%s\n' "$output" | tail -n1)"
  [ -s "$dest/db.dump" ]
  [ -s "$dest/storage.tar.gz" ]
  [ -s "$dest/escrow.tar.age" ]
  [ "$(jq -r .conversations "$dest/manifest.json")" = "7" ]
  [ "$(jq -r .latest_conversation_id "$dest/manifest.json")" = "42" ]
  [ "$(jq -r .sample_blob.key "$dest/manifest.json")" = "ab12" ]
  [ "$(jq -r .chatwoot_tag "$dest/manifest.json")" = "v4.18.0-ce" ]
  [ "$(jq -r '.files["db.dump"].bytes' "$dest/manifest.json")" -gt 0 ]
  [ "$(stat -c %a "$dest")" = "700" ]
}

@test "the escrow is encrypted and decrypts with the owner key" {
  run run_backup
  dest="$(printf '%s\n' "$output" | tail -n1)"
  ! grep -q topsecret123 "$dest/escrow.tar.age"
  mkdir "$BATS_TEST_TMPDIR/x"
  age -d -i "$KEY" "$dest/escrow.tar.age" | tar -x -C "$BATS_TEST_TMPDIR/x"
  grep -q topsecret123 "$BATS_TEST_TMPDIR/x/secrets.env"
}

@test "manifest holds no secrets or message text" {
  run run_backup
  dest="$(printf '%s\n' "$output" | tail -n1)"
  ! grep -q topsecret123 "$dest/manifest.json"
}

@test "an empty database dump fails and leaves no complete backup" {
  FAKE_EMPTY_DUMP=1 run run_backup
  [ "$status" -ne 0 ]
  [ -z "$(find "$BATS_TEST_TMPDIR/out/demo" -mindepth 1 -maxdepth 1 -type d)" ]
}

@test "an unreadable dump archive fails and leaves no complete backup" {
  FAKE_BAD_DUMP=1 run run_backup
  [ "$status" -ne 0 ]
  [ -z "$(find "$BATS_TEST_TMPDIR/out/demo" -mindepth 1 -maxdepth 1 -type d)" ]
}

@test "a second concurrent backup refuses with exit 75" {
  mkdir -p "$BATS_TEST_TMPDIR/out/demo"
  exec 8>"$BATS_TEST_TMPDIR/out/demo/.lock"
  flock -n 8
  run run_backup
  [ "$status" -eq 75 ]
}

@test "--no-storage skips the uploads archive and says so in the manifest" {
  run run_backup --no-storage
  [ "$status" -eq 0 ]
  dest="$(printf '%s\n' "$output" | tail -n1)"
  [ ! -e "$dest/storage.tar.gz" ]
  [ "$(jq -r .storage_included "$dest/manifest.json")" = "false" ]
}

@test "bad arguments are rejected" {
  run "$AGENT" --id "../x" --compose-file c --out o --recipient "$REC" --escrow-dir . --escrow-file a
  [ "$status" -eq 2 ]
  run "$AGENT" --id demo --compose-file c --out o --recipient "not-a-key" --escrow-dir . --escrow-file a
  [ "$status" -eq 2 ]
}
