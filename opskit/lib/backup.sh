#!/usr/bin/env bash
# `opskit backup run|list`: run the host agent, prune, copy off-server, alert/heartbeat.
# Needs log, validate, secrets, render, deploy (dc/_cfg), crypto, alert, prune to be sourced first.
# shellcheck shell=bash

OPSKIT_BACKUP_AGENT="${OPSKIT_BACKUP_AGENT:-$OPSKIT_ROOT/agent/backup.sh}"

# ensure_host_key ID -> per-client age key kept ON the host (mode 600) so automated restore tests can read backups.
# Backups are encrypted to BOTH this key and the owner's offline key; the off-server copy holds neither private key.
ensure_host_key() {
  local id="$1" key
  key="$(client_dir "$id")/backup.key"
  if [ ! -s "$key" ]; then
    (umask 077 && age-keygen -o "$key" >/dev/null 2>&1) || { rm -f "$key"; log_error "could not create the host backup key"; return 1; }
    log_info "created host backup key (stays on this host)"
  fi
  chmod 600 "$key"
}

host_recipient() { age-keygen -y "$(client_dir "$1")/backup.key"; }

backup_dir_for() { # ID -> local backup root for this client
  local id="$1" d
  d="$(_cfg '.backup.local_dir // ""' "$id")"
  [ -n "$d" ] || d="$(client_dir "$id")/backups"
  printf '%s' "$d"
}

# latest_backup ID -> prints the newest complete backup folder path (or nothing)
latest_backup() {
  local id="$1" base name
  base="$(backup_dir_for "$id")/$id"
  [ -d "$base" ] || return 0
  name="$(find "$base" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort | tail -n1 || true)"
  [ -n "$name" ] && printf '%s/%s' "$base" "$name"
  return 0
}

backup_list() {
  local id="$1" base
  base="$(backup_dir_for "$id")/$id"
  [ -d "$base" ] || { echo "no backups yet for $id"; return 0; }
  find "$base" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort
}

_remote_prune() { # REMOTE ID DAYS
  local remote="$1" id="$2" days="$3" name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    rclone purge "${remote%/}/${id}/${name}" >/dev/null 2>&1 && log_info "pruned remote backup ${name}"
  done < <(rclone lsf --dirs-only "${remote%/}/${id}/" 2>/dev/null | sed 's#/$##' | prune_candidates "$days" "$(date -u +%s)")
}

# backup_run ID -> exit 0 only if the local backup is complete AND (when configured) the off-server copy verified.
backup_run() {
  local id="$1" dir rec out dest keep_local keep_remote remote tag rc=0 args=() base ts
  _require_local "$id"
  dir="$(client_dir "$id")"
  out="$(backup_dir_for "$id")"
  keep_local="$(_cfg '.backup.retention_local // 14' "$id")"
  keep_remote="$(_cfg '.backup.retention_remote // 30' "$id")"
  remote="$(_cfg '.backup.remote // ""' "$id")"
  tag="$(_cfg '.install.tag // "unknown"' "$id")"

  rec="$(age_recipient)" || { emit_alert critical "$id" backup "no encryption key configured" >/dev/null; return 1; }
  [ "$(_cfg '.storage.type // "local"' "$id")" = "s3" ] && args+=(--no-storage)
  ensure_host_key "$id" || { emit_alert critical "$id" backup "host backup key missing" >/dev/null; return 1; }
  args+=(--recipient "$(host_recipient "$id")")
  # optional files that belong in the encrypted escrow when they exist (Telegram settings, monitoring user token)
  [ ! -s "$dir/alerts.env" ] || args+=(--escrow-file alerts.env)
  [ ! -s "$dir/monitor.env" ] || args+=(--escrow-file monitor.env)

  dest="$("$OPSKIT_BACKUP_AGENT" --id "$id" --compose-file "$dir/stack/docker-compose.yml" --out "$out" --recipient "$rec" \
    --escrow-dir "$dir" --escrow-file secrets.env --escrow-file client.yaml --tag "$tag" "${args[@]}" | tail -n1)" || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -d "$dest" ]; then
    emit_alert critical "$id" backup "local backup failed (exit ${rc})" >/dev/null
    return 1
  fi
  log_info "backup complete: $dest"
  prune_local "$out/$id" "$keep_local"

  if [ -n "$remote" ]; then
    require_tool rclone "apt install rclone" || return 1
    base="${remote%/}/${id}"
    ts="$(basename "$dest")"
    if rclone copy "$dest" "$base/$ts" >/dev/null 2>&1 && rclone check "$dest" "$base/$ts" --size-only >/dev/null 2>&1; then
      log_info "off-server copy verified: $base/$ts"
      _remote_prune "$remote" "$id" "$keep_remote"
    else
      emit_alert critical "$id" backup "off-server copy failed or does not match" >/dev/null
      return 1
    fi
  else
    log_warn "no backup.remote configured: backup exists only on this machine"
  fi
  send_heartbeat "$id" backup
}
