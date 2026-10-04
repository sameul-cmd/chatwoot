#!/usr/bin/env bash
# The AI first-reply bot per client (Phase 8): enable, disable (kill switch), status, reload, unanswered.
# Chatwoot is reached only through chatwoot_api.sh; the bot itself only through its container (never published).
# Needs lib/log.sh, render.sh, deploy.sh (dc, _cfg, _require_local), secrets.sh, chatwoot_api.sh.
# shellcheck shell=bash

BOT_NAME="opskit-aibot"

# _bot_http ID METHOD PATH -> body of an internal aibot call (run inside the container, so nothing is published)
_bot_http() {
  dc "$1" exec -T aibot python -c '
import os, sys, urllib.request, urllib.error
path = sys.argv[2].replace("@SECRET@", os.environ.get("AIBOT_WEBHOOK_SECRET", ""))
req = urllib.request.Request("http://localhost:8000" + path, method=sys.argv[1], data=b"{}" if sys.argv[1] == "POST" else None)
try:
    print(urllib.request.urlopen(req, timeout=10).read().decode())
except urllib.error.HTTPError as e:
    print(e.read().decode()); sys.exit(1)
' "$2" "$3" </dev/null
}

# _bot_set_cfg ID YQ_EXPRESSION -> edits client.yaml through yq (never by hand)
_bot_set_cfg() {
  yq -y -i "$2" "$(client_dir "$1")/client.yaml"
}

# _bot_wait_wired ID -> waits until the bot container reports that it is wired to Chatwoot
_bot_wait_wired() {
  local id="$1" _
  for _ in $(seq 1 40); do
    [ "$(_bot_http "$id" GET /health 2>/dev/null | jq -r '.wired // false' 2>/dev/null)" = "true" ] && return 0
    sleep 2
  done
  return 1
}

# _bot_wait_up ID -> waits until the bot container answers /health (it may have just been recreated)
_bot_wait_up() {
  local _
  for _ in $(seq 1 30); do
    _bot_http "$1" GET /health >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# _bot_account -> the Chatwoot account id (needs cw_use_stack first)
_bot_account() {
  cw_request GET /api/v1/profile | jq -r '.accounts[0].id'
}

# _bot_attached ACCOUNT BOT_ID -> inbox ids the bot is attached to
_bot_attached() {
  local inbox
  while read -r inbox; do
    [ "$(cw_request GET "/api/v1/accounts/$1/inboxes/${inbox}/agent_bot" | jq -r '.agent_bot.id // empty')" = "$2" ] && echo "$inbox"
  done < <(cw_request GET "/api/v1/accounts/$1/inboxes" | jq -r '.payload[].id')
}

bot_enable() {
  local id="$1" inboxes=() inbox account team team_id="" url bot bot_id token hmac dir existing body
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --inbox) inboxes+=("${2:-}"); shift 2 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  [ "${#inboxes[@]}" -gt 0 ] || { log_error "usage: opskit bot enable <id> --inbox N [--inbox M]"; return 2; }
  _require_local "$id"
  dir="$(client_dir "$id")"
  if [ -z "$(_cfg '.bot.llm.base_url // ""' "$id")" ] || [ -z "$(_cfg '.bot.llm.model // ""' "$id")" ]; then
    die "the AI service is not set up: run opskit llm set-key ${id} --base-url <url> (then llm model ${id} <name>)"
  fi
  [ "$(_cfg '.bot.llm.model' "$id")" != "$LLM_PLACEHOLDER_MODEL" ] || die "no model chosen: run opskit llm models ${id}, then opskit llm model ${id} <name>"
  [ -f "$dir/llm.env" ] || die "no AI key stored: run opskit llm set-key ${id} --base-url <url>"
  cw_use_stack "$id" || return 1
  account="$(_bot_account)"
  for inbox in "${inboxes[@]}"; do
    [[ "$inbox" =~ ^[0-9]+$ ]] || die "--inbox needs a number (got '${inbox}')"
    cw_request GET "/api/v1/accounts/${account}/inboxes/${inbox}" >/dev/null 2>&1 || die "inbox ${inbox} does not exist in Chatwoot"
  done
  team="$(_cfg '.bot.handoff_team // ""' "$id")"
  if [ -n "$team" ]; then
    team_id="$(cw_request GET "/api/v1/accounts/${account}/teams" | jq -r --arg t "$team" '.[] | select(.name == $t) | .id' | head -n1)"
    [ -n "$team_id" ] || die "team '${team}' (bot.handoff_team) does not exist in Chatwoot: create it first or clear the setting"
  fi
  load_secrets "$dir/secrets.env" || return 1
  url="http://aibot:8000/webhook/${AIBOT_WEBHOOK_SECRET}"
  # the webhook address contains a secret: it goes to Chatwoot from a mode-600 file, never on a command line
  body="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$body'" RETURN
  existing="$(cw_request GET "/api/v1/accounts/${account}/agent_bots" | jq -c --arg n "$BOT_NAME" '[.[] | select(.name == $n)][0] // empty')"
  if [ -z "$existing" ]; then
    N="$BOT_NAME" U="$url" jq -cn '{name: $ENV.N, outgoing_url: $ENV.U}' >"$body"
    bot="$(cw_request POST "/api/v1/accounts/${account}/agent_bots" -H 'Content-Type: application/json' --data-binary "@$body")" || return 1
  else
    bot="$existing"
    if [ "$(jq -r .outgoing_url <<<"$bot")" != "$url" ]; then
      U="$url" jq -cn '{outgoing_url: $ENV.U}' >"$body"
      bot="$(cw_request PATCH "/api/v1/accounts/${account}/agent_bots/$(jq -r .id <<<"$bot")" -H 'Content-Type: application/json' \
        --data-binary "@$body")" || return 1
    fi
  fi
  bot_id="$(jq -r .id <<<"$bot")"
  token="$(jq -r .access_token <<<"$bot")"
  hmac="$(jq -r .secret <<<"$bot")"
  if [ -z "$token" ] || [ "$token" = null ] || [ -z "$hmac" ] || [ "$hmac" = null ]; then
    die "Chatwoot did not return the bot's token and secret"
  fi
  (umask 077
    printf 'AIBOT_BOT_TOKEN=%s\nAIBOT_CHATWOOT_HMAC_SECRET=%s\nAIBOT_ACCOUNT_ID=%s\n' "$token" "$hmac" "$account" >"$dir/bot.env.tmp"
    [ -z "$team_id" ] || printf 'AIBOT_HANDOFF_TEAM_ID=%s\n' "$team_id" >>"$dir/bot.env.tmp")
  mv -f "$dir/bot.env.tmp" "$dir/bot.env"
  _bot_set_cfg "$id" ".bot.enabled = true | .bot.inboxes = [$(IFS=,; echo "${inboxes[*]}")]"
  render_client "$id" || return 1
  dc "$id" up -d --force-recreate aibot >/dev/null 2>&1 || die "could not restart the bot container"
  _bot_wait_wired "$id" || die "the bot did not report 'wired' in time: see: docker compose -p ${id} logs aibot (it never logs customer text)"
  if [ "$(_bot_http "$id" POST "/webhook/@SECRET@" 2>/dev/null | jq -r '.detail // empty')" != "bad signature" ]; then
    die "the bot's webhook did not refuse an unsigned request"
  fi
  for inbox in "${inboxes[@]}"; do
    cw_request POST "/api/v1/accounts/${account}/inboxes/${inbox}/set_agent_bot" -H 'Content-Type: application/json' \
      -d "$(jq -cn --argjson b "$bot_id" '{agent_bot: $b}')" >/dev/null || die "could not attach the bot to inbox ${inbox}"
  done
  log_info "bot enabled for ${id}: inboxes ${inboxes[*]}${team_id:+, handoff team ${team}}"
}

# bot_disable ID -> kill switch: detach everywhere, hand waiting chats to people, tell the bot to stop
bot_disable() {
  local id="$1" account bot_id inbox conv n=0
  _require_local "$id"
  cw_use_stack "$id" || return 1
  account="$(_bot_account)"
  bot_id="$(cw_request GET "/api/v1/accounts/${account}/agent_bots" | jq -r --arg n "$BOT_NAME" '[.[] | select(.name == $n)][0].id // empty')"
  if [ -n "$bot_id" ]; then
    while read -r inbox; do
      [ -n "$inbox" ] || continue
      cw_request POST "/api/v1/accounts/${account}/inboxes/${inbox}/set_agent_bot" -H 'Content-Type: application/json' -d '{"agent_bot":null}' >/dev/null
      # chats still waiting for the bot would be stranded: open them for people
      while read -r conv; do
        [ -n "$conv" ] || continue
        cw_request POST "/api/v1/accounts/${account}/conversations/${conv}/toggle_status" -H 'Content-Type: application/json' -d '{"status":"open"}' >/dev/null && n=$((n + 1))
      done < <(cw_request GET "/api/v1/accounts/${account}/conversations?status=pending&inbox_id=${inbox}" | jq -r '.data.payload[].id')
    done < <(_bot_attached "$account" "$bot_id")
  fi
  _bot_set_cfg "$id" '.bot.enabled = false'
  render_client "$id" || return 1
  dc "$id" up -d --force-recreate aibot >/dev/null 2>&1 || die "could not restart the bot container"
  _bot_wait_up "$id" || log_warn "the bot container is slow to start: check opskit bot status ${id}"
  log_info "bot disabled for ${id}: detached from all inboxes, ${n} waiting chat(s) opened for people"
}

bot_status() {
  local id="$1" account bot_id attached health
  _require_local "$id"
  _bot_wait_up "$id" || true
  health="$(_bot_http "$id" GET /health 2>/dev/null || true)"
  [ -n "$health" ] || die "the bot container is not running (docker compose -p ${id} ps)"
  printf 'bot container      %s\n' "$(jq -r '"ok, version \(.version), KB entries \(.kb_entries), enabled=\(.bot_enabled), wired=\(.wired), embeddings=\(.embeddings)"' <<<"$health")"
  printf 'configured         enabled=%s inboxes=%s model=%s\n' "$(_cfg '.bot.enabled // false' "$id")" "$(_cfg '(.bot.inboxes // []) | join(",")' "$id")" "$(_cfg '.bot.llm.model // "-"' "$id")"
  if cw_use_stack "$id" 2>/dev/null; then
    account="$(_bot_account)"
    bot_id="$(cw_request GET "/api/v1/accounts/${account}/agent_bots" | jq -r --arg n "$BOT_NAME" '[.[] | select(.name == $n)][0].id // empty')"
    attached="$( [ -z "$bot_id" ] || _bot_attached "$account" "$bot_id" | paste -sd, -)"
    printf 'attached to inboxes %s\n' "${attached:-none}"
  fi
  _bot_http "$id" GET /metrics 2>/dev/null | jq -r '"answered           \(.answered)\nhanded off         \(.handed_off)  \(.handoff_reasons)\nerrors             \(.errors)\naverage time       \(.avg_latency_ms // "-") ms\nunanswered topics  \(.unanswered | length)  (list them: opskit bot unanswered <id>)"' || true
}

bot_reload() {
  _require_local "$1"
  _bot_http "$1" POST /admin/reload | jq -r '"KB reloaded: \(.kb_entries) entries"'
}

# bot_unanswered ID -> the questions the bot could not answer, most asked first (customer text: run it on your own machine)
bot_unanswered() {
  _require_local "$1"
  _bot_http "$1" GET /metrics | jq -r '.unanswered[] | "\(.count)x  \(.question)"'
}
