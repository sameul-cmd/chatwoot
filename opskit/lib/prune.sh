#!/usr/bin/env bash
# Retention (SPEC 8): which timestamped backups are too old. Pure function + local helper.
# Backup folder names are UTC timestamps like 20261004T020000Z. Needs lib/log.sh.
# shellcheck shell=bash

_ts_to_epoch() { date -u -d "${1:0:4}-${1:4:2}-${1:6:2} ${1:9:2}:${1:11:2}:${1:13:2}" +%s; }

# prune_candidates DAYS NOW_EPOCH < names-on-stdin -> prints names to DELETE.
# Keeps every backup newer than DAYS days and ALWAYS keeps the newest one (never delete the last good backup).
prune_candidates() {
  local days="$1" now="$2" cutoff name newest="" names=()
  cutoff=$((now - days * 86400))
  while IFS= read -r name; do
    [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || continue
    names+=("$name")
  done
  [ "${#names[@]}" -gt 0 ] || return 0
  newest="$(printf '%s\n' "${names[@]}" | sort | tail -n1)"
  for name in "${names[@]}"; do
    [ "$name" = "$newest" ] && continue
    [ "$(_ts_to_epoch "$name")" -lt "$cutoff" ] && printf '%s\n' "$name"
  done
  return 0
}

# prune_local DIR DAYS -> deletes old complete backups and stale .partial folders (> 24h) under DIR.
prune_local() {
  local dir="$1" days="$2" now name
  now="${OPSKIT_NOW:-$(date -u +%s)}"
  [ -d "$dir" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    rm -rf "${dir:?}/${name}"
    log_info "pruned backup ${name}"
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | prune_candidates "$days" "$now")
  find "$dir" -maxdepth 1 -mindepth 1 -type d -name '.partial-*' -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
}
