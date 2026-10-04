#!/usr/bin/env bats
# The bot's opskit side (Phase 8): render, llm commands, bot command refusals. The live Chatwoot flow is in `opskit selftest`.

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  ROOT="$BATS_TEST_DIRNAME/.."
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  "$OPSKIT" client new shop --domain chat.shop.example.com --name "Shop BD" --local >/dev/null 2>&1
  CLIENT="$OPSKIT_CLIENTS_DIR/shop"
  LOG="$BATS_TEST_TMPDIR/llm.log"
  PORT="$BATS_TEST_TMPDIR/port"
  python3 "$ROOT/tests/fake_llm.py" "$PORT" "$LOG" &
  FAKE=$!
  for _ in $(seq 1 50); do [ -s "$PORT" ] && break; sleep 0.1; done
  URL="http://127.0.0.1:$(cat "$PORT")/v1"
  export AIBOT_LLM_API_KEY="sk-bats-secret-key"
}

teardown() {
  kill "$FAKE" 2>/dev/null || true
}

@test "without a bot the render writes an empty bot.yaml, no AI lines, demo mode, and a kb folder" {
  run "$OPSKIT" client render shop
  [ "$status" -eq 0 ]
  grep -q "the bot is not set up" "$CLIENT/stack/bot.yaml"
  grep -q '^AIBOT_MODE=demo$' "$CLIENT/stack/aibot.env"
  ! grep -q "AIBOT_LLM" "$CLIENT/stack/aibot.env"
  [ -d "$CLIENT/kb" ]
  grep -q "./bot.yaml:/config/bot.yaml:ro" "$CLIENT/stack/docker-compose.yml"
  grep -q "../kb:/kb:ro" "$CLIENT/stack/docker-compose.yml"
}

@test "set-key stores the key privately, saves the endpoint, and never prints or writes the key elsewhere" {
  run "$OPSKIT" llm set-key shop --base-url "$URL" --paid
  [ "$status" -eq 0 ]
  [[ "$output" != *"sk-bats-secret-key"* ]]
  [ "$(stat -c %a "$CLIENT/llm.env")" = 600 ]
  grep -q "^AIBOT_LLM_API_KEY=sk-bats-secret-key$" "$CLIENT/llm.env"
  ! grep -rq "sk-bats-secret-key" "$CLIENT/client.yaml" "$CLIENT/stack/bot.yaml"
  [ "$(yq -r .bot.llm.base_url "$CLIENT/client.yaml")" = "$URL" ]
  [ "$(yq -r .bot.llm.paid_tier "$CLIENT/client.yaml")" = true ]
}

@test "set-key without --paid warns that a real client will be refused" {
  run "$OPSKIT" llm set-key shop --base-url "$URL"
  [[ "$output" == *"paid-tier not stated"* ]]
  [ "$(yq -r '.bot.llm.paid_tier // false' "$CLIENT/client.yaml")" = false ]
}

@test "set-key refuses a bad address and a missing key" {
  run "$OPSKIT" llm set-key shop --base-url "not a url"
  [ "$status" -eq 2 ]
  unset AIBOT_LLM_API_KEY
  run bash -c '"$1" llm set-key shop --base-url "$2" </dev/null' _ "$OPSKIT" "$URL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no key given"* ]]
}

@test "models lists the service's models, marks the chosen one, and model/effort/embedding-model write client.yaml" {
  "$OPSKIT" llm set-key shop --base-url "$URL" --paid >/dev/null 2>&1
  run "$OPSKIT" llm models shop
  [[ "$output" == *"fake-chat"* && "$output" == *"fake-embed"* ]]
  run "$OPSKIT" llm model shop fake-chat
  [ "$status" -eq 0 ]
  run "$OPSKIT" llm models shop
  [[ "$output" == *"* fake-chat  (selected)"* ]]
  "$OPSKIT" llm effort shop max >/dev/null 2>&1
  "$OPSKIT" llm embedding-model shop fake-embed >/dev/null 2>&1
  [ "$(yq -r .bot.llm.effort "$CLIENT/client.yaml")" = max ]
  [ "$(yq -r .bot.embeddings.model "$CLIENT/client.yaml")" = fake-embed ]
  "$OPSKIT" llm embedding-model shop none >/dev/null 2>&1
  [ "$(yq -r '.bot.embeddings // "gone"' "$CLIENT/client.yaml")" = gone ]
  grep -q '"auth": true' "$LOG"   # the key was sent to the service as a bearer token
}

@test "an unknown model is saved with a warning, an invalid effort lists the valid values" {
  "$OPSKIT" llm set-key shop --base-url "$URL" --paid >/dev/null 2>&1
  run "$OPSKIT" llm model shop not-a-real-model
  [[ "$output" == *"not in the service's model list"* ]]
  run "$OPSKIT" llm effort shop ultra
  [ "$status" -eq 2 ]
  [[ "$output" == *"none low medium high max"* ]]
}

@test "after set-key the render has the bot lines, the key goes into the container env only, and bot.yaml has no key" {
  "$OPSKIT" llm set-key shop --base-url "$URL" --paid >/dev/null 2>&1
  "$OPSKIT" llm model shop fake-chat >/dev/null 2>&1
  yq -y -i '.bot.enabled = true' "$CLIENT/client.yaml"
  "$OPSKIT" client render shop >/dev/null 2>&1
  grep -q "^AIBOT_CONFIG=/config/bot.yaml$" "$CLIENT/stack/aibot.env"
  grep -q "^AIBOT_LLM_MODEL=fake-chat$" "$CLIENT/stack/aibot.env"
  grep -q "^AIBOT_LLM_TIER_PAID=true$" "$CLIENT/stack/aibot.env"
  grep -q "^AIBOT_BUSINESS_NAME=Shop BD$" "$CLIENT/stack/aibot.env"
  [ "$(stat -c %a "$CLIENT/stack/aibot.env")" = 600 ]
  [ "$(yq -r .llm.model "$CLIENT/stack/bot.yaml")" = fake-chat ]
  [ "$(yq -r '.llm.paid_tier // "stripped"' "$CLIENT/stack/bot.yaml")" = stripped ]
}

@test "bot enable refuses: no inbox, no AI service, no model chosen, not a local client" {
  run "$OPSKIT" bot enable shop
  [ "$status" -eq 2 ]
  run "$OPSKIT" bot enable shop --inbox 1
  [[ "$output" == *"the AI service is not set up"* ]]
  "$OPSKIT" llm set-key shop --base-url "$URL" --paid >/dev/null 2>&1
  run "$OPSKIT" bot enable shop --inbox 1
  [[ "$output" == *"no model chosen"* ]]
  run "$OPSKIT" bot enable shop --inbox one
  [ "$status" -ne 0 ]
  sed -i 's/target: local/target: remote/' "$CLIENT/client.yaml"
  run "$OPSKIT" bot enable shop --inbox 1
  [[ "$output" == *"not supported yet"* ]]
}

@test "unknown clients and options are refused" {
  run "$OPSKIT" bot enable nobody --inbox 1
  [[ "$output" == *"client not found"* ]]
  run "$OPSKIT" bot enable shop --force
  [ "$status" -eq 2 ]
  run "$OPSKIT" llm models nobody
  [[ "$output" == *"client not found"* ]]
}

@test "bot.yaml accepts the new settings and rejects a wrong one" {
  cat >"$BATS_TEST_TMPDIR/bot.yaml" <<'YAML'
llm: {base_url: "https://x.example/v1", model: m}
messages: {handoff: {en: "We will get back to you.", bn: "আমরা যোগাযোগ করব।"}}
messages_bn_approved: true
embeddings: {model: e, min_similarity: 0.4}
upset_words: {en: ["scam"], bn: ["প্রতারণা"]}
YAML
  run "$OPSKIT" bot validate "$BATS_TEST_TMPDIR/bot.yaml"
  [ "$status" -eq 0 ]
  sed -i 's/min_similarity: 0.4/min_similarity: 3/' "$BATS_TEST_TMPDIR/bot.yaml"
  run "$OPSKIT" bot validate "$BATS_TEST_TMPDIR/bot.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"embeddings.min_similarity"* ]]
}

@test "the bot code never logs message text and the docker command turns the access log off" {
  grep -q -- "--no-access-log" "$ROOT/../aibot/Dockerfile"
  ! grep -rnE "log\.(info|warning|error|debug|exception)\(.*(event\.text|\.content|\.answer)" "$ROOT/../aibot/src/aibot"
}
