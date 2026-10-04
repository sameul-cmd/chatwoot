#!/usr/bin/env bash
# Smoke tests used by upgrades (staging rehearsal and production). Prints a PASS/FAIL table, returns non-zero on any FAIL.
# Builds on post_deploy_checks (login, health, widget script, websocket, background job + email) and adds data and
# round-trip checks. Needs checks.sh, deploy.sh, restore.sh, chatwoot_api.sh, health.sh sourced first.
# shellcheck shell=bash

# smoke_round_trip ID -> a customer message through a temporary API inbox creates a conversation; everything it
# created is deleted again so a live client is not polluted. Prints "ok" or a short failure reason.
smoke_round_trip() {
  local id="$1" account inbox_json inbox_id ident contact src conv conv_id msgs cid_contact
  cw_use_stack "$id" || { echo "no API token"; return 1; }
  account="$(cw_request GET /api/v1/profile 2>/dev/null | jq -r '.accounts[0].id // empty')"
  [ -n "$account" ] || { echo "API did not answer"; return 1; }
  inbox_json="$(cw_request POST "/api/v1/accounts/${account}/inboxes" -H 'Content-Type: application/json' \
    -d '{"name":"opskit-smoke (temporary)","channel":{"type":"api"}}' 2>/dev/null)" || { echo "could not create the temporary inbox"; return 1; }
  inbox_id="$(printf '%s' "$inbox_json" | jq -r .id)"
  ident="$(printf '%s' "$inbox_json" | jq -r .inbox_identifier)"
  contact="$(cw_request POST "/public/api/v1/inboxes/${ident}/contacts" -H 'Content-Type: application/json' -d '{"name":"opskit smoke"}' 2>/dev/null)" || contact=""
  src="$(printf '%s' "$contact" | jq -r '.source_id // empty')"
  cid_contact="$(printf '%s' "$contact" | jq -r '.id // empty')"
  conv_id=""
  msgs=0
  if [ -n "$src" ]; then
    conv="$(cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations" -H 'Content-Type: application/json' -d '{}' 2>/dev/null || true)"
    conv_id="$(printf '%s' "$conv" | jq -r '.id // empty')"
    if [ -n "$conv_id" ]; then
      cw_request POST "/public/api/v1/inboxes/${ident}/contacts/${src}/conversations/${conv_id}/messages" -H 'Content-Type: application/json' \
        -d '{"content":"opskit smoke test"}' >/dev/null 2>&1 || true
      msgs="$(cw_request GET "/api/v1/accounts/${account}/conversations/${conv_id}/messages" 2>/dev/null | jq -r '[.payload[]? | select(.message_type == 0)] | length' 2>/dev/null || echo 0)"
    fi
  fi
  # clean up everything created (best effort: failures here do not fail the test)
  [ -z "$conv_id" ] || cw_request DELETE "/api/v1/accounts/${account}/conversations/${conv_id}" >/dev/null 2>&1 || true
  [ -z "$cid_contact" ] || cw_request DELETE "/api/v1/accounts/${account}/contacts/${cid_contact}" >/dev/null 2>&1 || true
  cw_request DELETE "/api/v1/accounts/${account}/inboxes/${inbox_id}" >/dev/null 2>&1 || true
  if [ "${msgs:-0}" -ge 1 ]; then echo ok; else echo "customer message did not create a conversation"; return 1; fi
}

# smoke_run ID LABEL BACKUP_DIR [--strict] -> LABEL is staging|production|rollback (used for failure injection)
# --strict: conversation count and newest id must EQUAL the backup (after a rollback); otherwise they must not shrink.
smoke_run() {
  local id="$1" label="$2" bdir="$3" strict=0 want_c want_m got_c got_m att rt
  [ "${4:-}" = "--strict" ] && strict=1
  post_deploy_checks "$id" || true   # prints the header + first rows and sets _CHECK_FAILS

  want_c="$(jq -r .conversations "$bdir/manifest.json")"
  want_m="$(jq -r .latest_conversation_id "$bdir/manifest.json")"
  got_c="$(_psql_sid "$id" 'SELECT count(*) FROM conversations')"
  got_m="$(_psql_sid "$id" 'SELECT coalesce(max(id),0) FROM conversations')"
  if { [ "$strict" -eq 1 ] && [ "$got_c" = "$want_c" ] && [ "$got_m" = "$want_m" ]; } ||
    { [ "$strict" -eq 0 ] && [ "${got_c:-0}" -ge "$want_c" ] && [ "${got_m:-0}" -ge "$want_m" ]; }; then
    _check "data intact (conversations)" PASS "${got_c} conversations, newest #${got_m} (backup: ${want_c}/#${want_m})"
  else
    _check "data intact (conversations)" FAIL "expected ${want_c}/#${want_m}, got ${got_c:-?}/#${got_m:-?}"
  fi

  att="$(verify_attachment_checksum "$id" "$bdir")"
  case "$att" in
    pass*) _check "attachment opens + checksum" PASS "${att#pass}" ;;
    fail*) _check "attachment opens + checksum" FAIL "${att#fail}" ;;
    *) _check "attachment opens + checksum" WARN "$att" ;;
  esac

  if rt="$(smoke_round_trip "$id")"; then _check "widget/API message round trip" PASS "conversation created and removed"; else _check "widget/API message round trip" FAIL "$rt"; fi

  local bot
  bot="$(check_aibot "$id" | cut -d'|' -f2)"
  if [ "$bot" = "ok" ]; then _check "bot health page" PASS "answers"; else _check "bot health page" FAIL "does not answer"; fi
  _check "bot answers a test question" WARN "skipped (bot not built yet, Phase 8)"

  if [ "${OPSKIT_UPGRADE_FAIL_SMOKE:-}" = "$label" ]; then
    _check "injected failure (test)" FAIL "OPSKIT_UPGRADE_FAIL_SMOKE=${label}"
  fi
  [ "$_CHECK_FAILS" -eq 0 ]
}
