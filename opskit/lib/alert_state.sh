#!/usr/bin/env bash
# Alert state and de-duplication (SPEC 9, Phase 4). Pure decision function + small per-check state files.
# Severities: ok | warn | critical (a check that cannot run is reported as warn, never as ok).
# shellcheck shell=bash

# is_quiet NOW_EPOCH TZ START(HH:MM) END(HH:MM) -> exit 0 if NOW falls inside the quiet window (may span midnight)
is_quiet() {
  local now="$1" tz="$2" start="$3" end="$4" cur s e
  cur="$(TZ="$tz" date -d "@${now}" +%H%M)"
  s="${start/:/}"
  e="${end/:/}"
  cur=$((10#$cur))
  s=$((10#$s))
  e=$((10#$e))
  if [ "$s" -le "$e" ]; then
    [ "$cur" -ge "$s" ] && [ "$cur" -lt "$e" ]
  else
    [ "$cur" -ge "$s" ] || [ "$cur" -lt "$e" ]
  fi
}

# decide_action SEV PREV_SEV PREV_LAST_SENT PREV_NOTIFIED PREV_HELD NOW QUIET(0|1) DEDUP_S REMIND_S
# prints one of: send | remind | resolve | hold | release | defer | none
#   send     new problem (or upgrade warn->critical): tell the owner now
#   remind   critical still open after REMIND_S: one reminder
#   resolve  a problem the owner was told about is gone: one "resolved" message
#   hold     warning during quiet hours: remember it, send later in the summary
#   release  a held warning that is still active after quiet hours: include in the summary
#   defer    same alert was sent < DEDUP_S ago: do not repeat, try again next cycle
#   none     nothing to do
decide_action() {
  local sev="$1" prev="$2" last="$3" notified="$4" held="$5" now="$6" quiet="$7" dedup="$8" remind="$9" age
  age=$((now - last))
  case "$sev" in
    ok)
      if [ "$prev" != "ok" ] && [ "$notified" = "1" ]; then echo resolve; else echo none; fi
      ;;
    warn | critical)
      if [ "$prev" = "ok" ]; then
        if [ "$sev" = "warn" ] && [ "$quiet" = "1" ]; then
          echo hold
        elif [ "$last" -gt 0 ] && [ "$age" -lt "$dedup" ]; then
          echo defer
        else
          echo send
        fi
      elif [ "$prev" = "warn" ] && [ "$sev" = "critical" ]; then
        echo send
      elif [ "$prev" = "critical" ] && [ "$sev" = "warn" ]; then
        echo none
      elif [ "$sev" = "critical" ]; then
        if [ "$last" -gt 0 ] && [ "$age" -ge "$remind" ]; then echo remind; else echo none; fi
      else
        if [ "$held" = "1" ] && [ "$quiet" = "0" ]; then echo release; else echo none; fi
      fi
      ;;
    *) echo none ;;
  esac
}

monitor_state_dir() { printf '%s/state/monitor' "$(client_dir "$1")"; }

# state_read DIR CHECK -> sets PREV_SEV PREV_SINCE PREV_LAST PREV_NOTIFIED PREV_HELD (defaults for a new check)
state_read() {
  local f="$1/$2.state"
  PREV_SEV="ok" PREV_SINCE=0 PREV_LAST=0 PREV_NOTIFIED=0 PREV_HELD=0
  [ -r "$f" ] || return 0
  PREV_SEV="$(sed -n 's/^sev=//p' "$f" | head -n1)"
  PREV_SINCE="$(sed -n 's/^since=//p' "$f" | head -n1)"
  PREV_LAST="$(sed -n 's/^last_sent=//p' "$f" | head -n1)"
  PREV_NOTIFIED="$(sed -n 's/^notified=//p' "$f" | head -n1)"
  PREV_HELD="$(sed -n 's/^held=//p' "$f" | head -n1)"
  PREV_SEV="${PREV_SEV:-ok}" PREV_SINCE="${PREV_SINCE:-0}" PREV_LAST="${PREV_LAST:-0}" PREV_NOTIFIED="${PREV_NOTIFIED:-0}" PREV_HELD="${PREV_HELD:-0}"
}

# state_write DIR CHECK SEV SINCE LAST_SENT NOTIFIED HELD (check names are [a-z0-9_-] only)
state_write() {
  local dir="$1" check="$2"
  [[ "$check" =~ ^[a-z0-9_-]+$ ]] || return 1
  mkdir -p "$dir"
  printf 'sev=%s\nsince=%s\nlast_sent=%s\nnotified=%s\nheld=%s\n' "$3" "$4" "$5" "$6" "$7" >"$dir/$check.state"
}

# state_checks DIR -> names of all checks that have a state file
state_checks() { find "$1" -maxdepth 1 -name '*.state' -printf '%f\n' 2>/dev/null | sed 's/\.state$//' | sort; }
