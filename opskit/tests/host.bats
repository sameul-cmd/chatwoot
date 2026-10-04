#!/usr/bin/env bats

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  FAKE="$BATS_TEST_TMPDIR/fake-ssh"
  cat >"$FAKE" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/ssh.args"
cat >"$BATS_TEST_TMPDIR/ssh.stdin"
EOS
  chmod +x "$FAKE"
  export OPSKIT_SSH="$FAKE"
}

@test "bootstrap sends the agent script over ssh, as root, with BatchMode" {
  run "$OPSKIT" host bootstrap 203.0.113.10
  [ "$status" -eq 0 ]
  grep -q 'BatchMode=yes' "$BATS_TEST_TMPDIR/ssh.args"
  grep -q '^root@203.0.113.10$' "$BATS_TEST_TMPDIR/ssh.args"
  grep -q 'ufw allow 443/tcp' "$BATS_TEST_TMPDIR/ssh.stdin"
}

@test "bootstrap forwards --dry-run and uses sudo for non-root users" {
  run "$OPSKIT" host bootstrap vps1.example.com --user deploy --dry-run
  [ "$status" -eq 0 ]
  grep -q '^deploy@vps1.example.com$' "$BATS_TEST_TMPDIR/ssh.args"
  grep -q '^sudo$' "$BATS_TEST_TMPDIR/ssh.args"
  grep -q '^--dry-run$' "$BATS_TEST_TMPDIR/ssh.args"
}

@test "bootstrap rejects hosts and users that could inject commands" {
  run "$OPSKIT" host bootstrap 'a;rm -rf /'
  [ "$status" -eq 2 ]
  run "$OPSKIT" host bootstrap 203.0.113.10 --user 'x;y'
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/ssh.args" ]
}

@test "agent bootstrap dry-run changes nothing and lists the steps" {
  run bash "$BATS_TEST_DIRNAME/../agent/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw allow 22/tcp"* ]]
  [[ "$output" == *"ufw allow 80/tcp"* ]]
  [[ "$output" == *"ufw allow 443/tcp"* ]]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"report only"* ]]
}
