#!/usr/bin/env bash
# Deploy / lifecycle for a client stack on the local Docker engine (remote deploy: Phase 11, ASSUMPTIONS A-005).
# Requires lib/log.sh, validate.sh, secrets.sh, render.sh, confirm.sh to be sourced first.
# shellcheck shell=bash

# dc ID args... -> docker compose always with -p <client_id> (project rule).
dc() {
  local id="$1"
  shift
  docker compose -p "$id" -f "$(client_dir "$id")/stack/docker-compose.yml" --project-directory "$(client_dir "$id")/stack" "$@"
}

_cfg() { yq -r "$1" "$(client_dir "$2")/client.yaml"; }

_require_local() {
  local target
  target="$(_cfg '.deploy.target // "remote"' "$1")"
  [ "$target" = "local" ] || die "deploy target '${target}' is not supported yet: only deploy.target: local (remote deploys arrive in Phase 11)"
}

# build_aibot_image ID -> builds opskit-aibot:<id>. OPSKIT_BUILD_CA=<bundle> adds a CA secret + host network
# for restricted networks (sandbox); normal builds need nothing.
build_aibot_image() {
  local id="$1" args=()
  if [ -n "${OPSKIT_BUILD_CA:-}" ]; then
    args+=(--network host --secret "id=cabundle,src=${OPSKIT_BUILD_CA}")
    [ -n "${HTTPS_PROXY:-}" ] && args+=(--build-arg "HTTPS_PROXY=${HTTPS_PROXY}" --build-arg "HTTP_PROXY=${HTTPS_PROXY}")
  fi
  docker build -q "${args[@]}" -t "opskit-aibot:${id}" "$OPSKIT_REPO_ROOT/aibot" >/dev/null || die "aibot image build failed"
}

wait_healthy() {
  local id="$1" timeout="${2:-300}" waited=0 cid status
  while [ "$waited" -lt "$timeout" ]; do
    cid="$(dc "$id" ps -q rails 2>/dev/null || true)"
    if [ -n "$cid" ]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo unknown)"
      [ "$status" = "healthy" ] && return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log_error "rails did not become healthy within ${timeout}s (check: docker compose -p ${id} logs rails)"
  return 1
}

# ensure_admin ID -> idempotent first Super Admin. Credentials file is written once (mode 600).
ensure_admin() {
  local id="$1" dir email result cred
  dir="$(client_dir "$id")"
  cred="$dir/admin-credentials.txt"
  email="$(_cfg '.contact.email // ""' "$id")"
  [ -n "$email" ] || email="admin@$(_cfg '.domain' "$id")"
  local raw
  load_secrets "$dir/secrets.env" || return 1
  raw="$(ADMIN_EMAIL="$email" ACCOUNT_NAME="$(_cfg '.accounts[0].name' "$id")" \
    dc "$id" exec -T -e ADMIN_EMAIL -e ADMIN_PASSWORD -e ACCOUNT_NAME rails bundle exec rails runner - \
    <"$OPSKIT_ROOT/templates/rails/ensure_admin.rb" 2>&1 || true)"
  result="$(printf '%s\n' "$raw" | grep -E '^ADMIN_(CREATED|EXISTS)$' | tail -n1 || true)"
  case "$result" in
    ADMIN_CREATED)
      load_secrets "$dir/secrets.env"
      (umask 077 && printf 'url: %s\nemail: %s\npassword: %s\n' "$(_frontend_url "$id")" "$email" "$ADMIN_PASSWORD" >"$cred")
      log_info "Super Admin created. Credentials saved to ${cred} (mode 600): move them to your password manager, then delete the file."
      if [ -t 1 ]; then printf 'Super Admin login (shown once)\n  email:    %s\n  password: %s\n' "$email" "$ADMIN_PASSWORD"; fi
      ;;
    ADMIN_EXISTS) log_info "Super Admin already exists; nothing to do" ;;
    *)
      log_error "could not ensure the Super Admin: $(printf '%s' "$raw" | grep -iE 'error|failed|Validation' | head -n1 | cut -c1-300)"
      return 1
      ;;
  esac
}

_frontend_url() { sed -n 's/^FRONTEND_URL=//p' "$(client_dir "$1")/stack/.env" | head -n1; }

deploy_client() {
  local id="$1"
  _require_local "$id"
  require_tool docker "install Docker" || return 1
  render_client "$id" || return 1
  log_info "building aibot image"
  build_aibot_image "$id"
  log_info "starting database and cache"
  dc "$id" up -d postgres redis >/dev/null
  log_info "running db:chatwoot_prepare (one-off container)"
  dc "$id" run --rm -T rails bundle exec rails db:chatwoot_prepare >/dev/null 2>&1 || die "db:chatwoot_prepare failed"
  log_info "starting the stack"
  dc "$id" up -d >/dev/null
  wait_healthy "$id" "${OPSKIT_HEALTH_TIMEOUT:-300}" || return 1
  ensure_admin "$id"
  log_info "deploy finished: $(_frontend_url "$id")"
}

pause_client() { _require_local "$1"; dc "$1" stop >/dev/null && log_info "paused $1"; }
resume_client() { _require_local "$1"; dc "$1" start >/dev/null && wait_healthy "$1" 180 && log_info "resumed $1"; }

# offboard_client ID YES -> destructive: removes containers AND volumes. Backups are not touched (kept separately).
offboard_client() {
  local id="$1" yes="${2:-}"
  confirm_destructive "offboard (delete containers and volumes of)" "$id" "$yes" || return 1
  dc "$id" down -v --remove-orphans >/dev/null 2>&1 || true
  docker image rm -f "opskit-aibot:${id}" >/dev/null 2>&1 || true
  log_info "offboarded ${id}: containers and volumes removed; ${OPSKIT_CLIENTS_DIR}/${id} kept (client.yaml, secrets)"
}
