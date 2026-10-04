#!/usr/bin/env bats

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  export OPSKIT_CLIENTS_DIR="$BATS_TEST_TMPDIR/clients"
  mkdir -p "$OPSKIT_CLIENTS_DIR"
  STACK="$OPSKIT_CLIENTS_DIR/demo/stack"
}

new_local() { "$OPSKIT" client new demo --domain chat.demo.localhost --name "Demo Store" --local; }

@test "client new creates a valid client.yaml and refuses duplicates" {
  run new_local
  [ "$status" -eq 0 ]
  [ -f "$OPSKIT_CLIENTS_DIR/demo/client.yaml" ]
  run new_local
  [ "$status" -ne 0 ]
}

@test "client new rejects an id that could escape the clients folder" {
  run "$OPSKIT" client new "../evil" --domain a.example.com
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/evil" ]
}

@test "rendered stack uses the CE tag, memory limits, no base service" {
  new_local
  run "$OPSKIT" client render demo
  [ "$status" -eq 0 ]
  grep -q 'image: chatwoot/chatwoot:v4.18.0-ce' "$STACK/docker-compose.yml"
  [ "$(grep -c 'mem_limit:' "$STACK/docker-compose.yml")" -ge 7 ]
  ! grep -qE '^  base:' "$STACK/docker-compose.yml"
  grep -q 'name: demo_postgres' "$STACK/docker-compose.yml"
  grep -q 'name: demo_storage' "$STACK/docker-compose.yml"
}

@test "only Caddy publishes ports" {
  new_local
  "$OPSKIT" client render demo
  [ "$(grep -c 'ports:' "$STACK/docker-compose.yml")" -eq 1 ]
  awk '/^  caddy:/{f=1} f&&/ports:/{print "caddy-has-ports"} /^  mailpit:/{f=0}' "$STACK/docker-compose.yml" | grep -q caddy-has-ports
}

@test "signup is off and the private-network webhook flag is set" {
  new_local
  "$OPSKIT" client render demo
  grep -q '^ENABLE_ACCOUNT_SIGNUP=false$' "$STACK/.env"
  grep -q '^SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true$' "$STACK/.env"
}

@test "secrets never appear in the compose file and env files are mode 600" {
  new_local
  "$OPSKIT" client render demo
  for name in POSTGRES_PASSWORD REDIS_PASSWORD SECRET_KEY_BASE AIBOT_WEBHOOK_SECRET; do
    value="$(sed -n "s/^${name}=//p" "$OPSKIT_CLIENTS_DIR/demo/secrets.env")"
    [ -n "$value" ]
    ! grep -q "$value" "$STACK/docker-compose.yml"
  done
  for f in .env aibot.env postgres.env redis.env; do
    [ "$(stat -c %a "$STACK/$f")" = "600" ]
  done
  [ "$(stat -c %a "$OPSKIT_CLIENTS_DIR/demo/secrets.env")" = "600" ]
}

@test "re-rendering is idempotent: same files, same secrets" {
  new_local
  "$OPSKIT" client render demo
  before="$(cd "$OPSKIT_CLIENTS_DIR/demo" && find . -type f -print0 | sort -z | xargs -0 sha256sum)"
  "$OPSKIT" client render demo
  after="$(cd "$OPSKIT_CLIENTS_DIR/demo" && find . -type f -print0 | sort -z | xargs -0 sha256sum)"
  [ "$before" = "$after" ]
}

@test "non-CE image tag is rejected" {
  new_local
  sed -i 's/tag: v4.18.0-ce/tag: v4.18.0/' "$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  run "$OPSKIT" client render demo
  [ "$status" -ne 0 ]
}

@test "shared_accounts is rejected at render time with the V2 message" {
  new_local
  sed -i 's/mode: dedicated/mode: shared_accounts/' "$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  run "$OPSKIT" client render demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"V2"* ]]
}

@test "remote target publishes 80/443 and has no mail catcher" {
  "$OPSKIT" client new shop --domain chat.shop.example.com --name Shop
  "$OPSKIT" client render shop
  grep -q '"80:80"' "$OPSKIT_CLIENTS_DIR/shop/stack/docker-compose.yml"
  grep -q '"443:443"' "$OPSKIT_CLIENTS_DIR/shop/stack/docker-compose.yml"
  ! grep -q mailpit "$OPSKIT_CLIENTS_DIR/shop/stack/docker-compose.yml"
  grep -q '^FRONTEND_URL=https://chat.shop.example.com$' "$OPSKIT_CLIENTS_DIR/shop/stack/.env"
}

@test "unresolved template variables fail the render" {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/validate.sh"
  . "$OPSKIT_ROOT/lib/secrets.sh"
  . "$OPSKIT_ROOT/lib/render.sh"
  printf 'a=${KNOWN}\nb=${FORGOTTEN}\n' >"$BATS_TEST_TMPDIR/t.tmpl"
  export KNOWN=1
  run render_template "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/t.out" KNOWN
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/t.out" ]
}

@test "ensure_secrets keeps existing values and sets mode 600" {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/validate.sh"
  . "$OPSKIT_ROOT/lib/secrets.sh"
  f="$BATS_TEST_TMPDIR/secrets.env"
  ensure_secrets "$f"
  first="$(cat "$f")"
  ensure_secrets "$f"
  [ "$first" = "$(cat "$f")" ]
  [ "$(stat -c %a "$f")" = "600" ]
  [ "$(wc -l <"$f")" -eq 5 ]
}

@test "secret generation aborts when openssl returns nothing" {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/validate.sh"
  . "$OPSKIT_ROOT/lib/secrets.sh"
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/fakebin/openssl"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/openssl"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run ensure_secrets "$BATS_TEST_TMPDIR/s.env"
  [ "$status" -ne 0 ]
}

@test "remote deploy is refused until Phase 11" {
  "$OPSKIT" client new shop --domain chat.shop.example.com --name Shop
  run "$OPSKIT" client deploy shop
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported yet"* ]]
}

@test "offboard refuses without --yes and with a wrong typed id" {
  new_local
  run "$OPSKIT" client offboard demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"--yes"* ]]
  OPSKIT_CONFIRM_ID=wrong run "$OPSKIT" client offboard demo --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "generated admin password meets Chatwoot's complexity rules" {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/validate.sh"
  . "$OPSKIT_ROOT/lib/secrets.sh"
  f="$BATS_TEST_TMPDIR/s.env"
  ensure_secrets "$f"
  pw="$(sed -n 's/^ADMIN_PASSWORD=//p' "$f")"
  [ "${#pw}" -ge 12 ]
  [[ "$pw" =~ [A-Z] ]]
  [[ "$pw" =~ [a-z] ]]
  [[ "$pw" =~ [0-9] ]]
  [[ "$pw" =~ [^A-Za-z0-9] ]]
}

@test "empty SMTP credentials are not written (Chatwoot would try to log in)" {
  new_local
  "$OPSKIT" client render demo
  ! grep -q '^SMTP_USERNAME=' "$STACK/.env"
  ! grep -q '^SMTP_PASSWORD=' "$STACK/.env"
  ! grep -q '^SMTP_AUTHENTICATION=' "$STACK/.env"
  grep -q '^SMTP_ADDRESS=mailpit$' "$STACK/.env"
}

@test "configured SMTP user writes the login lines" {
  "$OPSKIT" client new shop --domain chat.shop.example.com --name Shop
  printf 'smtp:\n  host: smtp.example.com\n  port: 587\n  user: apikey\n' >>"$OPSKIT_CLIENTS_DIR/shop/client.yaml"
  SMTP_PASSWORD=s3cret-pw "$OPSKIT" client render shop
  grep -q '^SMTP_USERNAME=apikey$' "$OPSKIT_CLIENTS_DIR/shop/stack/.env"
  grep -q '^SMTP_AUTHENTICATION=plain$' "$OPSKIT_CLIENTS_DIR/shop/stack/.env"
}

@test "render writes a nightly backup cron line in the client's time zone" {
  new_local
  "$OPSKIT" client render demo
  f="$OPSKIT_CLIENTS_DIR/demo/backup.cron"
  grep -q '^CRON_TZ=Asia/Dhaka$' "$f"
  grep -qE '^0 2 \* \* \* root flock -n /var/lock/opskit-backup-demo.lock .*/bin/opskit backup run demo ' "$f"
  ! grep -q '\${' "$f"
}

@test "a custom backup schedule is used in the cron line" {
  new_local
  printf 'backup:\n  schedule: "30 3 * * *"\n' >>"$OPSKIT_CLIENTS_DIR/demo/client.yaml"
  "$OPSKIT" client render demo
  grep -qE '^30 3 \* \* \* root flock' "$OPSKIT_CLIENTS_DIR/demo/backup.cron"
}
