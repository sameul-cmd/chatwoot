#!/usr/bin/env bash
# Health checks for a client stack (SPEC 9). Each check prints ONE line: name|severity|reason
# severity: ok | warn | critical. A check that cannot run reports warn ("could not check"), never ok.
# Reasons are short technical sentences: never message text, contact data or secrets.
# Needs lib/log.sh, render.sh, deploy.sh (dc, _cfg, _frontend_url) and alert_state.sh sourced first.
# shellcheck shell=bash

_hc_now() { printf '%s' "${OPSKIT_NOW:-$(date -u +%s)}"; }

# ---- pure evaluators -------------------------------------------------------------------------------------------
# sev_high_bad VALUE WARN CRIT -> ok|warn|critical (bigger is worse)
sev_high_bad() { awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN{ if (v+0>=c+0) print "critical"; else if (v+0>=w+0) print "warn"; else print "ok" }'; }
# sev_low_bad VALUE WARN CRIT -> smaller is worse (certificate days left, free memory %)
sev_low_bad() { awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN{ if (v+0<=c+0) print "critical"; else if (v+0<=w+0) print "warn"; else print "ok" }'; }

# oldest_job_age NOW < enqueued_at values on stdin -> age in whole seconds of the oldest (empty input -> 0)
oldest_job_age() { awk -v now="$1" 'BEGIN{m=0} NF{ a=now-$1; if (a>m) m=a } END{ printf "%d", m }'; }

# cert_days_left ENDDATE_TEXT NOW -> whole days until "notAfter=Dec 31 12:00:00 2026 GMT" style date
cert_days_left() {
  local end="${1#notAfter=}" now="$2" e
  e="$(date -u -d "$end" +%s 2>/dev/null)" || { echo -1; return 1; }
  echo $(((e - now) / 86400))
}

# ---- helpers -----------------------------------------------------------------------------------------------------
_hc_thr() { _cfg ".alerts.thresholds.$1 // $2" "$3"; } # KEY DEFAULT ID

_hc_redis() { # ID args... -> redis-cli through the redis container (password via env, never on a command line)
  local id="$1" pw
  shift
  pw="$(sed -n 's/^REDIS_PASSWORD=//p' "$(client_dir "$id")/stack/redis.env")"
  # </dev/null: docker exec would otherwise swallow the stdin of any `while read` loop calling this function
  REDISCLI_AUTH="$pw" dc "$id" exec -T -e REDISCLI_AUTH redis redis-cli --no-auth-warning "$@" </dev/null 2>/dev/null | tr -d '\r'
}

_hc_curl() { # ID PATH [curl args] -> local stacks use Caddy's test certificate; real hosts use the public certificate
  local id="$1" path="$2" host port
  shift 2
  host="$(_cfg '.domain' "$id")"
  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ]; then
    port="$(_cfg '.deploy.https_port // 8443' "$id")"
    curl -ks --max-time 15 --resolve "${host}:${port}:127.0.0.1" "$@" "$(_frontend_url "$id")${path}"
  else
    curl -s --max-time 15 "$@" "$(_frontend_url "$id")${path}"
  fi
}

# ---- checks ------------------------------------------------------------------------------------------------------
check_site() {
  local id="$1" api login
  api="$(_hc_curl "$id" /api || true)"
  login="$(_hc_curl "$id" /app/login -o /dev/null -w '%{http_code}' || true)"
  if [ -z "$api" ] || [ "${login:-000}" = "000" ]; then
    echo "site|critical|site is not reachable over HTTPS"
  elif [ "$login" != "200" ]; then
    echo "site|critical|login page answers HTTP ${login}"
  elif ! printf '%s' "$api" | grep -q '"queue_services":"ok"' || ! printf '%s' "$api" | grep -q '"data_services":"ok"'; then
    echo "site|critical|health route reports the database or Redis as unhealthy"
  else
    echo "site|ok|reachable, login page and health route fine"
  fi
}

check_containers() {
  local id="$1" out svc down="" expected="rails sidekiq postgres redis aibot caddy"
  out="$(dc "$id" ps -a --format '{{.Service}} {{.State}}' 2>/dev/null || true)"
  if [ -z "$out" ]; then
    echo "containers|critical|no containers found for this stack (is it down?)"
    return 0
  fi
  for svc in $expected; do
    printf '%s\n' "$out" | grep -q "^${svc} running$" || down+="${svc} "
  done
  if [ -n "$down" ]; then echo "containers|critical|not running: ${down% }"; else echo "containers|ok|all services running"; fi
}

check_sidekiq() {
  local id="$1" now alive=0 ident beat n
  now="$(_hc_now)"
  n="$(_hc_redis "$id" SCARD processes | head -n1)"
  if [ -z "$n" ]; then
    echo "sidekiq|warn|could not read Sidekiq state from Redis"
    return 0
  fi
  while IFS= read -r ident; do
    [ -n "$ident" ] || continue
    beat="$(_hc_redis "$id" HGET "$ident" beat | head -n1)"
    [ -n "$beat" ] && [ $((now - ${beat%%.*})) -le 60 ] && alive=$((alive + 1))
  done < <(_hc_redis "$id" SMEMBERS processes)
  if [ "$alive" -ge 1 ]; then echo "sidekiq|ok|${alive} worker process(es) alive"; else echo "sidekiq|critical|no Sidekiq worker is running (background jobs are not processed)"; fi
}

check_queue() {
  local id="$1" now q first warn crit sev ages="" max
  now="$(_hc_now)"
  warn="$(_hc_thr queue_latency_warn_s 300 "$id")"
  crit="$(_hc_thr queue_latency_crit_s 900 "$id")"
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    case "$q" in sidekiq-alive-*) continue ;; esac
    first="$(_hc_redis "$id" LINDEX "queue:${q}" -1 | jq -r '.enqueued_at // empty' 2>/dev/null || true)"
    [ -n "$first" ] && ages+="${first}"$'\n'
  done < <(_hc_redis "$id" SMEMBERS queues)
  max="$(printf '%s' "$ages" | oldest_job_age "$now")"
  sev="$(sev_high_bad "$max" "$warn" "$crit")"
  echo "queue_latency|${sev}|oldest waiting job is $((max / 60)) min $((max % 60)) s old"
}

check_failed_jobs() {
  local id="$1" dir f total prev warn grow
  dir="$(monitor_state_dir "$id")"
  mkdir -p "$dir"
  f="$dir/failed_jobs.counter"
  warn="$(_hc_thr failed_jobs_warn 50 "$id")"
  total=$(($(_hc_redis "$id" ZCARD retry | head -n1) + $(_hc_redis "$id" ZCARD dead | head -n1))) || {
    echo "failed_jobs|warn|could not read the retry/dead sets"
    return 0
  }
  prev="$(cat "$f" 2>/dev/null || echo "$total")"
  printf '%s' "$total" >"$f"
  grow=$((total - prev))
  if [ "$grow" -ge "$warn" ]; then echo "failed_jobs|warn|failed/retrying jobs grew by ${grow} since the last check (now ${total})"; else echo "failed_jobs|ok|${total} failed/retrying jobs (+${grow})"; fi
}

check_disk() {
  local id="$1" root pct max=0 p path warn crit
  warn="$(_hc_thr disk_warn_pct 85 "$id")"
  crit="$(_hc_thr disk_crit_pct 95 "$id")"
  root="$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo /)"
  for path in "$root" "$(client_dir "$id")"; do
    [ -e "$path" ] || continue
    p="$(df --output=pcent "$path" 2>/dev/null | tail -n1 | tr -dc '0-9')"
    [ -n "$p" ] && [ "$p" -gt "$max" ] && max="$p"
  done
  pct="$max"
  echo "disk|$(sev_high_bad "$pct" "$warn" "$crit")|disk is ${pct}% full"
}

check_memory() {
  local id="$1" total avail pct warn crit
  warn="$(_hc_thr mem_avail_warn_pct 10 "$id")"
  crit="$(_hc_thr mem_avail_crit_pct 5 "$id")"
  total="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
  avail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
  if [ -z "$total" ] || [ -z "$avail" ] || [ "$total" -eq 0 ]; then
    echo "memory|warn|could not read memory information"
    return 0
  fi
  pct=$((avail * 100 / total))
  echo "memory|$(sev_low_bad "$pct" "$warn" "$crit")|${pct}% of memory available"
}

check_restarts() {
  local id="$1" dir f now count=0 cid c base_count base_ts delta warn
  now="$(_hc_now)"
  dir="$(monitor_state_dir "$id")"
  mkdir -p "$dir"
  f="$dir/restarts.counter"
  warn="$(_hc_thr restarts_warn 3 "$id")"
  for cid in $(dc "$id" ps -aq 2>/dev/null); do
    c="$(docker inspect -f '{{.RestartCount}}' "$cid" 2>/dev/null || echo 0)"
    count=$((count + c))
  done
  if [ -r "$f" ]; then read -r base_count base_ts <"$f"; else base_count="$count"; base_ts="$now"; fi
  delta=$((count - base_count))
  if [ $((now - base_ts)) -ge 3600 ]; then printf '%s %s' "$count" "$now" >"$f"; else printf '%s %s' "$base_count" "$base_ts" >"$f"; fi
  if [ "$delta" -ge "$warn" ]; then echo "restarts|warn|containers restarted ${delta} times in the last hour"; else echo "restarts|ok|${delta} restarts in the last hour"; fi
}

check_cert() {
  local id="$1" host end days warn crit
  if [ "$(_cfg '.deploy.target // "remote"' "$id")" = "local" ]; then
    echo "cert|ok|local test certificate (not checked)"
    return 0
  fi
  host="$(_cfg '.domain' "$id")"
  warn="$(_hc_thr cert_warn_days 14 "$id")"
  crit="$(_hc_thr cert_crit_days 3 "$id")"
  end="$(echo | openssl s_client -connect "${host}:443" -servername "$host" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || true)"
  [ -n "$end" ] || { echo "cert|warn|could not read the HTTPS certificate"; return 0; }
  days="$(cert_days_left "$end" "$(_hc_now)")"
  echo "cert|$(sev_low_bad "$days" "$warn" "$crit")|HTTPS certificate expires in ${days} days"
}

check_aibot() {
  local id="$1" sev="warn"
  [ "$(_cfg '.bot.enabled // false' "$id")" = "true" ] && sev="critical"
  if dc "$id" exec -T aibot python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status == 200 else 1)" >/dev/null 2>&1; then
    echo "aibot|ok|bot health page answers"
  else
    echo "aibot|${sev}|bot health page does not answer"
  fi
}

# health_checks ID -> runs every check, one result line each
health_checks() {
  local id="$1" c
  for c in check_site check_containers check_sidekiq check_queue check_failed_jobs check_disk check_memory check_restarts check_cert check_aibot; do
    "$c" "$id" || echo "${c#check_}|warn|check could not run"
  done
}
