#!/usr/bin/env bash
# Alert payloads + heartbeat (SPEC 9 groundwork; Phase 4 delivers them). Needs lib/log.sh and jq.
# Alerts never contain message text: callers pass short technical summaries only.
# shellcheck shell=bash

OPSKIT_ALERT_DIR="${OPSKIT_ALERT_DIR:-${OPSKIT_ROOT:-.}/alerts/outbox}"

# emit_alert SEVERITY CLIENT CHECK SUMMARY -> writes a JSON file; POSTs to the hub when OPSKIT_HUB_URL is set.
emit_alert() {
  local severity="$1" client="$2" check="$3" summary="$4" file ts
  case "$severity" in info | warn | critical) ;; *)
    log_error "bad alert severity: $severity"
    return 1
    ;;
  esac
  summary="$(printf '%s' "$summary" | tr '\n\r' '  ' | cut -c1-300)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$OPSKIT_ALERT_DIR"
  file="$OPSKIT_ALERT_DIR/$(date -u +%Y%m%dT%H%M%S)-${client}-${check}.json"
  jq -n --arg s "$severity" --arg c "$client" --arg k "$check" --arg m "$summary" --arg t "$ts" \
    '{severity:$s, client_id:$c, check:$k, summary:$m, timestamp:$t}' >"$file"
  log_warn "alert (${severity}) ${client}/${check}: ${summary}"
  _hub_post "$file" || true
  printf '%s\n' "$file"
}

# send_heartbeat CLIENT NAME -> tells the hub a job succeeded (skipped silently without OPSKIT_HUB_URL).
send_heartbeat() {
  local client="$1" name="$2" tmp
  [ -n "${OPSKIT_HUB_URL:-}" ] || return 0
  tmp="$(mktemp)"
  jq -n --arg c "$client" --arg n "$name" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{type:"heartbeat", client_id:$c, name:$n, timestamp:$t}' >"$tmp"
  _hub_post "$tmp" || true
  rm -f "$tmp"
}

_hub_post() {
  [ -n "${OPSKIT_HUB_URL:-}" ] || return 0
  curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
    ${OPSKIT_HUB_TOKEN:+-H "Authorization: Bearer ${OPSKIT_HUB_TOKEN}"} \
    --data-binary "@$1" "$OPSKIT_HUB_URL" >/dev/null 2>&1 || {
    log_warn "hub not reachable; alert kept in the outbox"
    return 1
  }
}
