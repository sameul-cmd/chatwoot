#!/usr/bin/env bats

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT" client new shop --domain chat.shop.example.com --name "Shop BD" >/dev/null 2>&1
  CFG="$OPSKIT_CLIENTS_DIR/shop/client.yaml"
}

@test "the plan data is valid and complete (every channel, English and Bangla, review flag default true)" {
  run python3 "$BATS_TEST_DIRNAME/../lib/schema_check.py" channel_plan "$BATS_TEST_DIRNAME/../data/channel_plan.yaml"
  [ "$status" -eq 0 ]
  run python3 -c "
import yaml
d = yaml.safe_load(open('$BATS_TEST_DIRNAME/../data/channel_plan.yaml'))
bad = [(k, i) for k, v in d.items() for i, it in enumerate(v['items']) if it.get('review_required') is False]
assert not bad, bad
print('ok')"
  [ "$status" -eq 0 ]
}

@test "without channels in client.yaml every channel is listed" {
  run "$OPSKIT" channels plan shop
  [ "$status" -eq 0 ]
  for w in "Website chat bubble" "Email" "Telegram" "WhatsApp" "Facebook Messenger" "Instagram" "API inbox"; do [[ "$output" == *"$w"* ]]; done
  [[ "$output" == *"no channels are listed"* ]]
}

@test "only the client's channels are listed, with domain and name filled in" {
  printf 'channels:\n  - {type: whatsapp, name: WA}\n' >>"$CFG"
  run "$OPSKIT" channels plan shop
  [[ "$output" == *"WhatsApp"* ]]
  [[ "$output" != *"Telegram"* ]]
  [[ "$output" == *"chat.shop.example.com"* ]]
  [[ "$output" == *"Shop BD"* ]]
  [[ "$output" != *"{domain}"* ]]
}

@test "language and audience filters" {
  printf 'channels:\n  - {type: email, name: Mail}\n' >>"$CFG"
  run "$OPSKIT" channels plan shop --lang en --for client
  [[ "$output" == *"APP PASSWORD"* ]]
  [[ "$output" != *"ইমেইল"* ]]
  [[ "$output" != *"[US"* ]]
  run "$OPSKIT" channels plan shop --lang bn --for owner
  [[ "$output" == *"IMAP/SMTP"* ]]
  [[ "$output" != *"Choose the mailbox"* ]]
}

@test "Bangla lines are flagged for review" {
  run "$OPSKIT" channels plan shop
  [[ "$output" == *"review needed"* ]]
}

@test "the plan contains no secrets and tells people to share secrets privately" {
  run "$OPSKIT" channels plan shop
  [[ "$output" != *"AGE-SECRET"* ]]
  [[ "$output" == *"privately"* ]]
}

@test "bad options and unknown channel types are rejected" {
  run "$OPSKIT" channels plan shop --lang fr
  [ "$status" -ne 0 ]
  printf 'channels:\n  - {type: pigeon, name: x}\n' >>"$CFG"
  run "$OPSKIT" client validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"channels.0.type"* ]]
}
