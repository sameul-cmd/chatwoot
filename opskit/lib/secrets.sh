#!/usr/bin/env bash
# Secret generation for a client stack (SPEC 3.6): openssl rand, abort if empty, never overwrite, mode 600.
# Requires lib/log.sh and lib/validate.sh to be sourced first.
# shellcheck shell=bash

OPSKIT_SECRET_NAMES="SECRET_KEY_BASE POSTGRES_PASSWORD REDIS_PASSWORD AIBOT_WEBHOOK_SECRET ADMIN_PASSWORD"

_secret_bytes() {
  case "$1" in
    SECRET_KEY_BASE) echo 64 ;;
    *) echo 24 ;;
  esac
}

# ensure_secrets FILE -> creates FILE (mode 600) and appends any missing/empty secret. Existing values are kept.
ensure_secrets() {
  local file="$1" name current value
  (umask 077 && touch "$file")
  chmod 600 "$file"
  for name in $OPSKIT_SECRET_NAMES; do
    current="$(sed -n "s/^${name}=//p" "$file" | head -n1)"
    if [ -z "$current" ]; then
      value="$(gen_secret "$(_secret_bytes "$name")")" || return 1
      # Chatwoot requires upper + lower + digit + special in user passwords (verified on v4.18.0).
      [ "$name" = "ADMIN_PASSWORD" ] && value="${value}-Aa1!"
      require_secret "$name" "$value" || return 1
      # drop an empty placeholder line (if any) and append the new value
      sed -i "/^${name}=\$/d" "$file"
      printf '%s=%s\n' "$name" "$value" >>"$file"
      log_info "generated secret ${name}"
    fi
  done
}

# load_secrets FILE -> exports the secrets into the current shell without printing them.
load_secrets() {
  local file="$1" name value
  [ -f "$file" ] || {
    log_error "secrets file missing: $file"
    return 1
  }
  for name in $OPSKIT_SECRET_NAMES; do
    value="$(sed -n "s/^${name}=//p" "$file" | head -n1)"
    require_secret "$name" "$value" || return 1
    export "${name}=${value}"
  done
}
