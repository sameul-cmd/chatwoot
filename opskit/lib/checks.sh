#!/usr/bin/env bash
# Post-deploy checks (SPEC 7.5) with a PASS/FAIL table. Requires deploy.sh helpers.
# shellcheck shell=bash

_CHECK_FAILS=0
_check() { # NAME STATUS DETAIL
  printf '%-34s %-5s %s\n' "$1" "$2" "$3"
  [ "$2" = "FAIL" ] && _CHECK_FAILS=$((_CHECK_FAILS + 1))
  return 0
}

_https_base() { _frontend_url "$1"; }

_curl() { # ID path [extra curl args] -> uses --resolve so the client domain works locally with Caddy's internal CA
  local id="$1" path="$2" url host port
  shift 2
  url="$(_https_base "$id")"
  host="$(_cfg '.domain' "$id")"
  port="$(_cfg '.deploy.https_port // 8443' "$id")"
  curl -ks --max-time 15 --resolve "${host}:${port}:127.0.0.1" "$@" "${url}${path}"
}

post_deploy_checks() {
  local id="$1" out code subject tries=0 count dir origin
  _CHECK_FAILS=0
  dir="$(client_dir "$id")"
  printf '%-34s %-5s %s\n' CHECK RESULT DETAIL

  code="$(_curl "$id" /app/login -o /dev/null -w '%{http_code}')"
  if [ "$code" = "200" ]; then _check "login page via Caddy (HTTPS)" PASS "HTTP 200"; else _check "login page via Caddy (HTTPS)" FAIL "HTTP ${code:-none}"; fi

  out="$(_curl "$id" /api)"
  case "$out" in *'"queue_services":"ok"'*'"data_services":"ok"'*) _check "health /api (db + redis)" PASS "ok" ;; *) _check "health /api (db + redis)" FAIL "${out:0:80}" ;; esac

  code="$(_curl "$id" /packs/js/sdk.js -o /dev/null -w '%{http_code}')"
  if [ "$code" = "200" ]; then _check "widget script (sdk.js)" PASS "HTTP 200"; else _check "widget script (sdk.js)" FAIL "HTTP ${code:-none}"; fi

  origin="$(_https_base "$id")"
  out="$(_curl "$id" /cable -i --http1.1 --max-time 4 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==' -H "Origin: ${origin}" 2>/dev/null | head -n1 || true)"
  case "$out" in *101*) _check "websocket /cable through Caddy" PASS "101 Switching Protocols" ;; *) _check "websocket /cable through Caddy" FAIL "${out:0:60}" ;; esac

  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ]; then
    subject="opskit-check-$(date +%s)"
    load_secrets "$dir/secrets.env"
    dc "$id" exec -T -e TEST_SUBJECT="$subject" -e TEST_TO=ops-check@example.test rails bundle exec rails runner - \
      <"$OPSKIT_ROOT/templates/rails/send_test_mail.rb" >/dev/null 2>&1 || true
    count=0
    while [ "$tries" -lt 24 ] && [ "$count" -eq 0 ]; do
      sleep 5
      tries=$((tries + 1))
      count="$(dc "$id" exec -T rails ruby -rnet/http -rjson -e \
        "puts JSON.parse(Net::HTTP.get(URI('http://mailpit:8025/api/v1/messages'))).fetch('messages').count { |m| m['Subject'] == '${subject}' }" 2>/dev/null | tail -n1)"
      count="${count:-0}"
    done
    if [ "$count" -ge 1 ]; then
      _check "sidekiq job + test email (Mailpit)" PASS "email delivered"
    else
      _check "sidekiq job + test email (Mailpit)" FAIL "no email within 2 min (sidekiq or SMTP broken)"
    fi
  else
    _check "sidekiq job + test email" WARN "remote target: send a test email to a real inbox manually"
  fi
  [ "$_CHECK_FAILS" -eq 0 ]
}
