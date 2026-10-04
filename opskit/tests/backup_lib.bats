#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/crypto.sh"
  . "$OPSKIT_ROOT/lib/alert.sh"
  . "$OPSKIT_ROOT/lib/prune.sh"
  export OPSKIT_ALERT_DIR="$BATS_TEST_TMPDIR/outbox"
  KEY="$BATS_TEST_TMPDIR/owner.key"
  age-keygen -o "$KEY" 2>/dev/null
  export OPSKIT_AGE_RECIPIENT="$(age-keygen -y "$KEY")"
}

@test "encrypt then decrypt round-trips and leaves no plaintext copy" {
  printf 'SECRET_KEY_BASE=abc123\n' >"$BATS_TEST_TMPDIR/in.txt"
  encrypt_file "$BATS_TEST_TMPDIR/in.txt" "$BATS_TEST_TMPDIR/in.age"
  ! grep -q abc123 "$BATS_TEST_TMPDIR/in.age"
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/in.age")" = "600" ]
  decrypt_file "$BATS_TEST_TMPDIR/in.age" "$BATS_TEST_TMPDIR/out.txt" "$KEY"
  cmp "$BATS_TEST_TMPDIR/in.txt" "$BATS_TEST_TMPDIR/out.txt"
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/out.txt")" = "600" ]
}

@test "encryption refuses to run without a public key" {
  unset OPSKIT_AGE_RECIPIENT
  OPSKIT_KEYS_DIR="$BATS_TEST_TMPDIR/empty" run age_recipient
  [ "$status" -ne 0 ]
  [[ "$output" == *"no age public key"* ]]
}

@test "a malformed public key is rejected" {
  OPSKIT_AGE_RECIPIENT="not-a-key" run age_recipient
  [ "$status" -ne 0 ]
}

@test "decrypting with the wrong key fails and leaves no output file" {
  printf 'x\n' >"$BATS_TEST_TMPDIR/in.txt"
  encrypt_file "$BATS_TEST_TMPDIR/in.txt" "$BATS_TEST_TMPDIR/in.age"
  age-keygen -o "$BATS_TEST_TMPDIR/other.key" 2>/dev/null
  run decrypt_file "$BATS_TEST_TMPDIR/in.age" "$BATS_TEST_TMPDIR/out.txt" "$BATS_TEST_TMPDIR/other.key"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/out.txt" ]
}

@test "pruning keeps exactly the backups inside the retention window" {
  now="$(date -u -d '2026-10-30 12:00:00' +%s)"
  names="20261001T020000Z
20261015T020000Z
20261017T020000Z
20261029T020000Z
20261030T020000Z"
  run bash -c ". '$OPSKIT_ROOT/lib/prune.sh'; printf '%s\n' '$names' | prune_candidates 14 $now"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '20261001T020000Z\n20261015T020000Z')" ]
}

@test "pruning never deletes the newest backup even if it is older than the window" {
  now="$(date -u -d '2026-12-30 12:00:00' +%s)"
  run bash -c ". '$OPSKIT_ROOT/lib/prune.sh'; printf '20261001T020000Z\n20261002T020000Z\n' | prune_candidates 14 $now"
  [ "$output" = "20261001T020000Z" ]
}

@test "pruning ignores names that are not complete backups" {
  now="$(date -u -d '2026-12-30 12:00:00' +%s)"
  run bash -c ". '$OPSKIT_ROOT/lib/prune.sh'; printf '.partial-20260101T000000Z\nnotes\n20261001T020000Z\n' | prune_candidates 14 $now"
  [ -z "$output" ]
}

@test "prune_local deletes old folders on disk and keeps .partial of today" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d/20260101T020000Z" "$d/20260920T020000Z" "$d/.partial-20261029T020000Z"
  OPSKIT_NOW="$(date -u -d '2026-10-30 12:00:00' +%s)" prune_local "$d" 14
  [ ! -d "$d/20260101T020000Z" ]
  [ -d "$d/20260920T020000Z" ]
  [ -d "$d/.partial-20261029T020000Z" ]
}

@test "alert payload has the expected fields and a bounded summary" {
  long="$(printf 'x%.0s' $(seq 1 500))"
  run emit_alert critical demo backup "$long"
  [ "$status" -eq 0 ]
  f="$(printf '%s\n' "$output" | tail -n1)"
  [ "$(jq -r .severity "$f")" = "critical" ]
  [ "$(jq -r .client_id "$f")" = "demo" ]
  [ "$(jq -r .check "$f")" = "backup" ]
  [ "$(jq -r '.summary | length' "$f")" -le 300 ]
  jq -e .timestamp "$f" >/dev/null
}

@test "alert rejects an unknown severity" {
  run emit_alert panic demo backup "x"
  [ "$status" -ne 0 ]
}

@test "heartbeat is skipped without a hub and never fails" {
  unset OPSKIT_HUB_URL
  run send_heartbeat demo backup
  [ "$status" -eq 0 ]
}

@test "an unreachable hub does not fail the alert" {
  OPSKIT_HUB_URL="http://127.0.0.1:9/none" run emit_alert warn demo backup "hub down"
  [ "$status" -eq 0 ]
  [ -n "$(ls "$OPSKIT_ALERT_DIR")" ]
}

@test "backup settings are validated with field names" {
  f="$BATS_TEST_TMPDIR/c.yaml"
  sed 's/^accounts:/backup:\n  retention_local: 0\n  remote: ""\naccounts:/' "$BATS_TEST_DIRNAME/fixtures/client_valid.yaml" >"$f"
  run "$BATS_TEST_DIRNAME/../bin/opskit" client validate "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup.retention_local"* ]]
  [[ "$output" == *"backup.remote"* ]]
}
