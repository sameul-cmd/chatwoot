#!/usr/bin/env bash
# Remote actions go only through this file (project rule). OPSKIT_SSH can point at a fake for tests.
# shellcheck shell=bash

OPSKIT_SSH="${OPSKIT_SSH:-ssh}"

# ssh_run USER HOST command...   (stdin is forwarded)
ssh_run() {
  local user="$1" host="$2"
  shift 2
  "$OPSKIT_SSH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "${user}@${host}" "$@"
}
