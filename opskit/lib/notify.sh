#!/usr/bin/env bash
# Telegram notifications (Telegram-only: no ops-hub yet, ADR-016). Needs lib/log.sh.
# Settings live in clients/<id>/alerts.env (mode 600): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, optional TELEGRAM_API_BASE.
# The token is never put on a command line, in logs or in alerts.
# shellcheck shell=bash

alerts_env_file() { printf '%s/alerts.env' "$(client_dir "$1")"; }

_env_get() { sed -n "s/^${2}=//p" "$1" 2>/dev/null | head -n1; }

# alerts_set_telegram ID -> writes alerts.env from the environment variables TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
alerts_set_telegram() {
  local id="$1" f token="${TELEGRAM_BOT_TOKEN:-}" chat="${TELEGRAM_CHAT_ID:-}"
  [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]] || { log_error "TELEGRAM_BOT_TOKEN looks wrong (expected 123456:ABC... from @BotFather)"; return 1; }
  [[ "$chat" =~ ^-?[0-9]+$ ]] || { log_error "TELEGRAM_CHAT_ID must be a number"; return 1; }
  f="$(alerts_env_file "$id")"
  (umask 077 && printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$token" "$chat" >"$f")
  chmod 600 "$f"
  log_info "Telegram settings saved to ${f} (mode 600)"
}

# telegram_send ENV_FILE TEXT -> 0 if Telegram accepted the message (HTTP 200), else 1. Retries twice.
telegram_send() {
  local envf="$1" text="$2" token chat base code tries=0 body
  [ -r "$envf" ] || { log_warn "no Telegram settings (${envf##*/}): message not sent"; return 1; }
  token="$(_env_get "$envf" TELEGRAM_BOT_TOKEN)"
  chat="$(_env_get "$envf" TELEGRAM_CHAT_ID)"
  base="${TELEGRAM_API_BASE:-$(_env_get "$envf" TELEGRAM_API_BASE)}"
  base="${base:-https://api.telegram.org}"
  if [ -z "$token" ] || [ -z "$chat" ]; then
    log_warn "Telegram settings incomplete: message not sent"
    return 1
  fi
  text="$(printf '%s' "$text" | cut -c1-1000)"
  body="$(mktemp)"
  while [ "$tries" -lt 3 ]; do
    # the URL (which contains the token) is passed to curl on stdin, not on the command line
    code="$(printf 'url = "%s/bot%s/sendMessage"\n' "$base" "$token" | curl -sS -K - --max-time 10 -o "$body" -w '%{http_code}' \
      --data-urlencode "chat_id=${chat}" --data-urlencode "text=${text}" 2>/dev/null || true)"
    code="${code:-000}"
    [ "$code" = "200" ] && { rm -f "$body"; return 0; }
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] && sleep 2
  done
  rm -f "$body"
  log_warn "Telegram send failed (HTTP ${code})"
  return 1
}
