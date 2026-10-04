#!/usr/bin/env bats

setup() {
  PROBE="$BATS_TEST_DIRNAME/../lib/mail_probe.py"
  python3 "$BATS_TEST_DIRNAME/fake_mail.py" "$BATS_TEST_TMPDIR/ports" "box@example.test" "good-pass" &
  FAKE_PID=$!
  for _ in $(seq 1 50); do [ -s "$BATS_TEST_TMPDIR/ports" ] && break; sleep 0.1; done
  IMAP="$(jq -r .imap "$BATS_TEST_TMPDIR/ports")"
  SMTP="$(jq -r .smtp "$BATS_TEST_TMPDIR/ports")"
}

teardown() { kill "$FAKE_PID" 2>/dev/null || true; }

cfg() { # PASSWORD
  jq -n --arg pw "$1" --argjson i "$IMAP" --argjson s "$SMTP" '{email:"box@example.test", imap_address:"127.0.0.1", imap_port:$i, imap_login:"box@example.test", imap_password:$pw, imap_enable_ssl:false, smtp_address:"127.0.0.1", smtp_port:$s, smtp_login:"box@example.test", smtp_password:$pw, smtp_enable_ssl_tls:false, smtp_enable_starttls_auto:false}'
}

@test "imap login works with the right password" {
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg good-pass | python3 '$PROBE' imap"
  [ "$(jq -r .status <<<"$output")" = "ok" ]
}

@test "imap wrong password is reported as auth_failed" {
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg wrong | python3 '$PROBE' imap"
  [ "$(jq -r .status <<<"$output")" = "auth_failed" ]
}

@test "smtp login works and a wrong password is auth_failed" {
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg good-pass | python3 '$PROBE' smtp"
  [ "$(jq -r .status <<<"$output")" = "ok" ]
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg wrong | python3 '$PROBE' smtp"
  [ "$(jq -r .status <<<"$output")" = "auth_failed" ]
}

@test "an unreachable server is connect_failed" {
  run bash -c 'jq -n "{imap_address:\"127.0.0.1\", imap_port:9, imap_login:\"a\", imap_password:\"b\"}" | python3 "'"$PROBE"'" imap'
  [ "$(jq -r .status <<<"$output")" = "connect_failed" ]
}

@test "asking for SSL on a plain port is a tls_error" {
  run bash -c 'jq -n --argjson p '"$IMAP"' "{imap_address:\"127.0.0.1\", imap_port:\$p, imap_login:\"a\", imap_password:\"b\", imap_enable_ssl:true}" | python3 "'"$PROBE"'" imap'
  [ "$(jq -r .status <<<"$output")" = "tls_error" ]
}

@test "loopback: a test mail is sent, found and removed" {
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg good-pass | jq '. + {wait_seconds: 6}' | python3 '$PROBE' loopback"
  [ "$(jq -r .status <<<"$output")" = "ok" ]
}

@test "the password never appears in the output, even on failure" {
  run bash -c "$(declare -f cfg); IMAP=$IMAP SMTP=$SMTP; cfg super-secret-pw | python3 '$PROBE' imap"
  [[ "$output" != *"super-secret-pw"* ]]
}

@test "bad input does not crash" {
  run bash -c 'echo "not json" | python3 "'"$PROBE"'" imap'
  [ "$status" -eq 2 ]
  run bash -c 'echo "{}" | python3 "'"$PROBE"'" imap'
  [ "$(jq -r .status <<<"$output")" = "error" ]
}
