#!/usr/bin/env bash
# Safe upgrades (SPEC 10): info -> preflight -> backup -> staging rehearsal on the new image -> smoke -> production
# (only in the client's off-hours window) -> smoke -> automatic rollback on failure -> history.
# Never automatic: the owner starts every upgrade. Needs most other libs sourced first (see bin/opskit).
# shellcheck shell=bash

_tag_valid() { [[ "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ce$ ]]; }
_git_tag() { printf '%s' "${1%-ce}"; }
_ver_newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$2" ]; } # is $2 newer than $1

upgrade_dir() { printf '%s/upgrade' "$(client_dir "$1")"; }

# upgrade_history_add ID FROM TO RESULT NOTE [ROLLED_BACK(true|false)] [BACKUP_TS] [MIGRATIONS]
upgrade_history_add() {
  local id="$1" dir
  dir="$(upgrade_dir "$id")"
  mkdir -p "$dir"
  jq -nc --arg from "$2" --arg to "$3" --arg result "$4" --arg note "$(printf '%s' "$5" | cut -c1-300)" \
    --argjson rb "${6:-false}" --arg backup "${7:-}" --arg mig "${8:-}" --arg t "$(date -u -d "@$(_hc_now)" +%Y-%m-%dT%H:%M:%SZ)" \
    '{time:$t, from:$from, to:$to, result:$result, rolled_back:$rb, backup:$backup, migrations_applied:$mig, note:$note}' >>"$dir/history.jsonl"
}

_upgrade_notify() { # ID MESSAGE -> Telegram when configured (never fails the upgrade)
  local envf
  envf="$(alerts_env_file "$1")"
  if [ -r "$envf" ]; then telegram_send "$envf" "$2" >/dev/null 2>&1 || true; fi
  return 0
}

# set_client_tag ID TAG -> rewrites install.tag in client.yaml (keeps a dated copy for the record)
set_client_tag() {
  local id="$1" tag="$2" cfg dir
  dir="$(upgrade_dir "$id")"
  cfg="$(client_dir "$id")/client.yaml"
  mkdir -p "$dir"
  cp "$cfg" "$dir/client.yaml.$(date -u -d "@$(_hc_now)" +%Y%m%dT%H%M%SZ).bak"
  python3 - "$cfg" "$tag" <<'PY'
import sys, yaml
cfg, tag = sys.argv[1:3]
c = yaml.safe_load(open(cfg))
c.setdefault("install", {})["tag"] = tag
yaml.safe_dump(c, open(cfg, "w"), sort_keys=False)
PY
}

# upgrade_window_ok ID NOW -> exit 0 if a live upgrade is allowed now (client's off-hours window)
upgrade_window_ok() {
  local id="$1" now="$2" mode start end tz
  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ] && [ "${OPSKIT_ENFORCE_WINDOW:-0}" != "1" ]; then return 0; fi
  mode="$(_cfg '.upgrade_window.mode // "window"' "$id")"
  [ "$mode" = "anytime" ] && return 0
  start="$(_cfg '.upgrade_window.start // "01:00"' "$id")"
  end="$(_cfg '.upgrade_window.end // "05:00"' "$id")"
  tz="$(_cfg '.timezone' "$id")"
  is_quiet "$now" "$tz" "$start" "$end"
}

# ---- 5.2 release information ---------------------------------------------------------------------------------------
upgrade_info() {
  local id="$1" to="$2" cur ga gb repo n m added removed t
  _tag_valid "$to" || { log_error "target must be a Community Edition tag like v4.18.0-ce"; return 2; }
  cur="$(_cfg '.install.tag' "$id")"
  repo="$OPSKIT_REPO_ROOT"
  ga="$(_git_tag "$cur")"
  gb="$(_git_tag "$to")"
  for t in "$ga" "$gb"; do
    git -C "$repo" rev-parse -q --verify "refs/tags/${t}^{commit}" >/dev/null || {
      log_error "release ${t} is not in this checkout: run  git fetch upstream tag ${t} --no-tags"
      return 1
    }
  done
  printf 'Upgrade %s: %s -> %s\n' "$id" "$cur" "$to"
  n="$(git -C "$repo" rev-list --count "${ga}..${gb}")"
  printf '  changes:     %s commits between the two releases\n' "$n"
  m="$(git -C "$repo" diff --name-only "$ga" "$gb" -- db/migrate)"
  printf '  migrations:  %s database change(s)\n' "$(printf '%s' "$m" | grep -c . || true)"
  [ -z "$m" ] || printf '%s\n' "$m" | sed 's#^db/migrate/#               - #'
  added="$(comm -13 <(git -C "$repo" show "${ga}:.env.example" | grep -oE '^[A-Z][A-Z0-9_]*=' | sort -u) <(git -C "$repo" show "${gb}:.env.example" | grep -oE '^[A-Z][A-Z0-9_]*=' | sort -u) | tr -d '=')"
  removed="$(comm -23 <(git -C "$repo" show "${ga}:.env.example" | grep -oE '^[A-Z][A-Z0-9_]*=' | sort -u) <(git -C "$repo" show "${gb}:.env.example" | grep -oE '^[A-Z][A-Z0-9_]*=' | sort -u) | tr -d '=')"
  printf '  new settings:     %s\n' "${added:-none}"
  printf '  removed settings: %s\n' "${removed:-none}"
  if git -C "$repo" diff --quiet "$ga" "$gb" -- docker-compose.production.yaml; then
    printf '  official compose: unchanged\n'
  else
    printf '  official compose: CHANGED - review docker-compose.production.yaml and our templates before upgrading\n'
  fi
  printf 'Read the official release notes and docs/runbooks/upgrade-checklist.md before a real client upgrade.\n'
}

# ---- 5.4 preflight --------------------------------------------------------------------------------------------------
# upgrade_ensure_image TAG ID -> the target image is available locally (pull with retries on rate limits)
upgrade_ensure_image() {
  local tag="$1" id="$2" image attempt=1 delay=15
  image="$(_cfg '.install.image // "chatwoot/chatwoot"' "$id"):${tag}"
  docker image inspect "$image" >/dev/null 2>&1 && return 0
  until docker pull -q "$image" >/dev/null 2>&1; do
    [ "$attempt" -lt 5 ] || { log_error "image ${image} could not be pulled (does the tag exist?)"; return 1; }
    log_warn "pull of ${image} failed (attempt ${attempt}); retrying in ${delay}s"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

# upgrade_preflight ID TAG MODE(stage|apply) [outage_fix]
upgrade_preflight() {
  local id="$1" to="$2" mode="$3" outage="${4:-}" cur now problems=() last f age free need bdir size
  now="$(_hc_now)"
  _tag_valid "$to" || { log_error "target must be a Community Edition tag like v4.18.0-ce"; return 2; }
  cur="$(_cfg '.install.tag' "$id")"
  [ "$to" != "$cur" ] || problems+=("already on ${to}")
  _ver_newer "${cur%-ce}" "${to%-ce}" || problems+=("${to} is not newer than ${cur} (downgrades are not supported)")
  [ -f "$(client_dir "$id")/stack/docker-compose.yml" ] || problems+=("client has not been deployed")
  if [ "${#problems[@]}" -eq 0 ]; then
    wait_healthy "$id" 30 >/dev/null 2>&1 || problems+=("the live stack is not healthy right now: fix that first")
    bdir="$(latest_backup "$id")"
    if [ -n "$bdir" ]; then size="$(du -sb "$bdir" | cut -f1)"; else size=0; fi
    need=$((size * 2 / 1024 + 2097152))
    free="$(df --output=avail "$(client_dir "$id")" | tail -n1 | tr -dc '0-9')"
    [ "${free:-0}" -ge "$need" ] || problems+=("not enough free disk space (need about $((need / 1024)) MB)")
  fi
  if [ "$mode" = "apply" ]; then
    if ! upgrade_window_ok "$id" "$now"; then
      if [ "$outage" = "yes" ]; then log_warn "outside the off-hours window: allowed because --outage-fix was given"
      else problems+=("outside the client's off-hours window ($(_cfg '.upgrade_window.start // "01:00"' "$id")-$(_cfg '.upgrade_window.end // "05:00"' "$id") $(_cfg '.timezone' "$id")); use --outage-fix only for an outage"); fi
    fi
    f="$(upgrade_dir "$id")/staging-${to}.json"
    if [ ! -f "$f" ] || [ "$(jq -r .status "$f" 2>/dev/null)" != "pass" ] || [ "$(jq -r .from_tag "$f" 2>/dev/null)" != "$cur" ]; then
      problems+=("no passing staging rehearsal for ${cur} -> ${to}: run  opskit upgrade ${id} --to ${to} --stage")
    else
      last="$(jq -r .finished_epoch "$f")"
      age=$((now - last))
      [ "$age" -le 86400 ] || problems+=("the staging rehearsal is older than 24 hours: repeat it")
    fi
  fi
  if [ "${#problems[@]}" -gt 0 ]; then
    local p
    for p in "${problems[@]}"; do log_error "preflight: ${p}"; done
    return 1
  fi
  log_info "preflight ok (${mode}): ${cur} -> ${to}"
}

# ---- 5.5 staging rehearsal ------------------------------------------------------------------------------------------
upgrade_stage() {
  local id="$1" to="$2" cur sid bdir now started rc=0 out mig_before mig_after file status="pass" reason=""
  upgrade_preflight "$id" "$to" stage || return 1
  now="$(_hc_now)"
  cur="$(_cfg '.install.tag' "$id")"
  sid="$(_staging_id "$id")"
  bdir="$(latest_backup "$id")"
  if [ -z "$bdir" ] || [ $((now - $(_ts_to_epoch "$(basename "$bdir")"))) -gt 86400 ]; then
    log_info "no backup from the last 24 hours: making one"
    backup_run "$id" || { log_error "backup failed: upgrade stopped"; return 1; }
    bdir="$(latest_backup "$id")"
  fi
  upgrade_ensure_image "$to" "$id" || return 1
  _staging_exists "$sid" && teardown_staging "$sid"
  started="$now"
  log_info "rehearsal: restoring ${cur} backup $(basename "$bdir") into ${sid} running ${to}"
  mig_before="$(jq -r .migrations_count "$bdir/manifest.json")"
  export OPSKIT_STAGING_TAG="$to"
  if restore_to_staging "$id" "$bdir" ""; then
    mig_after="$(_psql_sid "$sid" 'SELECT count(*) FROM schema_migrations')"
    log_info "database changes applied on the copy: $((mig_after - mig_before))"
    out="$(smoke_run "$sid" staging "$bdir" 2>&1)" || { status="fail"; reason="smoke tests failed on the staging copy"; rc=1; }
    printf '%s\n' "$out"
  else
    status="fail"
    reason="staging copy could not be built on ${to} (migration or startup error)"
    mig_after=""
    rc=1
  fi
  unset OPSKIT_STAGING_TAG
  mkdir -p "$(upgrade_dir "$id")"
  file="$(upgrade_dir "$id")/staging-${to}.json"
  jq -n --arg s "$status" --arg r "$reason" --arg f "$cur" --arg t "$to" --arg b "$(basename "$bdir")" --argjson e "$(_hc_now)" \
    --argjson secs "$(($(_hc_now) - started))" --arg m "$([ -n "${mig_after:-}" ] && echo $((mig_after - mig_before)) || echo "")" \
    '{status:$s, reason:$r, from_tag:$f, to_tag:$t, backup:$b, finished_epoch:$e, seconds:$secs, migrations_applied:$m}' >"$file"
  teardown_staging "$sid"
  if [ "$rc" -eq 0 ]; then log_info "staging rehearsal PASSED (${cur} -> ${to}); result saved to ${file}"; else log_error "staging rehearsal FAILED: ${reason}"; fi
  return "$rc"
}

# ---- 5.8 rollback ---------------------------------------------------------------------------------------------------
# upgrade_rollback ID OLD_TAG BACKUP_DIR REASON -> back to the old version; database restored only if it changed
upgrade_rollback() {
  local id="$1" old="$2" bdir="$3" reason="$4" now_ver want_ver restore_db=0 tmp key
  log_warn "ROLLBACK to ${old}: ${reason}"
  _upgrade_notify "$id" "↩️ ROLLBACK [${id}] upgrade failed (${reason}); going back to ${old}"
  set_client_tag "$id" "$old"
  render_client "$id" >/dev/null || return 1
  want_ver="$(jq -r .schema_version "$bdir/manifest.json")"
  now_ver="$(_psql_sid "$id" "SELECT coalesce(max(version),'0') FROM schema_migrations")"
  if [ -z "$now_ver" ] || [ "$now_ver" != "$want_ver" ]; then restore_db=1; fi
  if [ "$restore_db" -eq 1 ]; then
    log_warn "database changed during the upgrade (version ${now_ver:-unknown} vs ${want_ver}): restoring it from the pre-upgrade backup"
    key="$(client_dir "$id")/backup.key"
    tmp="$(mktemp -d)"
    decrypt_file "$bdir/db.dump.age" "$tmp/db.dump" "$key" || { rm -rf "$tmp"; return 1; }
    dc "$id" stop rails sidekiq aibot >/dev/null 2>&1 || true
    dc "$id" exec -T postgres psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS chatwoot WITH (FORCE)" </dev/null >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    dc "$id" exec -T postgres psql -U postgres -d postgres -c "CREATE DATABASE chatwoot" </dev/null >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    dc "$id" exec -T postgres pg_restore -U postgres -d chatwoot --no-owner <"$tmp/db.dump" >/dev/null 2>&1 || true
    rm -rf "$tmp"
  else
    log_info "database unchanged: only the program version is switched back"
  fi
  dc "$id" up -d >/dev/null 2>&1 || return 1
  wait_healthy "$id" "${OPSKIT_HEALTH_TIMEOUT:-300}" || return 1
  return 0
}

# ---- 5.7 production upgrade ----------------------------------------------------------------------------------------------
# upgrade_apply ID TAG YES OUTAGE_FIX
upgrade_apply() {
  local id="$1" to="$2" yes="${3:-}" outage="${4:-}" cur bdir bts out reason="" failed=0 mig_before mig_after
  upgrade_preflight "$id" "$to" apply "$outage" || return 1
  confirm_destructive "upgrade the LIVE client" "$id" "$yes" || return 1
  cur="$(_cfg '.install.tag' "$id")"
  upgrade_history_add "$id" "$cur" "$to" started "upgrade started"
  _upgrade_notify "$id" "🔧 UPGRADE [${id}] ${cur} -> ${to} started"

  log_info "fresh backup before the upgrade"
  backup_run "$id" || { upgrade_history_add "$id" "$cur" "$to" aborted "pre-upgrade backup failed"; log_error "backup failed: nothing was changed"; return 1; }
  bdir="$(latest_backup "$id")"
  bts="$(basename "$bdir")"
  mig_before="$(jq -r .migrations_count "$bdir/manifest.json")"
  upgrade_ensure_image "$to" "$id" || { upgrade_history_add "$id" "$cur" "$to" aborted "image not available"; return 1; }

  set_client_tag "$id" "$to"
  if ! render_client "$id" >/dev/null; then failed=1; reason="render failed"; fi
  if [ "$failed" -eq 0 ]; then
    log_info "running db:chatwoot_prepare on ${to}"
    dc "$id" run --rm -T rails bundle exec rails db:chatwoot_prepare >/dev/null 2>&1 || { failed=1; reason="db:chatwoot_prepare failed on ${to}"; }
  fi
  if [ "$failed" -eq 0 ]; then
    dc "$id" up -d >/dev/null 2>&1 || { failed=1; reason="stack did not start on ${to}"; }
  fi
  if [ "$failed" -eq 0 ]; then
    wait_healthy "$id" "${OPSKIT_HEALTH_TIMEOUT:-300}" || { failed=1; reason="stack did not become healthy on ${to}"; }
  fi
  if [ "$failed" -eq 0 ]; then
    out="$(smoke_run "$id" production "$bdir" 2>&1)" || { failed=1; reason="smoke tests failed on ${to}"; }
    printf '%s\n' "$out"
  fi

  if [ "$failed" -eq 0 ]; then
    mig_after="$(_psql_sid "$id" 'SELECT count(*) FROM schema_migrations')"
    upgrade_history_add "$id" "$cur" "$to" success "smoke tests passed" false "$bts" "$((mig_after - mig_before))"
    _upgrade_notify "$id" "✅ UPGRADE [${id}] ${cur} -> ${to} finished and tested"
    log_info "UPGRADE SUCCEEDED: ${id} now runs ${to}"
    return 0
  fi

  log_error "upgrade failed: ${reason}"
  if upgrade_rollback "$id" "$cur" "$bdir" "$reason"; then
    out="$(smoke_run "$id" rollback "$bdir" --strict 2>&1)" && {
      printf '%s\n' "$out"
      upgrade_history_add "$id" "$cur" "$to" rolled_back "$reason" true "$bts"
      emit_alert critical "$id" upgrade "upgrade to ${to} failed and was rolled back to ${cur}: ${reason}" >/dev/null
      _upgrade_notify "$id" "🔴 UPGRADE [${id}] to ${to} FAILED (${reason}). Rolled back to ${cur}: data checked and intact."
      log_error "ROLLED BACK to ${cur}; data verified"
      return 1
    }
    printf '%s\n' "$out"
    reason="${reason}; rollback smoke tests failed"
  fi
  upgrade_history_add "$id" "$cur" "$to" rollback_failed "$reason" true "$bts"
  emit_alert critical "$id" upgrade "UPGRADE AND ROLLBACK FAILED (${reason}). Restore manually: opskit restore ${id} --from ${bts} --target staging, backup folder $(basename "$bdir")" >/dev/null
  _upgrade_notify "$id" "🔴🔴 UPGRADE [${id}] AND ROLLBACK FAILED. Manual action needed. Backup: ${bts}"
  log_error "ROLLBACK FAILED: manual action needed (backup ${bts} is intact)"
  return 2
}
