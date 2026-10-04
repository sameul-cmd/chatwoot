#!/usr/bin/env bats
# Industry packs (Phase 7): pack data checks, the apply plan and the apply itself against a pretend Chatwoot.

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  ROOT="$BATS_TEST_DIRNAME/.."
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT" client new shop --domain chat.shop.example.com --name "Shop BD" --local >/dev/null 2>&1
  CLIENT="$OPSKIT_CLIENTS_DIR/shop"
  LOG="$BATS_TEST_TMPDIR/requests.log"
  PORT="$BATS_TEST_TMPDIR/port"
  python3 "$ROOT/tests/fake_chatwoot.py" "$PORT" "$LOG" "$ROOT/tests/fixtures/pack_live_shapes.json" &
  FAKE=$!
  for _ in $(seq 1 50); do [ -s "$PORT" ] && break; sleep 0.1; done
  # the same libraries the command uses, with the stack lookup replaced by the pretend server
  cat >"$BATS_TEST_TMPDIR/env.sh" <<EOF
export OPSKIT_ROOT="$ROOT"
for l in log validate secrets render deploy chatwoot_api pack; do . "$ROOT/lib/\$l.sh"; done
cw_use_stack() { export CW_BASE_URL="http://127.0.0.1:\$(cat "$PORT")" CW_TOKEN=test; }
EOF
}

teardown() {
  kill "$FAKE" 2>/dev/null || true
}

apply() {
  bash -c '. "$1"; shift; pack_apply "$@"' _ "$BATS_TEST_TMPDIR/env.sh" shop "$@"
}

@test "all six packs are valid" {
  run "$OPSKIT" pack validate
  [ "$status" -eq 0 ]
  for i in generic fcommerce clinic travel education service; do [[ "$output" == *"valid: $i"* ]]; done
}

@test "pack list names the six industries" {
  run "$OPSKIT" pack list
  [ "$output" = "$(printf 'clinic\neducation\nfcommerce\ngeneric\nservice\ntravel')" ]
}

@test "an unknown industry lists the valid ones" {
  run "$OPSKIT" pack validate bakery
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown industry 'bakery'"* && "$output" == *"fcommerce"* ]]
}

@test "the validator names a digit, a blank in an automatic text, an unknown label, bad hours and Bangla in English" {
  cp -r "$ROOT/packs/fcommerce" "$BATS_TEST_TMPDIR/fcommerce"
  d="$BATS_TEST_TMPDIR/fcommerce"
  sed -i 's/Thank you! We have received/Thank you! We have received 5/' "$d/canned_responses.yaml"
  sed -i '0,/A team member/s/A team member will reply shortly./Call [phone] now./' "$d/auto_replies.yaml"
  sed -i 's/label: price/label: nolabel/' "$d/automations.yaml"
  sed -i '0,/"10:00"/s/"10:00"/"21:00"/' "$d/business_hours.yaml"
  sed -i '0,/Which product are you interested in?/s//কোন পণ্য?/' "$d/canned_responses.yaml"
  run python3 "$ROOT/lib/pack_data.py" validate "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"order_received.en: packs must not contain digits"* ]]
  [[ "$output" == *"greeting.en: automatic messages must not contain [blanks]"* ]]
  [[ "$output" == *"labels.yaml does not define"* ]]
  [[ "$output" == *"day 0 needs closed: true"* ]]
  [[ "$output" == *"ask_product.en: English text contains Bangla letters"* ]]
}

@test "a pack with a missing language is rejected with the field name" {
  cp -r "$ROOT/packs/clinic" "$BATS_TEST_TMPDIR/clinic"
  sed -i '0,/    bn: /{/    bn: /d}' "$BATS_TEST_TMPDIR/clinic/canned_responses.yaml"
  run python3 "$ROOT/lib/pack_data.py" validate "$BATS_TEST_TMPDIR/clinic"
  [ "$status" -eq 1 ]
  [[ "$output" == *"canned_responses.yaml: items.0: 'bn' is a required property"* ]]
}

@test "a pack file for another industry is rejected" {
  cp -r "$ROOT/packs/clinic" "$BATS_TEST_TMPDIR/clinic"
  sed -i 's/^industry: clinic/industry: travel/' "$BATS_TEST_TMPDIR/clinic/labels.yaml"
  run python3 "$ROOT/lib/pack_data.py" validate "$BATS_TEST_TMPDIR/clinic"
  [ "$status" -eq 1 ]
  [[ "$output" == *"labels.yaml: industry 'travel' does not match the folder 'clinic'"* ]]
}

@test "every Bangla text is marked review_required until approved" {
  run grep -rc "review_required: false" "$ROOT"/packs
  [[ "$output" != *":1"* && "$output" != *":2"* ]]
}

@test "dry run shows the plan and changes nothing" {
  run apply fcommerce --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"CREATE     saved reply"* && "$output" == *"Dry run: nothing was changed"* ]]
  ! grep -qE "^(POST|PATCH)" "$LOG"
}

@test "Bangla that is not proofread is left out unless asked for" {
  run apply fcommerce
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED    saved reply                  greeting_bn"* && "$output" == *"Bangla not yet proofread"* ]]
  run curl -s "http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1/canned_responses"
  [[ "$output" == *"please_wait_en"* && "$output" != *"please_wait_bn"* ]]
}

@test "apply creates the pack, a second apply changes nothing, and nothing is ever deleted" {
  run apply fcommerce --include-unreviewed
  [ "$status" -eq 0 ]
  [[ "$output" == *"pack fcommerce applied to shop"* ]]
  base="http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1"
  [ "$(curl -s "$base/canned_responses" | jq length)" -eq 32 ]
  [ "$(curl -s "$base/labels" | jq '.payload | length')" -eq 7 ]
  [ "$(curl -s "$base/automation_rules" | jq '[.payload[] | select(.name | startswith("[opskit:fcommerce]"))] | length')" -eq 6 ]
  [ "$(curl -s "$base/inboxes" | jq '[.payload[] | select(.id == 2)][0] | [.greeting_enabled, .working_hours_enabled, .timezone, .csat_survey_enabled] | @csv' -r)" = 'true,true,"Asia/Dhaka",true' ]
  : >"$LOG"
  run apply fcommerce --include-unreviewed
  [[ "$output" == *"0 to create, 0 to update"* && "$output" == *"Nothing to change."* ]]
  ! grep -qE "^(POST|PATCH)" "$LOG"
  ! grep -q "^DELETE" "$LOG"
}

@test "items the client edited or made are kept as they are" {
  apply fcommerce --include-unreviewed
  base="http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1"
  [ "$(curl -s "$base/canned_responses" | jq -r '.[] | select(.short_code == "greeting_en") | .content')" = "changed" ]
  [ "$(curl -s "$base/labels" | jq -r '.payload[] | select(.title == "price") | .description')" = "changed" ]
  [ "$(curl -s "$base/inboxes" | jq -r '.payload[] | select(.id == 1) | .greeting_message')" = "Hello! বাংলা ok" ]
  run apply fcommerce --include-unreviewed --dry-run
  [[ "$output" == *"KEPT       saved reply                  greeting_en"* && "$output" == *"client edited"* ]]
}

@test "a saved reply the client adds later survives another apply" {
  apply fcommerce --include-unreviewed
  base="http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1"
  curl -s -X POST "$base/canned_responses" -H 'Content-Type: application/json' -d '{"canned_response":{"short_code":"my_own","content":"mine"}}' >/dev/null
  apply fcommerce --include-unreviewed
  [ "$(curl -s "$base/canned_responses" | jq -r '.[] | select(.short_code == "my_own") | .content')" = "mine" ]
  [ "$(curl -s "$base/canned_responses" | jq length)" -eq 33 ]
}

@test "a newer pack text updates an item the client has not touched, but not one the client edited" {
  export OPSKIT_PACKS_DIR="$BATS_TEST_TMPDIR/packs"
  mkdir -p "$OPSKIT_PACKS_DIR"
  cp -r "$ROOT/packs/fcommerce" "$OPSKIT_PACKS_DIR/"
  apply fcommerce --include-unreviewed
  base="http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1"
  curl -s -X PATCH "$base/canned_responses/$(curl -s "$base/canned_responses" | jq '.[] | select(.short_code == "thanks_en") | .id')" \
    -H 'Content-Type: application/json' -d '{"canned_response":{"content":"client wording"}}' >/dev/null
  sed -i 's/We have received your order details and will confirm shortly./We got your order and will confirm soon./' "$OPSKIT_PACKS_DIR/fcommerce/canned_responses.yaml"
  sed -i 's/Thank you for contacting us. Have a great day!/Thanks for writing to us!/' "$OPSKIT_PACKS_DIR/fcommerce/canned_responses.yaml"
  run apply fcommerce --include-unreviewed
  [[ "$output" == *"1 to update"* ]]
  [ "$(curl -s "$base/canned_responses" | jq -r '.[] | select(.short_code == "order_received_en") | .content')" = "Thank you! We got your order and will confirm soon." ]
  [ "$(curl -s "$base/canned_responses" | jq -r '.[] | select(.short_code == "thanks_en") | .content')" = "client wording" ]
}

@test "--inbox limits the hours and greeting to that inbox" {
  run apply fcommerce --include-unreviewed --dry-run --inbox 2
  [[ "$output" == *"inbox 2 greeting"* && "$output" != *"inbox 1 greeting"* ]]
}

@test "the state file holds hashes only, no message text" {
  apply fcommerce --include-unreviewed
  [ -s "$CLIENT/pack-state.json" ]
  ! grep -qE "Thank you|ধন্যবাদ" "$CLIENT/pack-state.json"
}

@test "starter questions are copied once and never overwritten" {
  apply fcommerce --include-unreviewed
  [ -f "$CLIENT/kb/faq.yaml" ]
  echo "edited" >>"$CLIENT/kb/faq.yaml"
  run apply fcommerce --include-unreviewed
  [[ "$output" == *"left untouched"* ]]
  [ "$(tail -n1 "$CLIENT/kb/faq.yaml")" = "edited" ]
}

@test "apply refuses a client that is not a local stack, and a missing Chatwoot gives a plain message" {
  sed -i 's/target: local/target: remote/' "$CLIENT/client.yaml"
  run apply fcommerce
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported yet"* ]]
  sed -i 's/target: remote/target: local/' "$CLIENT/client.yaml"
  kill "$FAKE"
  run apply fcommerce
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the client's Chatwoot"* ]]
}

@test "unknown options and unknown clients are refused" {
  run apply fcommerce --force
  [ "$status" -eq 2 ]
  run "$OPSKIT" pack apply nobody fcommerce
  [ "$status" -ne 0 ]
  [[ "$output" == *"client not found"* ]]
}

@test "pack review prints the Bangla on one page and approve flips only what it is told to" {
  export OPSKIT_PACKS_DIR="$BATS_TEST_TMPDIR/packs"
  mkdir -p "$OPSKIT_PACKS_DIR"
  cp -r "$ROOT/packs/clinic" "$OPSKIT_PACKS_DIR/"
  run "$OPSKIT" pack review clinic
  [[ "$output" == *"Saved reply \`appointment_ask\`"* && "$output" == *"- BN: "* ]]
  run "$OPSKIT" pack approve clinic --key appointment_ask
  [[ "$output" == *"approved 1 text(s)"* ]]
  [ "$(grep -c 'review_required: false' "$OPSKIT_PACKS_DIR/clinic/canned_responses.yaml")" -eq 1 ]
  run "$OPSKIT" pack approve clinic --all
  [ "$(grep -c 'review_required: true' "$OPSKIT_PACKS_DIR"/clinic/*.yaml "$OPSKIT_PACKS_DIR"/clinic/kb_starter/*.yaml | awk -F: '{s+=$2} END {print s}')" -eq 0 ]
  run "$OPSKIT" pack validate clinic
  [ "$status" -eq 0 ]
}

@test "approved Bangla is applied without the flag" {
  export OPSKIT_PACKS_DIR="$BATS_TEST_TMPDIR/packs"
  mkdir -p "$OPSKIT_PACKS_DIR"
  cp -r "$ROOT/packs/clinic" "$OPSKIT_PACKS_DIR/"
  "$OPSKIT" pack approve clinic --all >/dev/null
  run apply clinic
  [[ "$output" != *"not yet proofread"* ]]
  curl -s "http://127.0.0.1:$(cat "$PORT")/api/v1/accounts/1/canned_responses" | jq -e '.[] | select(.short_code == "appointment_ask_bn")' >/dev/null
}

@test "the pack code never calls a delete endpoint" {
  ! grep -qiE "DELETE|destroy" "$ROOT/lib/pack.sh" "$ROOT/lib/pack.py"
}
