#!/usr/bin/env bash
# Channel health poller (SPEC 9): lists inboxes through the API with the monitoring user and reports any inbox that
# Chatwoot flags as `reauthorization_required` (email, Facebook, Instagram, WhatsApp embedded sign-up).
# Output lines: name|severity|reason, one per inbox, only inbox id/name/type (never contact data or message text).
# Needs lib/chatwoot_api.sh, deploy.sh, health.sh sourced first.
# shellcheck shell=bash

monitor_env_file() { printf '%s/monitor.env' "$(client_dir "$1")"; }

# ensure_monitor_user ID -> creates the ops-monitor user once and stores its token in monitor.env (mode 600)
ensure_monitor_user() {
  local id="$1" f email raw token
  f="$(monitor_env_file "$id")"
  [ ! -s "$f" ] || return 0
  email="ops-monitor@$(_cfg '.domain' "$id")"
  raw="$(MONITOR_EMAIL="$email" dc "$id" exec -T -e MONITOR_EMAIL rails bundle exec rails runner - \
    <"$OPSKIT_ROOT/templates/rails/ensure_monitor.rb" 2>/dev/null || true)"
  token="$(printf '%s\n' "$raw" | sed -n 's/^MONITOR_TOKEN=//p' | tail -n1)"
  [[ "$token" =~ ^[A-Za-z0-9]{16,}$ ]] || { log_error "could not create the monitoring user"; return 1; }
  (umask 077 && printf 'MONITOR_EMAIL=%s\nMONITOR_TOKEN=%s\n' "$email" "$token" >"$f")
  chmod 600 "$f"
  log_info "monitoring user ready (token saved to monitor.env, mode 600)"
}

_clean_name() { printf '%s' "$1" | tr -d '\000-\037' | cut -c1-60; }

# parse_inboxes_json < json -> check lines (pure; used by tests)
parse_inboxes_json() {
  jq -r '.payload[]? | [(.id|tostring), (.name // "inbox"), (.channel_type // "channel" | sub("^Channel::"; "")), ((.reauthorization_required // false)|tostring)] | @tsv' \
    | while IFS=$'\t' read -r iid name type reauth; do
        name="$(_clean_name "$name")"
        if [ "$reauth" = "true" ]; then
          printf 'channel-%s|critical|Inbox "%s" (%s) needs to be re-connected\n' "$iid" "$name" "$type"
        else
          printf 'channel-%s|ok|Inbox "%s" (%s) connected\n' "$iid" "$name" "$type"
        fi
      done
}

channels_health() {
  local id="$1" f token acct body
  f="$(monitor_env_file "$id")"
  token="$(sed -n 's/^MONITOR_TOKEN=//p' "$f" 2>/dev/null | head -n1)"
  if [ -z "$token" ]; then
    echo "channels_api|warn|monitoring user is not set up (run a deploy)"
    return 0
  fi
  export CW_BASE_URL CW_RESOLVE CW_INSECURE CW_TOKEN
  CW_BASE_URL="$(_frontend_url "$id")"
  CW_TOKEN="$token"
  CW_RESOLVE=""
  CW_INSECURE=0
  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ]; then
    CW_RESOLVE="$(_cfg '.domain' "$id"):$(_cfg '.deploy.https_port // 8443' "$id"):127.0.0.1"
    CW_INSECURE=1
  fi
  acct="$(cw_request GET /api/v1/profile 2>/dev/null | jq -r '.accounts[0].id // empty' 2>/dev/null || true)"
  if [ -z "$acct" ]; then
    echo "channels_api|warn|could not query channel status (API not answering or key rejected)"
    return 0
  fi
  body="$(cw_request GET "/api/v1/accounts/${acct}/inboxes" 2>/dev/null || true)"
  if ! printf '%s' "$body" | jq -e '.payload' >/dev/null 2>&1; then
    echo "channels_api|warn|could not read the inbox list"
    return 0
  fi
  echo "channels_api|ok|inbox list readable"
  printf '%s' "$body" | parse_inboxes_json
}
