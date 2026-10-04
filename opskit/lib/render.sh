#!/usr/bin/env bash
# Render a client's stack files from client.yaml + templates. Fails on any unresolved ${...}.
# Requires lib/log.sh, lib/validate.sh, lib/secrets.sh to be sourced first. Needs yq and envsubst.
# shellcheck shell=bash

OPSKIT_CLIENTS_DIR="${OPSKIT_CLIENTS_DIR:-$OPSKIT_ROOT/clients}"
OPSKIT_REPO_ROOT="${OPSKIT_REPO_ROOT:-$(cd "$OPSKIT_ROOT/.." && pwd)}"

client_dir() { printf '%s/%s' "$OPSKIT_CLIENTS_DIR" "$1"; }

_y() { yq -r "$1" "$2"; }

# render_template TEMPLATE OUT VARNAMES... -> envsubst with an explicit allow-list, then verify nothing is left.
render_template() {
  local tmpl="$1" out="$2" shellvars="" v
  shift 2
  for v in "$@"; do shellvars+="\${$v} "; done
  envsubst "$shellvars" <"$tmpl" >"$out"
  if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$out" >&2; then
    log_error "unresolved variables in rendered $(basename "$out") (see lines above)"
    rm -f "$out"
    return 1
  fi
}

# render_client ID -> writes <client_dir>/stack/{docker-compose.yml,.env,aibot.env,Caddyfile}
render_client() {
  local id="$1" dir cfg stack
  dir="$(client_dir "$id")"
  cfg="$dir/client.yaml"
  [ -f "$cfg" ] || die "client not found: $id (expected $cfg)"
  python3 "$OPSKIT_ROOT/lib/schema_check.py" client "$cfg" || die "client.yaml is invalid"

  ensure_secrets "$dir/secrets.env" || return 1
  (
    load_secrets "$dir/secrets.env" || exit 1
    local target http_port https_port domain
    export CLIENT_ID="$id" REPO_ROOT="$OPSKIT_REPO_ROOT"
    CW_IMAGE="$(_y '.install.image // "chatwoot/chatwoot"' "$cfg")"
    CW_TAG="$(_y '.install.tag // "v4.18.0-ce"' "$cfg")"
    case "$CW_TAG" in *-ce) ;; *) log_error "install.tag must be a Community Edition tag ending in -ce (got '$CW_TAG')"; exit 1 ;; esac
    domain="$(_y '.domain' "$cfg")"
    target="$(_y '.deploy.target // "remote"' "$cfg")"
    RAILS_MEM="$(_y '.sizing.rails_mem // "1536m"' "$cfg")"
    SIDEKIQ_MEM="$(_y '.sizing.sidekiq_mem // "1g"' "$cfg")"
    POSTGRES_MEM="$(_y '.sizing.postgres_mem // "1g"' "$cfg")"
    REDIS_MEM="$(_y '.sizing.redis_mem // "256m"' "$cfg")"
    AIBOT_MEM="$(_y '.sizing.aibot_mem // "256m"' "$cfg")"
    RAILS_MAX_THREADS="$(_y '.sizing.rails_max_threads // 5' "$cfg")"
    SIDEKIQ_CONCURRENCY="$(_y '.sizing.sidekiq_concurrency // 5' "$cfg")"
    STORAGE_SERVICE="$(_y '.storage.type // "local"' "$cfg")"
    [ "$STORAGE_SERVICE" = "s3" ] && STORAGE_SERVICE="amazon"
    export CW_IMAGE CW_TAG RAILS_MEM SIDEKIQ_MEM POSTGRES_MEM REDIS_MEM AIBOT_MEM RAILS_MAX_THREADS SIDEKIQ_CONCURRENCY STORAGE_SERVICE

    if [ "$target" = "local" ]; then
      http_port="$(_y '.deploy.http_port // 8080' "$cfg")"
      https_port="$(_y '.deploy.https_port // 8443' "$cfg")"
      HTTP_BIND="127.0.0.1:${http_port}"
      HTTPS_BIND="127.0.0.1:${https_port}"
      FRONTEND_URL="https://${domain}:${https_port}"
      CADDY_SITE="${domain}"
      CADDY_TLS="tls internal"
      SMTP_HOST="mailpit"; SMTP_PORT=1025; SMTP_AUTH=""; SMTP_STARTTLS="false"
      SMTP_USER=""
      MAILPIT_SERVICE="$(cat "$OPSKIT_ROOT/templates/mailpit.service.tmpl")"
    else
      HTTP_BIND="80"
      HTTPS_BIND="443"
      FRONTEND_URL="https://${domain}"
      CADDY_SITE="${domain}"
      CADDY_TLS=""
      SMTP_HOST="$(_y '.smtp.host // ""' "$cfg")"
      SMTP_PORT="$(_y '.smtp.port // 587' "$cfg")"
      SMTP_AUTH="plain"; SMTP_STARTTLS="true"
      MAILPIT_SERVICE=""
    fi
    [ "$target" = "local" ] || SMTP_USER="$(_y '.smtp.user // ""' "$cfg")"
    SMTP_SENDER="$(_y '.smtp.sender // ""' "$cfg")"
    [ -n "$SMTP_SENDER" ] || SMTP_SENDER="$(_y '.name' "$cfg") <noreply@${domain}>"
    SMTP_DOMAIN="${domain}"
    SMTP_PASSWORD="${SMTP_PASSWORD:-}"
    # Chatwoot treats an EMPTY SMTP_USERNAME as "set" and then tries to log in (verified on v4.18.0), so the
    # login lines are only written when a user name is configured.
    SMTP_AUTH_LINES=""
    if [ -n "$SMTP_USER" ]; then
      SMTP_AUTH_LINES="SMTP_USERNAME=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_AUTHENTICATION=${SMTP_AUTH:-plain}"
    fi
    export HTTP_BIND HTTPS_BIND FRONTEND_URL CADDY_SITE CADDY_TLS SMTP_HOST SMTP_PORT SMTP_AUTH SMTP_STARTTLS \
      MAILPIT_SERVICE SMTP_USER SMTP_SENDER SMTP_DOMAIN SMTP_PASSWORD SMTP_AUTH_LINES

    # aibot: non-secret LLM settings from client.yaml; the key itself is added in Phase 8 (never in this file).
    AIBOT_LLM_LINES=""
    if [ "$(_y '.bot.enabled // false' "$cfg")" = "true" ]; then
      AIBOT_LLM_LINES="AIBOT_LLM_BASE_URL=$(_y '.bot.llm.base_url' "$cfg")
AIBOT_LLM_MODEL=$(_y '.bot.llm.model' "$cfg")
AIBOT_LLM_EFFORT=$(_y '.bot.llm.effort // "medium"' "$cfg")
AIBOT_LLM_EFFORT_PARAM=$(_y '.bot.llm.effort_param // "reasoning_effort"' "$cfg")
AIBOT_LLM_TIER_PAID=true"
    fi
    export AIBOT_LLM_LINES

    stack="$dir/stack"
    mkdir -p "$stack"
    (umask 077
      printf 'POSTGRES_DB=chatwoot\nPOSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD" >"$stack/postgres.env"
      printf 'REDIS_PASSWORD=%s\n' "$REDIS_PASSWORD" >"$stack/redis.env"
      : >"$stack/.env.tmp" && : >"$stack/aibot.env.tmp")
    chmod 600 "$stack/postgres.env" "$stack/redis.env"
    render_template "$OPSKIT_ROOT/templates/compose.yml.tmpl" "$stack/docker-compose.yml" \
      CLIENT_ID CW_IMAGE CW_TAG RAILS_MEM SIDEKIQ_MEM POSTGRES_MEM REDIS_MEM AIBOT_MEM \
      HTTP_BIND HTTPS_BIND MAILPIT_SERVICE
    render_template "$OPSKIT_ROOT/templates/env.tmpl" "$stack/.env.tmp" \
      CLIENT_ID SECRET_KEY_BASE FRONTEND_URL RAILS_MAX_THREADS SIDEKIQ_CONCURRENCY POSTGRES_PASSWORD REDIS_PASSWORD \
      STORAGE_SERVICE SMTP_SENDER SMTP_DOMAIN SMTP_HOST SMTP_PORT SMTP_AUTH_LINES SMTP_STARTTLS
    render_template "$OPSKIT_ROOT/templates/aibot.env.tmpl" "$stack/aibot.env.tmp" \
      CLIENT_ID AIBOT_WEBHOOK_SECRET AIBOT_LLM_LINES
    render_template "$OPSKIT_ROOT/templates/Caddyfile.tmpl" "$stack/Caddyfile" CLIENT_ID CADDY_SITE CADDY_TLS
    chmod 600 "$stack/.env.tmp" "$stack/aibot.env.tmp"
    mv -f "$stack/.env.tmp" "$stack/.env"
    mv -f "$stack/aibot.env.tmp" "$stack/aibot.env"
  ) || return 1
  log_info "rendered stack for ${id} in ${dir}/stack"
}
