#!/usr/bin/env bash
# Logging helpers. Secrets must never be printed: pass values through mask().
# shellcheck shell=bash

OPSKIT_LOG_LEVEL="${OPSKIT_LOG_LEVEL:-info}"

_log_rank() {
  case "$1" in debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;; esac
}

_log() {
  local level="$1"
  shift
  if [ "$(_log_rank "$level")" -ge "$(_log_rank "$OPSKIT_LOG_LEVEL")" ]; then
    printf '%s [%s] %s\n' "$(date -u +%H:%M:%S)" "$level" "$*" >&2
  fi
}

log_debug() { _log debug "$@"; }
log_info() { _log info "$@"; }
log_warn() { _log warn "$@"; }
log_error() { _log error "$@"; }

die() {
  log_error "$@"
  exit 1
}

# mask VALUE -> first 2 chars + *** (or *** when short). Use for any secret shown to a human.
mask() {
  local v="${1:-}"
  if [ "${#v}" -le 6 ]; then
    printf '***'
  else
    printf '%s***' "${v:0:2}"
  fi
}
