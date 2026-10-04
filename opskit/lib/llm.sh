#!/usr/bin/env bash
# BYOK AI service per client (ADR-011): key, endpoint, model picker, effort, embedding model.
# The key lives only in clients/<id>/llm.env (mode 600, git-ignored) and is never printed or put on a command line.
# Needs lib/log.sh, render.sh, deploy.sh (dc, _cfg, _require_local).
# shellcheck shell=bash
# shellcheck disable=SC2016  # the $n / $l / $u in the yq expressions are yq variables, not shell

LLM_PLACEHOLDER_MODEL="choose-with-opskit-llm-model"
LLM_EFFORTS="none low medium high max"

# _llm_key ID -> the stored key (for piping into curl only)
_llm_key() {
  local var
  var="$(_cfg '.bot.llm.api_key_env // "AIBOT_LLM_API_KEY"' "$1")"
  sed -n "s/^${var}=//p" "$(client_dir "$1")/llm.env" 2>/dev/null | head -n1
}

# _llm_get ID PATH -> body of GET <base_url>PATH with the stored key
_llm_get() {
  local id="$1" base key
  base="$(_cfg '.bot.llm.base_url // ""' "$id")"
  [ -n "$base" ] || die "no AI service set: run opskit llm set-key ${id} --base-url <url>"
  key="$(_llm_key "$id")"
  { printf 'url = "%s%s"\n' "$base" "$2"; [ -z "$key" ] || printf 'header = "Authorization: Bearer %s"\n' "$key"; } \
    | curl -sS -f --max-time 20 -K - 2>/dev/null
}

# _llm_apply ID -> render again and restart only the bot container when the stack is running
_llm_apply() {
  render_client "$1" || return 1
  if dc "$1" ps --status running --services 2>/dev/null | grep -qx aibot; then
    dc "$1" up -d --force-recreate aibot >/dev/null 2>&1 || die "could not restart the bot container"
  fi
}

# llm_set_key ID --base-url URL [--paid]   (key from $AIBOT_LLM_API_KEY or a hidden prompt)
llm_set_key() {
  local id="$1" url="" paid="" key var dir
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --base-url) url="${2:-}"; shift 2 ;;
      --paid) paid="true"; shift ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || { log_error "usage: opskit llm set-key <id> --base-url https://host/v1 [--paid]"; return 2; }
  _require_local "$id"
  dir="$(client_dir "$id")"
  var="$(_cfg '.bot.llm.api_key_env // "AIBOT_LLM_API_KEY"' "$id")"
  key="${AIBOT_LLM_API_KEY:-}"
  if [ -z "$key" ]; then
    printf 'Paste the AI service key for %s (input is hidden): ' "$id" >&2
    read -rs key || true
    printf '\n' >&2
  fi
  [ -n "$key" ] || die "no key given"
  (umask 077; printf '%s=%s\n' "$var" "$key" >"$dir/llm.env.tmp")
  mv -f "$dir/llm.env.tmp" "$dir/llm.env"
  yq -y -i --arg u "$url" --arg m "$LLM_PLACEHOLDER_MODEL" \
    ".bot.llm.base_url = \$u | .bot.llm.model = (.bot.llm.model // \$m) | .bot.enabled = (.bot.enabled // false)${paid:+ | .bot.llm.paid_tier = true}" "$dir/client.yaml"
  _llm_apply "$id" || return 1
  log_info "AI service saved for ${id}: ${url}${paid:+ (stated paid-tier or owner-owned)}; key stored in ${dir}/llm.env (mode 600)"
  [ -n "$paid" ] || log_warn "paid-tier not stated: the bot refuses to start on a real client until you run set-key again with --paid"
}

llm_models() {
  local id="$1" current ids
  _require_local "$id"
  ids="$(_llm_get "$id" /models | jq -r '.data[].id' | sort)" || die "could not list the models: check the base URL and the key"
  current="$(_cfg '.bot.llm.model // ""' "$id")"
  printf '%s\n' "$ids" | while read -r m; do
    if [ "$m" = "$current" ]; then printf '* %s  (selected)\n' "$m"; else printf '  %s\n' "$m"; fi
  done
}

llm_model() {
  local id="$1" name="${2:-}" ids
  [ -n "$name" ] || { log_error "usage: opskit llm model <id> <model name>  (see: opskit llm models <id>)"; return 2; }
  _require_local "$id"
  if ids="$(_llm_get "$id" /models 2>/dev/null | jq -r '.data[].id' 2>/dev/null)" && [ -n "$ids" ] && ! grep -qxF "$name" <<<"$ids"; then
    log_warn "'${name}' is not in the service's model list; saving it anyway (some services do not list every model)"
  fi
  yq -y -i --arg n "$name" '.bot.llm.model = $n' "$(client_dir "$id")/client.yaml"
  _llm_apply "$id" || return 1
  log_info "model for ${id}: ${name}"
}

llm_effort() {
  local id="$1" level="${2:-}"
  case " ${LLM_EFFORTS} " in *" ${level} "*) ;; *) log_error "effort must be one of: ${LLM_EFFORTS}"; return 2 ;; esac
  _require_local "$id"
  yq -y -i --arg l "$level" '.bot.llm.effort = $l' "$(client_dir "$id")/client.yaml"
  _llm_apply "$id" || return 1
  log_info "effort for ${id}: ${level}"
}

# llm_embedding_model ID NAME|none -> the optional embedding model for hybrid KB search
llm_embedding_model() {
  local id="$1" name="${2:-}"
  [ -n "$name" ] || { log_error "usage: opskit llm embedding-model <id> <model name>|none"; return 2; }
  _require_local "$id"
  if [ "$name" = none ]; then
    yq -y -i 'del(.bot.embeddings)' "$(client_dir "$id")/client.yaml"
  else
    yq -y -i --arg n "$name" '.bot.embeddings.model = $n' "$(client_dir "$id")/client.yaml"
  fi
  _llm_apply "$id" || return 1
  log_info "embedding model for ${id}: ${name}"
}
