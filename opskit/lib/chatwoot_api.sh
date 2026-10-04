#!/usr/bin/env bash
# Chatwoot API access (project rule: all API calls go through this file): timeouts, retries on 429/5xx,
# the token never appears on a command line or in logs. Needs lib/log.sh.
# Env: CW_BASE_URL, CW_TOKEN (never printed), CW_RESOLVE=host:port:ip (optional), CW_INSECURE=1 (local test certs only)
# shellcheck shell=bash

# cw_request METHOD PATH [extra curl args...] -> body on stdout; returns 0 on 2xx/3xx, 1 otherwise
cw_request() {
  local method="$1" path="$2" tries=0 code body hdr args=()
  shift 2
  [ -n "${CW_BASE_URL:-}" ] || { log_error "CW_BASE_URL not set"; return 1; }
  hdr="$(mktemp)"
  chmod 600 "$hdr"
  # shellcheck disable=SC2064
  trap "rm -f '$hdr'" RETURN
  [ -z "${CW_TOKEN:-}" ] || printf 'api-access-token: %s\n' "$CW_TOKEN" >"$hdr"
  [ -z "${CW_RESOLVE:-}" ] || args+=(--resolve "$CW_RESOLVE")
  [ "${CW_INSECURE:-0}" != "1" ] || args+=(-k)
  body="$(mktemp)"
  while [ "$tries" -lt 3 ]; do
    code="$(curl -sS --max-time 20 -o "$body" -w '%{http_code}' -X "$method" -H "@$hdr" "${args[@]}" "$@" "${CW_BASE_URL}${path}" 2>/dev/null || true)"
    code="${code:-000}"
    case "$code" in 429 | 5* | 000) tries=$((tries + 1)); sleep 2 ;; *) break ;; esac
  done
  cat "$body"
  rm -f "$body"
  case "$code" in 2* | 3*) return 0 ;; *) log_error "API ${method} ${path} -> HTTP ${code}"; return 1 ;; esac
}

# cw_admin_token ID -> prints the Super Admin's API token (via the rails container; never logged)
cw_admin_token() {
  local id="$1" email
  email="$(_cfg '.contact.email // ""' "$id")"
  [ -n "$email" ] || email="admin@$(_cfg '.domain' "$id")"
  ADMIN_EMAIL="$email" dc "$id" exec -T -e ADMIN_EMAIL rails bundle exec rails runner \
    'puts "TOKEN=" + User.find_by!(email: ENV.fetch("ADMIN_EMAIL")).access_token.token' 2>/dev/null \
    | sed -n 's/^TOKEN=//p' | tail -n1
}

# cw_use_stack ID -> sets CW_BASE_URL / CW_RESOLVE / CW_INSECURE / CW_TOKEN for a local stack
cw_use_stack() {
  local id="$1" host port
  host="$(_cfg '.domain' "$id")"
  port="$(_cfg '.deploy.https_port // 8443' "$id")"
  export CW_BASE_URL CW_RESOLVE CW_INSECURE CW_TOKEN
  CW_BASE_URL="$(_frontend_url "$id")"
  CW_RESOLVE="${host}:${port}:127.0.0.1"
  CW_INSECURE=1
  CW_TOKEN="$(cw_admin_token "$id")"
  [ -n "$CW_TOKEN" ] || { log_error "could not obtain the admin API token"; return 1; }
}

# cw_seed_demo -> creates an API inbox, a contact, a conversation and a message with a small PNG attachment.
# Uses only fictional data. Prints "conversation_id=<n>". Requires cw_use_stack first.
cw_seed_demo() {
  local account inbox_json inbox_id ident contact src conv png msg
  account="$(cw_request GET /api/v1/profile | jq -r '.accounts[0].id')" || return 1
  inbox_json="$(cw_request POST "/api/v1/accounts/${account}/inboxes" -H 'Content-Type: application/json' \
    -d '{"name":"Demo API inbox","channel":{"type":"api"}}')" || return 1
  inbox_id="$(printf '%s' "$inbox_json" | jq -r .id)"
  ident="$(printf '%s' "$inbox_json" | jq -r .inbox_identifier)"
  if [ -z "$ident" ] || [ "$ident" = "null" ]; then
    log_error "inbox identifier missing"
    return 1
  fi
  contact="$(cw_request POST "/public/api/v1/inboxes/${ident}/contacts" -H 'Content-Type: application/json' -d '{"name":"Demo Customer"}')" || return 1
  src="$(printf '%s' "$contact" | jq -r .source_id)"
  conv="$(cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations" -H 'Content-Type: application/json' -d '{}')" || return 1
  conv="$(printf '%s' "$conv" | jq -r .id)"
  png="$(mktemp --suffix=.png)"
  printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d >"$png"
  msg="$(cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations/${conv}/messages" \
    -F 'content=demo photo' -F "attachments[]=@${png};type=image/png")" || { rm -f "$png"; return 1; }
  rm -f "$png"
  printf '%s' "$msg" | jq -e '.id' >/dev/null || return 1
  printf 'conversation_id=%s inbox_id=%s\n' "$conv" "$inbox_id"
}
