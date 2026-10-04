#!/usr/bin/env bash
# Industry starter packs (Phase 7): list, validate, review, approve and apply. The decisions are made by lib/pack.py
# (pure logic); this file only reads the live account, shows the plan and calls the Chatwoot API through chatwoot_api.sh.
# Needs lib/log.sh, render.sh (client_dir), deploy.sh (_cfg, _require_local), chatwoot_api.sh.
# shellcheck shell=bash

PACKS_DIR="${OPSKIT_PACKS_DIR:-$OPSKIT_ROOT/packs}"

pack_list() {
  local d
  for d in "$PACKS_DIR"/*/; do
    [ -f "${d}pack.yaml" ] && basename "$d"
  done
}

# _pack_dir INDUSTRY -> prints the folder, or an error that lists the valid industries
_pack_dir() {
  local ind="${1:-}"
  if [[ "$ind" =~ ^[a-z]+$ ]] && [ -f "$PACKS_DIR/$ind/pack.yaml" ]; then
    printf '%s' "$PACKS_DIR/$ind"
  else
    log_error "unknown industry '${ind}'. Valid: $(pack_list | paste -sd' ' -)"
    return 1
  fi
}

# pack_validate [INDUSTRY]: every pack when none is given
pack_validate() {
  local ind rc=0 dir inds=("$@")
  [ "$#" -gt 0 ] || mapfile -t inds < <(pack_list)
  for ind in "${inds[@]}"; do
    dir="$(_pack_dir "$ind")" || return 1
    if python3 "$OPSKIT_ROOT/lib/pack_data.py" validate "$dir"; then echo "valid: $ind"; else rc=1; fi
  done
  return "$rc"
}

pack_review() {
  python3 "$OPSKIT_ROOT/lib/pack.py" review "$(_pack_dir "${1:-}")"
}

# pack_approve INDUSTRY --key KEY | --all   (only after the owner has proofread the Bangla)
pack_approve() {
  local dir
  dir="$(_pack_dir "${1:-}")" || return 1
  shift
  [ "${1:-}" = "--all" ] || [ "${1:-}" = "--key" ] || { log_error "usage: opskit pack approve <industry> --key KEY | --all"; return 2; }
  python3 "$OPSKIT_ROOT/lib/pack.py" approve "$dir" "$@"
}

# _pack_live ID FILE -> everything the pack could collide with, read from the client's Chatwoot
_pack_live() {
  local base="/api/v1/accounts/$1" canned labels rules inboxes
  canned="$(cw_request GET "$base/canned_responses")" || return 1
  labels="$(cw_request GET "$base/labels")" || return 1
  rules="$(cw_request GET "$base/automation_rules")" || return 1
  inboxes="$(cw_request GET "$base/inboxes")" || return 1
  jq -n --argjson canned "$canned" --argjson labels "$labels" --argjson rules "$rules" --argjson inboxes "$inboxes" \
    '{canned: $canned, labels: $labels.payload, rules: $rules.payload, inboxes: $inboxes.payload}' >"$2"
}

# _pack_send METHOD PATH JSON -> 0 on success; the reason (never customer data) on failure
_pack_send() {
  local out
  if out="$(cw_request "$1" "$2" -H 'Content-Type: application/json' -d "$3" </dev/null 2>/dev/null)"; then return 0; fi
  log_warn "Chatwoot refused it: $(printf '%s' "$out" | jq -r '.message // .error // "no reason given"' 2>/dev/null | cut -c1-200)"
  return 1
}

# _pack_execute ACCOUNT PLAN_FILE -> applies create/update rows; prints failed state keys, one per line
_pack_execute() {
  local base="/api/v1/accounts/$1" status class skey id payload method path body
  while IFS=$'\x1f' read -r status class skey id payload; do
    if [ "$status" = create ]; then method=POST; path=""; else method=PATCH; path="/$id"; fi
    body="$payload"
    case "$class" in
      saved) path="$base/canned_responses$path"; body="$(jq -c '{canned_response: .}' <<<"$payload")" ;;
      label) path="$base/labels$path" ;;
      rule) path="$base/automation_rules$path" ;;
    esac
    _pack_send "$method" "$path" "$body" || printf '%s\n' "$skey"
  done < <(jq -r '.[] | select(.inbox == null and (.status == "create" or .status == "update"))
                  | "\(.status)\u001f\(.skey | split(":")[0])\u001f\(.skey)\u001f\(.id // "")\u001f\(.payload | tojson)"' "$2")
  # one PATCH per inbox: the greeting, hours, after-hours text and rating switch travel together
  local inbox skeys
  while IFS=$'\x1f' read -r inbox skeys payload; do
    _pack_send PATCH "$base/inboxes/$inbox" "$payload" || jq -r '.[]' <<<"$skeys"
  done < <(jq -r '[.[] | select(.inbox != null and (.status == "create" or .status == "update"))] | group_by(.inbox)[]
                  | "\(.[0].inbox)\u001f\(map(.skey) | tojson)\u001f\(map(.payload) | add | tojson)"' "$2")
}

# pack_apply ID INDUSTRY [--dry-run] [--inbox N[,N]] [--include-unreviewed]
pack_apply() {
  local id="$1" ind="$2" dir dry=0 inbox="" include=() tmp state langs tz account failed out
  shift 2
  dir="$(_pack_dir "$ind")" || return 1
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      --inbox) inbox="${2:-}"; shift 2 ;;
      --include-unreviewed) include=(--include-unreviewed); shift ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  pack_validate "$ind" >/dev/null || { python3 "$OPSKIT_ROOT/lib/pack_data.py" validate "$dir"; die "the pack itself is invalid; fix it first"; }
  _require_local "$id"
  langs="$(_cfg '.languages | join(",")' "$id")"
  tz="$(_cfg '.timezone' "$id")"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  cw_use_stack "$id" || return 1
  account="$(cw_request GET /api/v1/profile | jq -r '.accounts[0].id')"
  _pack_live "$account" "$tmp/live.json" || die "could not read the client's Chatwoot (is the stack running? admin token available?)"
  state="$(client_dir "$id")/pack-state.json"
  python3 "$OPSKIT_ROOT/lib/pack.py" plan --pack "$dir" --live "$tmp/live.json" --state "$state" --langs "$langs" --timezone "$tz" \
    ${inbox:+--inbox "$inbox"} "${include[@]}" --out "$tmp/plan.json" || return 1
  if [ "$(jq '[.[] | select(.status == "skipped")] | length' "$tmp/plan.json")" -gt 0 ]; then
    echo "Some Bangla texts are not proofread yet and were left out. Read them with: opskit pack review ${ind}; add --include-unreviewed to apply them anyway."
  fi
  if [ "$(jq '[.[] | select(.status == "create" or .status == "update")] | length' "$tmp/plan.json")" -eq 0 ]; then
    echo "Nothing to change."
  fi
  if [ "$dry" -eq 1 ]; then
    echo "Dry run: nothing was changed. The default opening hours are every day 10:00-20:00; adjust them in the inbox settings if the client keeps other days."
    return 0
  fi
  failed="$(_pack_execute "$account" "$tmp/plan.json")"
  # shellcheck disable=SC2086  # failed keys are plain words (kind:key); no spaces
  python3 "$OPSKIT_ROOT/lib/pack.py" state --plan "$tmp/plan.json" --state "$state" --failed $failed
  _pack_copy_kb "$id" "$dir"
  echo "Chats are only tagged, not assigned: once the client has agents, add assignment under Settings > Automation in Chatwoot."
  if [ -n "$failed" ]; then
    out="$(printf '%s\n' "$failed" | wc -l | tr -d ' ')"
    log_error "${out} item(s) could not be applied (see messages above); run the command again after fixing them"
    return 1
  fi
  log_info "pack ${ind} applied to ${id}"
}

# _pack_copy_kb ID PACKDIR -> the bot's starter questions, never over a file that already exists
_pack_copy_kb() {
  local target
  target="$(client_dir "$1")/kb"
  mkdir -p "$target"
  if [ -e "$target/faq.yaml" ]; then
    echo "Starter questions already in ${target}/faq.yaml: left untouched."
  else
    cp "$2/kb_starter/faq.yaml" "$target/faq.yaml"
    echo "Starter questions for the bot copied to ${target}/faq.yaml. Fill in the answers: the bot ignores questions without an answer."
  fi
}
