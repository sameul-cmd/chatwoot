#!/usr/bin/env bash
# Orchestrator (SPEC 9, Telegram-only per ADR-016): run checks, apply de-duplication/quiet hours, tell the owner.
# `monitor_run ID` = host checks (cron every 5 min); `monitor_run ID --channels` = channel poller (every 15 min).
# Needs: log, validate, render, deploy, alert, alert_state, health, channels_health, notify sourced first.
# shellcheck shell=bash

_label() {
  case "$1" in
    site) echo "Website" ;; containers) echo "Services" ;; sidekiq) echo "Background jobs (Sidekiq)" ;;
    queue_latency) echo "Job queue delay" ;; failed_jobs) echo "Failed jobs" ;; disk) echo "Disk space" ;;
    memory) echo "Memory" ;; restarts) echo "Restarts" ;; cert) echo "HTTPS certificate" ;; aibot) echo "AI bot" ;;
    channels_api) echo "Channel status" ;; channel-*) echo "Channel ${1#channel-}" ;; *) echo "$1" ;;
  esac
}

_mins() { echo $(($1 / 60)); }

# monitor_run ID [--channels] -> exit 0 ok; 3 if an alert could not be delivered (it is retried next cycle)
monitor_run() {
  local id="$1" mode="host" results name sev reason now tz qs qe quiet dedup remind sdir envf action msg rc=0
  shift
  [ "${1:-}" = "--channels" ] && mode="channels"
  _require_local "$id"
  # OPSKIT_STATE_NOW moves only the alert-decision clock (selftest/tests); health data keeps using real time
  now="${OPSKIT_STATE_NOW:-$(_hc_now)}"
  tz="$(_cfg '.timezone' "$id")"
  qs="$(_cfg '.alerts.quiet_hours.start // "22:00"' "$id")"
  qe="$(_cfg '.alerts.quiet_hours.end // "08:00"' "$id")"
  dedup=$(($(_cfg '.alerts.dedup_minutes // 30' "$id") * 60))
  remind=$(($(_cfg '.alerts.reminder_hours // 2' "$id") * 3600))
  quiet=0
  is_quiet "$now" "$tz" "$qs" "$qe" && quiet=1
  sdir="$(monitor_state_dir "$id")"
  envf="$(alerts_env_file "$id")"
  [ -r "$envf" ] || log_warn "no Telegram settings for ${id}: alerts go to the outbox only (opskit alerts set-telegram ${id})"

  if [ "$mode" = "channels" ]; then results="$(channels_health "$id")"; else results="$(health_checks "$id")"; fi
  # channel checks that no longer exist (inbox deleted/fixed away) count as ok so they can resolve
  if [ "$mode" = "channels" ]; then
    for name in $(state_checks "$sdir" | grep -E '^channel-' || true); do
      printf '%s\n' "$results" | grep -q "^${name}|" || results+=$'\n'"${name}|ok|no longer listed"
    done
  fi

  local held_lines=""
  while IFS='|' read -r name sev reason; do
    [ -n "$name" ] || continue
    [[ "$name" =~ ^[a-z0-9_-]+$ ]] || continue
    state_read "$sdir" "$name"
    action="$(decide_action "$sev" "$PREV_SEV" "$PREV_LAST" "$PREV_NOTIFIED" "$PREV_HELD" "$now" "$quiet" "$dedup" "$remind")"
    case "$action" in
      send)
        if [ "$sev" = "critical" ]; then msg="🔴 CRITICAL [${id}] $(_label "$name"): ${reason}"; else msg="🟠 WARNING [${id}] $(_label "$name"): ${reason}"; fi
        if telegram_send "$envf" "$msg"; then
          emit_alert "$sev" "$id" "$name" "$reason" >/dev/null
          state_write "$sdir" "$name" "$sev" "$([ "$PREV_SEV" = "ok" ] && echo "$now" || echo "$PREV_SINCE")" "$now" 1 0
        else
          emit_alert "$sev" "$id" "$name" "$reason (not delivered)" >/dev/null
          log_warn "alert for ${name} could not be delivered; will retry next cycle"
          rc=3
        fi
        ;;
      remind)
        msg="🔁 STILL CRITICAL [${id}] $(_label "$name"): ${reason} (open for $(_mins $((now - PREV_SINCE))) min)"
        if telegram_send "$envf" "$msg"; then
          state_write "$sdir" "$name" "$sev" "$PREV_SINCE" "$now" 1 0
        else rc=3; fi
        ;;
      resolve)
        msg="✅ RESOLVED [${id}] $(_label "$name"): back to normal (was ${PREV_SEV} for $(_mins $((now - PREV_SINCE))) min)"
        if telegram_send "$envf" "$msg"; then
          emit_alert info "$id" "$name" "resolved" >/dev/null
          state_write "$sdir" "$name" ok 0 "$now" 0 0
        else rc=3; fi
        ;;
      hold) state_write "$sdir" "$name" warn "$now" "$PREV_LAST" 0 1 ;;
      release) held_lines+="${name}|${reason}"$'\n' ;;
      defer) ;;
      none)
        # keep the state in step with what we saw (e.g. critical->warn, or ok)
        if [ "$sev" = "ok" ]; then
          [ "$PREV_SEV" = "ok" ] || state_write "$sdir" "$name" ok 0 "$PREV_LAST" 0 0
        elif [ "$sev" != "$PREV_SEV" ]; then
          state_write "$sdir" "$name" "$sev" "$PREV_SINCE" "$PREV_LAST" "$PREV_NOTIFIED" "$PREV_HELD"
        fi
        ;;
    esac
  done <<<"$results"

  # one summary for warnings that were held during quiet hours and are still active
  if [ -n "$held_lines" ]; then
    msg="🟠 WARNINGS [${id}] held during quiet hours:"
    while IFS='|' read -r name reason; do
      [ -n "$name" ] && msg+=$'\n'"- $(_label "$name"): ${reason}"
    done <<<"$held_lines"
    if telegram_send "$envf" "$msg"; then
      while IFS='|' read -r name reason; do
        [ -n "$name" ] || continue
        state_read "$sdir" "$name"
        state_write "$sdir" "$name" warn "$PREV_SINCE" "$now" 1 0
        emit_alert warn "$id" "$name" "$reason" >/dev/null
      done <<<"$held_lines"
    else rc=3; fi
  fi

  # dead-man's switch: an external service (e.g. healthchecks.io / UptimeRobot heartbeat) learns we are alive
  if [ "$mode" = "host" ] && [ -n "${OPSKIT_HEARTBEAT_URL:-}" ]; then
    curl -fsS --max-time 10 -o /dev/null "$OPSKIT_HEARTBEAT_URL" 2>/dev/null || log_warn "heartbeat URL did not answer"
  fi
  return "$rc"
}

# monitor_status ID -> table of the last known state of every check
monitor_status() {
  local id="$1" sdir name
  sdir="$(monitor_state_dir "$id")"
  printf '%-22s %-9s %s\n' CHECK STATE SINCE
  for name in $(state_checks "$sdir"); do
    state_read "$sdir" "$name"
    printf '%-22s %-9s %s\n' "$(_label "$name")" "$PREV_SEV" "$([ "$PREV_SINCE" -gt 0 ] && date -u -d "@$PREV_SINCE" +%H:%M:%SZ || echo -)"
  done
}
