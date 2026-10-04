#!/usr/bin/env bash
# Validation helpers.
# shellcheck shell=bash

# require_tool NAME [HINT]
require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "missing tool: $1${2:+ ($2)}"
    return 1
  }
}

# require_secret NAME VALUE  -> abort when empty (SPEC 3.6). Never prints the value.
require_secret() {
  local name="$1" value="${2:-}"
  if [ -z "$value" ]; then
    log_error "secret ${name} is empty; aborting"
    return 1
  fi
}

# gen_secret BYTES -> hex string from openssl; aborts if the result is empty.
gen_secret() {
  local bytes="${1:-32}" out
  out="$(openssl rand -hex "$bytes")"
  require_secret "generated secret" "$out" || return 1
  printf '%s' "$out"
}
