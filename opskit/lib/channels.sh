#!/usr/bin/env bash
# `opskit channels check <id>`: tests every connected channel and prints PASS / WARN / FAIL with a fix hint.
# Everything it learns comes from the Chatwoot API (monitoring user) plus read-only probes. Never prints tokens,
# passwords or message text. Needs the other libs sourced (see bin/opskit): health, channels_health, chatwoot_api, ...
# shellcheck shell=bash

CH_FAILS=0 CH_WARNS=0 CH_PASSES=0
CH_SEND_TEST=0

# _row LABEL CHECK STATUS DETAIL [HINT_KEY [HINT_EXTRA]]
_row() {
  local hint=""
  printf '%-38s %-28s %-5s %s\n' "$1" "$2" "$3" "$4"
  case "$3" in PASS) CH_PASSES=$((CH_PASSES + 1)) ;; WARN) CH_WARNS=$((CH_WARNS + 1)) ;; FAIL) CH_FAILS=$((CH_FAILS + 1)) ;; esac
  if [ "$3" != "PASS" ] && [ -n "${5:-}" ]; then
    hint="$(_ch_hint "$5")"
    printf '    fix: %s%s\n' "$hint" "${6:+ ($6)}"
  fi
  return 0
}

# _ch_curl ID PATH [curl args] -> uses the client's HTTPS address (test certificate accepted on local stacks)
_ch_status() { _hc_curl "$@" -o /dev/null -w '%{http_code}' 2>/dev/null || true; }

# _ch_secret_get ID PATH_WITH_SECRET [curl args] -> GET where the URL contains a secret: the URL goes to curl on
# stdin (config), never on the command line. Prints the body.
_ch_secret_get() {
  local id="$1" path="$2" host port base
  shift 2
  base="$(_frontend_url "$id")"
  host="$(_cfg '.domain' "$id")"
  port="$(_cfg '.deploy.https_port // 8443' "$id")"
  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ]; then
    printf 'url = "%s%s"\n' "$base" "$path" | curl -ks --max-time 15 --resolve "${host}:${port}:127.0.0.1" -K - "$@"
  else
    printf 'url = "%s%s"\n' "$base" "$path" | curl -s --max-time 15 -K - "$@"
  fi
}

# _runner ID ENV=VAL... < script -> output of a read-only rails runner script
_runner() {
  local id="$1" args=() kv
  shift
  for kv in "$@"; do args+=(-e "$kv"); done
  dc "$id" exec -T "${args[@]}" rails bundle exec rails runner - <"$OPSKIT_ROOT/templates/rails/read_channel_secret.rb" 2>/dev/null || true
}

# ---- website widget ------------------------------------------------------------------------------------------------------
# widget_round_trip ID WEBSITE_TOKEN -> prints "ok" or a short reason; everything created is deleted again
widget_round_trip() {
  local id="$1" tk="$2" cfg at hdr msg conv contact account acct_ok=0
  cfg="$(_hc_curl "$id" "/api/v1/widget/config?website_token=${tk}" -X POST -H 'Content-Type: application/json' -d '{"locale":"en"}' || true)"
  at="$(printf '%s' "$cfg" | jq -r '.website_channel_config.auth_token // empty' 2>/dev/null || true)"
  [ -n "$at" ] || { echo "the widget did not give a visitor session"; return 1; }
  hdr="$(mktemp)"
  chmod 600 "$hdr"
  printf 'X-Auth-Token: %s\n' "$at" >"$hdr"
  msg="$(_hc_curl "$id" "/api/v1/widget/messages?website_token=${tk}&locale=en" -X POST -H "@$hdr" -H 'Content-Type: application/json' \
    -d '{"message":{"content":"opskit channel check","timestamp":"2026-01-01T00:00:00.000Z"}}' || true)"
  rm -f "$hdr"
  conv="$(printf '%s' "$msg" | jq -r '.conversation_id // empty' 2>/dev/null || true)"
  [ -n "$conv" ] || { echo "the visitor's message was not accepted"; return 1; }
  account="$(cw_request GET /api/v1/profile 2>/dev/null | jq -r '.accounts[0].id // empty' || true)"
  if [ -n "$account" ]; then
    contact="$(cw_request GET "/api/v1/accounts/${account}/conversations/${conv}" 2>/dev/null | jq -r '.meta.sender.id // empty' || true)"
    cw_request DELETE "/api/v1/accounts/${account}/conversations/${conv}" >/dev/null 2>&1 && acct_ok=1
    [ -z "$contact" ] || cw_request DELETE "/api/v1/accounts/${account}/contacts/${contact}" >/dev/null 2>&1 || true
  fi
  [ "$acct_ok" -eq 1 ] || { echo "message arrived but the test conversation could not be removed"; return 0; }
  echo ok
}

ch_widget() { # ID INBOX_JSON
  local id="$1" j="$2" label tk code
  label="$(jq -r '"\(.name) (widget)"' <<<"$j")"
  tk="$(jq -r '.website_token // empty' <<<"$j")"
  [ -n "$tk" ] || { _row "$label" "website token" FAIL "inbox has no website token" widget_page; return; }
  code="$(_ch_status "$id" "/widget?website_token=${tk}")"
  if [ "$code" = "200" ]; then _row "$label" "widget page" PASS "HTTP 200"; else _row "$label" "widget page" FAIL "HTTP ${code:-none}" widget_page; fi
  code="$(_ch_status "$id" /packs/js/sdk.js)"
  if [ "$code" = "200" ]; then _row "$label" "embed script (sdk.js)" PASS "HTTP 200"; else _row "$label" "embed script (sdk.js)" FAIL "HTTP ${code:-none}" widget_page; fi
  if _ch_cable "$id"; then _row "$label" "live updates (WebSocket)" PASS "101 Switching Protocols"; else _row "$label" "live updates (WebSocket)" FAIL "handshake failed" widget_cable; fi
  local rt
  if rt="$(widget_round_trip "$id" "$tk")"; then
    if [ "$rt" = "ok" ]; then _row "$label" "visitor message round trip" PASS "conversation created and removed"; else _row "$label" "visitor message round trip" WARN "$rt" widget_roundtrip; fi
  else
    _row "$label" "visitor message round trip" FAIL "$rt" widget_roundtrip
  fi
}

_ch_cable() { # ID -> 0 if /cable upgrades to a WebSocket
  local id="$1" origin first
  origin="$(_frontend_url "$id")"
  first="$(_hc_curl "$id" /cable -i --http1.1 --max-time 4 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==' -H "Origin: ${origin}" 2>/dev/null | head -n1 || true)"
  case "$first" in *101*) return 0 ;; *) return 1 ;; esac
}

# ---- API inbox ---------------------------------------------------------------------------------------------------------------
ch_api() { # ID INBOX_JSON
  local id="$1" j="$2" label ident contact src conv account cid rc="" ok=0
  label="$(jq -r '"\(.name) (API)"' <<<"$j")"
  ident="$(jq -r '.inbox_identifier // empty' <<<"$j")"
  [ -n "$ident" ] || { _row "$label" "inbox identifier" FAIL "missing" api_roundtrip; return; }
  contact="$(CW_TOKEN="" cw_request POST "/public/api/v1/inboxes/${ident}/contacts" -H 'Content-Type: application/json' -d '{"name":"opskit channel check"}' 2>/dev/null || true)"
  src="$(jq -r '.source_id // empty' <<<"$contact" 2>/dev/null || true)"
  cid="$(jq -r '.id // empty' <<<"$contact" 2>/dev/null || true)"
  if [ -n "$src" ]; then
    conv="$(CW_TOKEN="" cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations" -H 'Content-Type: application/json' -d '{}' 2>/dev/null | jq -r '.id // empty' || true)"
    if [ -n "$conv" ] && CW_TOKEN="" cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations/${conv}/messages" \
      -H 'Content-Type: application/json' -d '{"content":"opskit channel check"}' >/dev/null 2>&1; then ok=1; fi
    account="$(cw_request GET /api/v1/profile 2>/dev/null | jq -r '.accounts[0].id // empty' || true)"
    if [ -n "$account" ]; then
      [ -z "$conv" ] || cw_request DELETE "/api/v1/accounts/${account}/conversations/${conv}" >/dev/null 2>&1 || true
      [ -z "$cid" ] || cw_request DELETE "/api/v1/accounts/${account}/contacts/${cid}" >/dev/null 2>&1 || true
    fi
  fi
  rc="$([ "$ok" -eq 1 ] && echo ok || echo fail)"
  if [ "$rc" = "ok" ]; then _row "$label" "message round trip" PASS "conversation created and removed"; else _row "$label" "message round trip" FAIL "test message was not accepted" api_roundtrip; fi
}

# ---- email -------------------------------------------------------------------------------------------------------------------------
_probe_status() { jq -r '.status // "error"' <<<"$1" 2>/dev/null || echo error; }
_probe_detail() { jq -r '.detail // ""' <<<"$1" 2>/dev/null || true; }

ch_email() { # ID INBOX_JSON
  local id="$1" j="$2" label res st provider imap_on smtp_on fwd cfg
  label="$(jq -r '"\(.name) (email)"' <<<"$j")"
  provider="$(jq -r '.provider // ""' <<<"$j")"
  imap_on="$(jq -r '.imap_enabled // false' <<<"$j")"
  smtp_on="$(jq -r '.smtp_enabled // false' <<<"$j")"
  fwd="$(jq -r '.forwarding_enabled // false' <<<"$j")"
  if [ "$provider" = "google" ] || [ "$provider" = "microsoft" ]; then
    if [ "$(jq -r '.reauthorization_required // false' <<<"$j")" = "true" ]; then
      _row "$label" "sign-in (${provider})" FAIL "needs to be re-authorized" meta_reauth
    else
      _row "$label" "sign-in (${provider})" PASS "connected through ${provider}"
    fi
    return
  fi
  if [ "$imap_on" != "true" ] && [ "$fwd" != "true" ]; then
    _row "$label" "can receive mail" FAIL "neither IMAP nor forwarding is on" email_no_receive
  elif [ "$imap_on" != "true" ]; then
    _row "$label" "can receive mail" PASS "through forwarding"
  fi
  cfg="$(jq -c '{email, imap_address, imap_port, imap_login, imap_password, imap_enable_ssl, imap_openssl_verify_mode: .imap_openssl_verify_mode, smtp_address, smtp_port, smtp_login, smtp_password, smtp_enable_ssl_tls, smtp_enable_starttls_auto, smtp_openssl_verify_mode}' <<<"$j")"
  if [ "$imap_on" = "true" ]; then
    res="$(printf '%s' "$cfg" | python3 "$OPSKIT_ROOT/lib/mail_probe.py" imap)"
    st="$(_probe_status "$res")"
    case "$st" in
      ok) _row "$label" "incoming mail (IMAP)" PASS "$(_probe_detail "$res")" ;;
      auth_failed) _row "$label" "incoming mail (IMAP)" FAIL "login rejected" email_auth ;;
      tls_error) _row "$label" "incoming mail (IMAP)" WARN "$(_probe_detail "$res")" email_tls ;;
      timeout) _row "$label" "incoming mail (IMAP)" FAIL "no answer in time" email_timeout ;;
      *) _row "$label" "incoming mail (IMAP)" FAIL "$(_probe_detail "$res")" email_connect ;;
    esac
  fi
  if [ "$smtp_on" = "true" ]; then
    res="$(printf '%s' "$cfg" | python3 "$OPSKIT_ROOT/lib/mail_probe.py" smtp)"
    st="$(_probe_status "$res")"
    case "$st" in
      ok) _row "$label" "outgoing mail (SMTP)" PASS "$(_probe_detail "$res")" ;;
      auth_failed) _row "$label" "outgoing mail (SMTP)" FAIL "login rejected" email_auth ;;
      tls_error) _row "$label" "outgoing mail (SMTP)" WARN "$(_probe_detail "$res")" email_tls ;;
      timeout) _row "$label" "outgoing mail (SMTP)" FAIL "no answer in time" email_timeout ;;
      *) _row "$label" "outgoing mail (SMTP)" FAIL "$(_probe_detail "$res")" email_connect ;;
    esac
  else
    _row "$label" "outgoing mail (SMTP)" WARN "not configured: replies use the server's default mail settings" ""
  fi
  if [ "$CH_SEND_TEST" -eq 1 ] && [ "$imap_on" = "true" ] && [ "$smtp_on" = "true" ]; then
    res="$(printf '%s' "$cfg" | python3 "$OPSKIT_ROOT/lib/mail_probe.py" loopback)"
    st="$(_probe_status "$res")"
    case "$st" in
      ok) _row "$label" "test mail to itself" PASS "$(_probe_detail "$res")" ;;
      not_seen) _row "$label" "test mail to itself" WARN "$(_probe_detail "$res")" email_not_seen ;;
      auth_failed) _row "$label" "test mail to itself" FAIL "login rejected" email_auth ;;
      *) _row "$label" "test mail to itself" FAIL "$(_probe_detail "$res")" email_connect ;;
    esac
  fi
}

ch_unknown() { # INBOX_JSON
  _row "$(jq -r '"\(.name) (\(.channel_type | sub("^Channel::"; "")))"' <<<"$1")" "automatic check" WARN "not available yet" no_checker
}

# channels_check ID [--send-test] [--inbox N] -> exit 1 if any FAIL
channels_check() {
  local id="$1" only="" body acct n j type
  shift
  CH_FAILS=0 CH_WARNS=0 CH_PASSES=0 CH_SEND_TEST=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --send-test) CH_SEND_TEST=1; shift ;;
      --inbox) only="${2:-}"; shift 2 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  _require_local "$id"
  cw_use_monitor "$id" || { log_error "monitoring user is not set up: run a deploy first"; return 1; }
  acct="$(cw_request GET /api/v1/profile 2>/dev/null | jq -r '.accounts[0].id // empty' || true)"
  [ -n "$acct" ] || { log_error "the Chatwoot API did not answer (is the stack up? opskit monitor status ${id})"; return 1; }
  body="$(cw_request GET "/api/v1/accounts/${acct}/inboxes" 2>/dev/null || true)"
  n="$(jq -r '.payload | length' <<<"$body" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 0 ]; then
    echo "No channels are connected yet for ${id}. See: opskit channels plan ${id}"
    return 0
  fi
  printf '%-38s %-28s %-5s %s\n' CHANNEL CHECK RESULT DETAIL
  while IFS= read -r j; do
    [ -z "$only" ] || [ "$(jq -r .id <<<"$j")" = "$only" ] || continue
    type="$(jq -r '.channel_type // ""' <<<"$j")"
    case "$type" in
      Channel::WebWidget) ch_widget "$id" "$j" ;;
      Channel::Api) ch_api "$id" "$j" ;;
      Channel::Email) ch_email "$id" "$j" ;;
      Channel::Telegram) ch_telegram "$id" "$j" ;;
      Channel::Whatsapp) ch_whatsapp "$id" "$j" ;;
      Channel::FacebookPage | Channel::Instagram) ch_meta "$id" "$j" ;;
      *) ch_unknown "$j" ;;
    esac
  done < <(jq -c '.payload[]' <<<"$body")
  printf '\nSummary: %s PASS, %s WARN, %s FAIL\n' "$CH_PASSES" "$CH_WARNS" "$CH_FAILS"
  [ "$CH_FAILS" -eq 0 ]
}
