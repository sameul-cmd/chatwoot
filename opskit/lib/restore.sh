#!/usr/bin/env bash
# `opskit restore` and `opskit backup verify` (SPEC 8). Restores always go into a FRESH staging stack
# (project <id>-staging, own volumes/ports); they never touch the running production stack.
# Needs the other libs (deploy, render, backup, crypto, alert) sourced first.
# shellcheck shell=bash

_staging_id() { printf '%s-staging' "$1"; }

# _staging_exists SID -> true if containers, volumes or a client folder of that staging stack exist
_staging_exists() {
  local sid="$1"
  [ -d "$(client_dir "$sid")/stack" ] && return 0
  [ -n "$(docker volume ls -q --filter "name=^${sid}_" 2>/dev/null)" ] && return 0
  return 1
}

# teardown_staging SID -> removes containers, volumes, image and the folder (which holds copied secrets)
teardown_staging() {
  local sid="$1"
  if [ -f "$(client_dir "$sid")/stack/docker-compose.yml" ]; then
    dc "$sid" down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  docker volume ls -q --filter "name=^${sid}_" 2>/dev/null | xargs -r docker volume rm -f >/dev/null 2>&1 || true
  docker image rm -f "opskit-aibot:${sid}" >/dev/null 2>&1 || true
  rm -rf "${OPSKIT_CLIENTS_DIR:?}/${sid}"
}

_resolve_backup() { # ID FROM -> prints backup folder
  local id="$1" from="$2" d
  if [ "$from" = "latest" ]; then
    d="$(latest_backup "$id")"
  else
    [[ "$from" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { log_error "--from must be 'latest' or a timestamp like 20261004T020000Z"; return 1; }
    d="$(backup_dir_for "$id")/$id/$from"
  fi
  if [ -z "$d" ] || [ ! -f "$d/manifest.json" ]; then
    log_error "backup not found (${from}); see: opskit backup list ${id}"
    return 1
  fi
  printf '%s' "$d"
}

_verify_manifest_files() { # BACKUP_DIR -> checks sha256 of every file named in the manifest
  local d="$1" name want got
  while IFS=$'\t' read -r name want; do
    [ -f "$d/$name" ] || { log_error "backup file missing: $name"; return 1; }
    got="$(sha256sum "$d/$name" | cut -d' ' -f1)"
    [ "$got" = "$want" ] || { log_error "checksum mismatch: $name (backup damaged)"; return 1; }
  done < <(jq -r '.files | to_entries[] | [.key, .value.sha256] | @tsv' "$d/manifest.json")
}

_wait_container_healthy() { # SID SERVICE TIMEOUT
  local sid="$1" svc="$2" timeout="${3:-120}" waited=0 cid st
  while [ "$waited" -lt "$timeout" ]; do
    cid="$(dc "$sid" ps -q "$svc" 2>/dev/null || true)"
    st="$([ -n "$cid" ] && docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo none)"
    [ "$st" = "healthy" ] && return 0
    sleep 3
    waited=$((waited + 3))
  done
  log_error "$svc did not become healthy in ${timeout}s"
  return 1
}

# _staging_config SRC DST SID -> staging copy of client.yaml: new id, local target, ports +100, no backup/remote settings
_staging_config() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys, yaml
src, dst, sid = sys.argv[1:4]
c = yaml.safe_load(open(src))
c["client_id"] = sid
c.pop("backup", None)
d = c.setdefault("deploy", {})
d["target"] = "local"
d["http_port"] = int(d.get("http_port", 8080)) + 100
d["https_port"] = int(d.get("https_port", 8443)) + 100
yaml.safe_dump(c, open(dst, "w"), sort_keys=False)
PY
}

# restore_to_staging ID BACKUP_DIR IDENTITY_FILE_OR_EMPTY -> staging stack running; sets RESTORE_ESCROW_STATUS
restore_to_staging() {
  local id="$1" bdir="$2" identity="$3" sid sdir tmp
  sid="$(_staging_id "$id")"
  sdir="$(client_dir "$sid")"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  _verify_manifest_files "$bdir" || return 1

  RESTORE_ESCROW_STATUS="not-tested"
  mkdir -p "$sdir"
  if [ -n "$identity" ]; then
    decrypt_file "$bdir/escrow.tar.age" "$tmp/escrow.tar" "$identity" || return 1
    tar -x -C "$tmp" -f "$tmp/escrow.tar" secrets.env client.yaml || { log_error "escrow archive unreadable"; return 1; }
    cp "$tmp/client.yaml" "$tmp/orig-client.yaml"
    if cmp -s "$tmp/secrets.env" "$(client_dir "$id")/secrets.env" 2>/dev/null; then RESTORE_ESCROW_STATUS="decrypts-and-matches-live"; else RESTORE_ESCROW_STATUS="decrypts-differs-from-live"; fi
    (umask 077 && cp "$tmp/secrets.env" "$sdir/secrets.env")
    _staging_config "$tmp/orig-client.yaml" "$sdir/client.yaml" "$sid"
  else
    # automated monthly test: the live secrets are already on this host, so no private key is needed
    (umask 077 && cp "$(client_dir "$id")/secrets.env" "$sdir/secrets.env")
    _staging_config "$(client_dir "$id")/client.yaml" "$sdir/client.yaml" "$sid"
  fi
  chmod 600 "$sdir/secrets.env"

  render_client "$sid" || return 1
  build_aibot_image "$sid"
  log_info "restoring into ${sid}: database"
  dc "$sid" up -d postgres redis >/dev/null
  _wait_container_healthy "$sid" postgres 120 || return 1
  local err
  err="$(dc "$sid" exec -T postgres pg_restore -U postgres -d chatwoot --no-owner --clean --if-exists <"$bdir/db.dump" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -qiE 'fatal|could not connect'; then
    log_error "pg_restore failed: $(printf '%s' "$err" | head -n1 | cut -c1-200)"
    return 1
  fi
  log_info "restoring into ${sid}: migrations check and start"
  dc "$sid" run --rm -T rails bundle exec rails db:chatwoot_prepare >/dev/null 2>&1 || { log_error "db:chatwoot_prepare failed on the restored database"; return 1; }
  dc "$sid" up -d rails >/dev/null
  if [ -f "$bdir/storage.tar.gz" ]; then
    log_info "restoring into ${sid}: uploads"
    dc "$sid" exec -T rails tar xzf - -C /app/storage <"$bdir/storage.tar.gz" || { log_error "uploads restore failed"; return 1; }
  fi
  dc "$sid" up -d >/dev/null
  wait_healthy "$sid" "${OPSKIT_HEALTH_TIMEOUT:-300}" || return 1
}

# restore_client ID --from TS|latest --target staging [--identity FILE] [--overwrite --yes]
restore_client() {
  local id="$1" from="" target="" identity="" overwrite="" yes="" sid bdir
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --target) target="${2:-}"; shift 2 ;;
      --identity) identity="${2:-}"; shift 2 ;;
      --overwrite) overwrite="yes"; shift ;;
      --yes) yes="yes"; shift ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  [ -n "$from" ] || { log_error "usage: opskit restore <id> --from <timestamp|latest> --target staging [--identity key.txt] [--overwrite --yes]"; return 2; }
  case "$target" in
    staging) ;;
    new-host) die "--target new-host is not supported yet: a new host is a remote deploy (Phase 11, ASSUMPTIONS A-010)" ;;
    *) log_error "--target must be staging"; return 2 ;;
  esac
  _require_local "$id"
  sid="$(_staging_id "$id")"
  bdir="$(_resolve_backup "$id" "$from")" || return 1

  if _staging_exists "$sid"; then
    if [ "$overwrite" != "yes" ]; then
      log_error "staging stack '${sid}' already exists; refusing to overwrite it (add --overwrite --yes, or remove it first)"
      return 1
    fi
    confirm_destructive "overwrite the existing staging stack" "$sid" "$yes" || return 1
    teardown_staging "$sid"
  fi
  restore_to_staging "$id" "$bdir" "$identity" || { log_error "restore failed; staging stack left for inspection: opskit restore ... --overwrite --yes to retry"; return 1; }
  log_info "restore finished: $(_frontend_url "$sid") (escrow: ${RESTORE_ESCROW_STATUS})"
}

_psql_sid() { dc "$1" exec -T postgres psql -U postgres -d chatwoot -tA -c "$2" 2>/dev/null | tr -d '\r' | head -n1; }

# backup_verify ID [--identity FILE] [--keep] -> restore test; writes verify/<ts>.json; alerts on failure
backup_verify() {
  local id="$1" identity="" keep=0 sid bdir started rc=0 login conv attach escrow status out vdir
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      --keep) keep=1; shift ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
  done
  _require_local "$id"
  sid="$(_staging_id "$id")"
  bdir="$(latest_backup "$id")"
  [ -n "$bdir" ] || { emit_alert critical "$id" restore_test "no backup to test" >/dev/null; return 1; }
  started="$(date -u +%s)"
  _staging_exists "$sid" && teardown_staging "$sid"
  login="skipped" conv="skipped" attach="skipped"
  if restore_to_staging "$id" "$bdir" "$identity"; then
    local code want_c want_m got_c got_m sample key sum size path got_sum
    # 1. login with the admin account
    load_secrets "$(client_dir "$sid")/secrets.env"
    local email
    email="$(_cfg '.contact.email // ""' "$id")"
    [ -n "$email" ] || email="admin@$(_cfg '.domain' "$id")"
    # password travels via the environment (exported by load_secrets), never as a command-line argument
    code="$(jq -n --arg e "$email" '{email:$e,password:env.ADMIN_PASSWORD}' \
      | _curl "$sid" /auth/sign_in -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @-)"
    if [ "$code" = "200" ]; then login="pass"; else login="fail(http ${code:-none})"; fi
    # 2. conversations: same count and same newest id as when the backup was taken
    want_c="$(jq -r .conversations "$bdir/manifest.json")"
    want_m="$(jq -r .latest_conversation_id "$bdir/manifest.json")"
    got_c="$(_psql_sid "$sid" 'SELECT count(*) FROM conversations')"
    got_m="$(_psql_sid "$sid" 'SELECT coalesce(max(id),0) FROM conversations')"
    if [ "$got_c" = "$want_c" ] && [ "$got_m" = "$want_m" ]; then conv="pass(${got_c} conversations, newest #${got_m})"; else conv="fail(expected ${want_c}/#${want_m}, got ${got_c:-?}/#${got_m:-?})"; fi
    # 3. attachment: newest file blob exists and matches its recorded checksum
    sample="$(jq -r '.sample_blob // empty | [.key,.checksum,.byte_size] | @tsv' "$bdir/manifest.json")"
    if [ "$(jq -r .storage_included "$bdir/manifest.json")" != "true" ]; then
      attach="skipped(storage not in backup)"
    elif [ -z "$sample" ]; then
      attach="warn(no attachments in this backup to test)"
    else
      IFS=$'\t' read -r key sum size <<<"$sample"
      path="/app/storage/${key:0:2}/${key:2:2}/${key}"
      got_sum="$(dc "$sid" exec -T rails ruby -rdigest -e "p=ARGV[0]; puts(File.exist?(p) ? Digest::MD5.base64digest(File.binread(p)) + '|' + File.size(p).to_s : 'missing')" "$path" 2>/dev/null | tail -n1)"
      if [ "$got_sum" = "${sum}|${size}" ]; then attach="pass(newest attachment matches checksum)"; else attach="fail(${got_sum:-no answer})"; fi
    fi
  else
    login="fail(restore did not complete)"
    conv="fail(restore did not complete)"
    attach="fail(restore did not complete)"
  fi
  escrow="${RESTORE_ESCROW_STATUS:-not-tested}"
  status="pass"
  case "$login$conv$attach" in *fail*) status="fail" ;; esac
  vdir="$(client_dir "$id")/verify"
  mkdir -p "$vdir"
  out="$vdir/$(date -u +%Y%m%dT%H%M%SZ).json"
  jq -n --arg id "$id" --arg b "$(basename "$bdir")" --arg s "$status" --arg l "$login" --arg c "$conv" --arg a "$attach" --arg e "$escrow" \
    --argjson secs "$(($(date -u +%s) - started))" \
    '{client_id:$id, backup:$b, status:$s, seconds:$secs, checks:{login:$l, conversations:$c, attachment:$a, escrow:$e}}' >"$out"
  printf 'restore test: %s  (login=%s, conversations=%s, attachment=%s, escrow=%s)\n' "$status" "$login" "$conv" "$attach" "$escrow"
  [ "$keep" -eq 1 ] || teardown_staging "$sid"
  if [ "$status" != "pass" ]; then
    emit_alert critical "$id" restore_test "restore test failed: login=${login} conversations=${conv} attachment=${attach}" >/dev/null
    rc=1
  else
    send_heartbeat "$id" restore_test
  fi
  return "$rc"
}
