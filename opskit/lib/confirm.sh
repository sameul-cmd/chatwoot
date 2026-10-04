#!/usr/bin/env bash
# Confirmation helpers for destructive actions (SPEC 0.6): --yes plus typed client id.
# shellcheck shell=bash

# confirm_destructive ACTION CLIENT_ID YES_FLAG
#   YES_FLAG must be "yes" and the typed id must equal CLIENT_ID (read from OPSKIT_CONFIRM_ID for tests,
#   otherwise from stdin).
confirm_destructive() {
  local action="$1" client_id="$2" yes_flag="${3:-}"
  if [ "$yes_flag" != "yes" ]; then
    log_error "refusing to ${action} '${client_id}' without --yes"
    return 1
  fi
  local typed="${OPSKIT_CONFIRM_ID:-}"
  if [ -z "$typed" ]; then
    printf 'Type the client id (%s) to confirm %s: ' "$client_id" "$action" >&2
    read -r typed || true
  fi
  if [ "$typed" != "$client_id" ]; then
    log_error "typed id does not match; aborting ${action}"
    return 1
  fi
}
