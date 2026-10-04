#!/usr/bin/env bash
# Channel checks for Telegram, WhatsApp Cloud API and Facebook/Instagram (part of `opskit channels check`).
# Two layers: OUR side (inbox settings, webhook endpoint, verification handshake) works anywhere; the other side's
# view (Telegram getWebhookInfo, Meta status) is a READ-ONLY probe and only a WARN when it cannot be reached.
# Secrets travel to curl through stdin config, never as command-line arguments. Needs channels.sh sourced first.
# shellcheck shell=bash

# _tg_api TOKEN METHOD -> first line = HTTP code, rest = body (a subshell cannot set variables for the caller)
_tg_api() {
  local token="$1" method="$2" base body code
  base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
  body="$(mktemp)"
  code="$(printf 'url = "%s/bot%s/%s"\n' "$base" "$token" "$method" | curl -sS -K - --max-time 10 -o "$body" -w '%{http_code}' 2>/dev/null || true)"
  printf '%s\n' "${code:-000}"
  cat "$body"
  rm -f "$body"
}

ch_telegram() { # ID INBOX_JSON
  local id="$1" j="$2" label iid bot code token info url expected err edate pending now host
  label="$(jq -r '"\(.name) (Telegram)"' <<<"$j")"
  iid="$(jq -r .id <<<"$j")"
  bot="$(jq -r '.bot_name // empty' <<<"$j")"
  if [ -n "$bot" ]; then _row "$label" "bot" PASS "@${bot}"; else _row "$label" "bot" WARN "no bot name saved" ""; fi
  code="$(_ch_status "$id" /webhooks/telegram/opskit-check -X POST -H 'Content-Type: application/json' -d '{}')"
  if [ "$code" = "200" ]; then _row "$label" "webhook endpoint" PASS "answers over HTTPS"; else _row "$label" "webhook endpoint" FAIL "HTTP ${code:-none}" tg_endpoint; fi
  token="$(_runner "$id" ACTION=telegram_token "INBOX_ID=${iid}" | sed -n 's/^SECRET=//p' | head -n1)"
  if [ -z "$token" ]; then
    _row "$label" "Telegram's own view" WARN "skipped: bot token not readable" ""
    return 0
  fi
  info="$(_tg_api "$token" getWebhookInfo)"
  TG_CODE="${info%%$'\n'*}"
  info="${info#*$'\n'}"
  case "$TG_CODE" in
    000) _row "$label" "Telegram's own view" WARN "could not reach Telegram" tg_unreachable; return 0 ;;
    401 | 404) _row "$label" "Telegram's own view" FAIL "bot token rejected" tg_token; return 0 ;;
    200) ;;
    *) _row "$label" "Telegram's own view" WARN "Telegram answered HTTP ${TG_CODE}" tg_unreachable; return 0 ;;
  esac
  url="$(jq -r '.result.url // empty' <<<"$info" 2>/dev/null || true)"
  expected="$(_frontend_url "$id")/webhooks/telegram/${token}"
  if [ -z "$url" ]; then
    _row "$label" "Telegram -> this server" FAIL "Telegram has no webhook set" tg_mismatch
  elif [ "$url" != "$expected" ]; then
    host="${url#https://}"
    _row "$label" "Telegram -> this server" FAIL "Telegram sends to ${host%%/*}, not to this server" tg_mismatch
  else
    _row "$label" "Telegram -> this server" PASS "webhook points to this server"
  fi
  err="$(jq -r '.result.last_error_message // empty' <<<"$info" 2>/dev/null || true)"
  edate="$(jq -r '.result.last_error_date // 0' <<<"$info" 2>/dev/null || echo 0)"
  now="$(_hc_now)"
  if [ -n "$err" ] && [ $((now - edate)) -le 86400 ]; then
    _row "$label" "Telegram delivery errors" FAIL "last error: $(printf '%s' "$err" | tr -d '\000-\037' | cut -c1-80)" tg_error
  else
    _row "$label" "Telegram delivery errors" PASS "none in the last 24 hours"
  fi
  pending="$(jq -r '.result.pending_update_count // 0' <<<"$info" 2>/dev/null || echo 0)"
  if [ "${pending:-0}" -gt 20 ]; then _row "$label" "Telegram queue" WARN "${pending} messages waiting at Telegram" tg_error; fi
}

# _meta_get TOKEN PATH -> first line = HTTP code, rest = body (bearer token via stdin config)
_meta_get() {
  local token="$1" path="$2" base body code
  base="${META_GRAPH_BASE:-https://graph.facebook.com}"
  body="$(mktemp)"
  code="$(printf 'url = "%s/%s/%s"\nheader = "Authorization: Bearer %s"\n' "$base" "${META_GRAPH_VERSION:-v21.0}" "$path" "$token" \
    | curl -sS -K - --max-time 10 -o "$body" -w '%{http_code}' 2>/dev/null || true)"
  printf '%s\n' "${code:-000}"
  cat "$body"
  rm -f "$body"
}

ch_whatsapp() { # ID INBOX_JSON
  local id="$1" j="$2" label provider phone gaps=() k vt enc chal body wrong api pnid res shown digits_have digits_want
  label="$(jq -r '"\(.name) (WhatsApp)"' <<<"$j")"
  provider="$(jq -r '.provider // ""' <<<"$j")"
  phone="$(jq -r '.phone_number // empty' <<<"$j")"
  if [ "$provider" != "whatsapp_cloud" ]; then
    _row "$label" "provider" FAIL "provider is '${provider:-unknown}'" wa_provider
    return 0
  fi
  for k in api_key phone_number_id business_account_id webhook_verify_token; do
    [ -n "$(jq -r ".provider_config.${k} // empty" <<<"$j")" ] || gaps+=("$k")
  done
  [[ "$phone" =~ ^\+[0-9]{8,15}$ ]] || gaps+=("phone_number")
  if [ "${#gaps[@]}" -gt 0 ]; then
    _row "$label" "settings" FAIL "missing: ${gaps[*]}" wa_settings
    return 0
  fi
  _row "$label" "settings" PASS "phone number, ids and tokens present"
  vt="$(jq -r '.provider_config.webhook_verify_token' <<<"$j")"
  enc="%2B${phone#+}"
  chal="opskit$((RANDOM * RANDOM))"
  body="$(_ch_secret_get "$id" "/webhooks/whatsapp/${enc}?hub.mode=subscribe&hub.verify_token=${vt}&hub.challenge=${chal}" || true)"
  if [ "$body" = "$chal" ]; then
    _row "$label" "Meta verification handshake" PASS "right token: challenge echoed"
    wrong="$(_ch_secret_get "$id" "/webhooks/whatsapp/${enc}?hub.mode=subscribe&hub.verify_token=opskit-wrong-token&hub.challenge=${chal}" || true)"
    if [ "$wrong" = "$chal" ]; then _row "$label" "wrong token refused" FAIL "any token is accepted" wa_open; else _row "$label" "wrong token refused" PASS "refused"; fi
  else
    _row "$label" "Meta verification handshake" FAIL "challenge not echoed" wa_handshake
  fi
  api="$(jq -r '.provider_config.api_key' <<<"$j")"
  pnid="$(jq -r '.provider_config.phone_number_id' <<<"$j")"
  res="$(_meta_get "$api" "${pnid}?fields=display_phone_number,verified_name,quality_rating")"
  META_CODE="${res%%$'\n'*}"
  res="${res#*$'\n'}"
  case "$META_CODE" in
    000) _row "$label" "Meta's own view" WARN "could not reach Meta" wa_unreachable ;;
    401) _row "$label" "Meta's own view" FAIL "access token rejected" wa_token ;;
    400 | 403)
      if [ "$(jq -r '.error.code // 0' <<<"$res" 2>/dev/null)" = "190" ]; then _row "$label" "Meta's own view" FAIL "access token expired or invalid" wa_token
      else _row "$label" "Meta's own view" FAIL "Meta refused the phone number id" wa_number; fi
      ;;
    404) _row "$label" "Meta's own view" FAIL "phone number id not found" wa_number ;;
    200)
      shown="$(jq -r '.display_phone_number // empty' <<<"$res")"
      digits_have="$(printf '%s' "$shown" | tr -dc '0-9')"
      digits_want="${phone#+}"
      if [ "$digits_have" = "$digits_want" ]; then
        _row "$label" "Meta's own view" PASS "number known to Meta (name: $(jq -r '.verified_name // "?"' <<<"$res" | cut -c1-40), quality: $(jq -r '.quality_rating // "?"' <<<"$res"))"
      else
        _row "$label" "Meta's own view" FAIL "Meta's number differs from the one saved here" wa_number
      fi
      ;;
    *) _row "$label" "Meta's own view" WARN "Meta answered HTTP ${META_CODE}" wa_unreachable ;;
  esac
  printf '    note: you can reply within 24 hours of the customer'"'"'s last message, afterwards only approved templates. Meta bills per message to the client'"'"'s own account (rules and prices change: check Meta'"'"'s pricing page).\n'
}

ch_meta() { # ID INBOX_JSON  (Facebook page or Instagram)
  local id="$1" j="$2" type label names absent="" out n vt path wrong right chal
  type="$(jq -r '.channel_type' <<<"$j")"
  label="$(jq -r '"\(.name) (\(.channel_type | sub("^Channel::"; "")))"' <<<"$j")"
  if [ "$(jq -r '.reauthorization_required // false' <<<"$j")" = "true" ]; then
    _row "$label" "connection" FAIL "needs to be re-connected" meta_reauth
  else
    _row "$label" "connection" PASS "Chatwoot reports it as connected"
  fi
  if [ "$type" = "Channel::Instagram" ]; then names="INSTAGRAM_APP_ID,INSTAGRAM_APP_SECRET,INSTAGRAM_VERIFY_TOKEN"; vt="INSTAGRAM_VERIFY_TOKEN"; path="/webhooks/instagram"
  else names="FB_APP_ID,FB_APP_SECRET,FB_VERIFY_TOKEN"; vt="FB_VERIFY_TOKEN"; path="/bot"; fi
  out="$(_runner "$id" ACTION=config_present "NAMES=${names}")"
  for n in ${names//,/ }; do
    printf '%s\n' "$out" | grep -q "^PRESENT ${n} yes$" || absent+="${n} "
  done
  if [ -n "$absent" ]; then
    _row "$label" "Meta app settings" FAIL "missing: ${absent% }" meta_env
    return 0
  fi
  _row "$label" "Meta app settings" PASS "app id, secret and verify token are set"
  chal="opskit$((RANDOM * RANDOM))"
  wrong="$(_ch_secret_get "$id" "${path}?hub.mode=subscribe&hub.verify_token=opskit-wrong-token&hub.challenge=${chal}" || true)"
  right="$(_runner "$id" ACTION=config_value "NAME=${vt}" | sed -n 's/^SECRET=//p' | head -n1)"
  if [ "$wrong" = "$chal" ]; then
    _row "$label" "webhook verification" FAIL "a wrong token is accepted" meta_handshake
  elif [ -n "$right" ] && [ "$(_ch_secret_get "$id" "${path}?hub.mode=subscribe&hub.verify_token=${right}&hub.challenge=${chal}" || true)" = "$chal" ]; then
    _row "$label" "webhook verification" PASS "right token echoed, wrong token refused"
  else
    _row "$label" "webhook verification" FAIL "the right token is not echoed" meta_handshake
  fi
}
