#!/usr/bin/env bats

setup() {
  OPSKIT="$BATS_TEST_DIRNAME/../bin/opskit"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  LIB="$BATS_TEST_DIRNAME/../lib"
}

@test "help lists commands" {
  run "$OPSKIT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor"* ]]
}

@test "unknown command exits 2 with usage" {
  run "$OPSKIT" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "doctor passes when all tools exist" {
  run "$OPSKIT" doctor
  [ "$status" -eq 0 ]
}

@test "doctor names a missing tool" {
  # PATH without docker/age/rclone etc: only core dirs, no /usr/local, so at least one tool is missing
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for t in bash git env dirname cat sed date printf; do
    p="$(command -v "$t")" && ln -sf "$p" "$BATS_TEST_TMPDIR/bin/$t"
  done
  PATH="$BATS_TEST_TMPDIR/bin" run /usr/bin/env bash "$OPSKIT" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "llm and selftest are placeholders until later phases" {
  run "$OPSKIT" llm models demo
  [ "$status" -eq 3 ]
  run "$OPSKIT" selftest
  [ "$status" -eq 3 ]
}

@test "valid client.yaml passes" {
  run "$OPSKIT" client validate "$FIX/client_valid.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid:"* ]]
}

@test "shared_accounts is rejected with V2 message" {
  run "$OPSKIT" client validate "$FIX/client_shared.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"install.mode"* ]]
  [[ "$output" == *"V2"* ]]
}

@test "invalid effort names the field" {
  run "$OPSKIT" client validate "$FIX/client_bad_effort.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bot.llm.effort"* ]]
}

@test "missing required field is named" {
  run "$OPSKIT" client validate "$FIX/client_missing_tz.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"timezone"* ]]
}

@test "bad domain fails on domain" {
  run "$OPSKIT" client validate "$FIX/client_bad_domain.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *": domain:"* ]]
}

@test "bot.yaml valid and invalid" {
  run "$OPSKIT" bot validate "$FIX/bot_valid.yaml"
  [ "$status" -eq 0 ]
  run "$OPSKIT" bot validate "$FIX/bot_bad_confidence.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"min_confidence"* ]]
}

@test "pack file valid and invalid industry" {
  run "$OPSKIT" pack validate "$FIX/pack_valid.yaml"
  [ "$status" -eq 0 ]
  run "$OPSKIT" pack validate "$FIX/pack_bad_industry.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"industry"* ]]
}

@test "validate without a file exits 2" {
  run "$OPSKIT" client validate
  [ "$status" -eq 2 ]
}

@test "mask hides secrets" {
  . "$LIB/log.sh"
  [ "$(mask 'abcdef1234567890')" = "ab***" ]
  [ "$(mask 'short')" = "***" ]
}

@test "empty secret aborts" {
  . "$LIB/log.sh"
  . "$LIB/validate.sh"
  run require_secret SECRET_KEY_BASE ""
  [ "$status" -eq 1 ]
  run require_secret SECRET_KEY_BASE "x"
  [ "$status" -eq 0 ]
}

@test "gen_secret returns 64 hex chars for 32 bytes" {
  . "$LIB/log.sh"
  . "$LIB/validate.sh"
  run gen_secret 32
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}

@test "destructive actions need --yes and typed id" {
  . "$LIB/log.sh"
  . "$LIB/confirm.sh"
  run confirm_destructive restore demo no
  [ "$status" -eq 1 ]
  OPSKIT_CONFIRM_ID=wrong run confirm_destructive restore demo yes
  [ "$status" -eq 1 ]
  OPSKIT_CONFIRM_ID=demo run confirm_destructive restore demo yes
  [ "$status" -eq 0 ]
}

@test "only our paths differ from the pinned upstream tag" {
  run "$LIB/check_upstream_paths.sh"
  if [ "$status" -eq 3 ]; then skip "pinned tag not available (shallow clone)"; fi
  [ "$status" -eq 0 ]
}

@test "reserved addons block accepted while disabled" {
  run "$OPSKIT" client validate "$FIX/client_addons_reserved.yaml"
  [ "$status" -eq 0 ]
}

@test "enabling a V2 add-on is rejected with a V2 message" {
  run "$OPSKIT" client validate "$FIX/client_addon_on.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"addons.order_capture.enabled"* ]]
  [[ "$output" == *"V2"* ]]
}

@test "custom brand mode is not available yet" {
  run "$OPSKIT" client validate "$FIX/client_brand_custom.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"brand.mode"* ]]
}
