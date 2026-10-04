#!/usr/bin/env bats

setup() {
  export OPSKIT_ROOT="$BATS_TEST_DIRNAME/.."
  . "$OPSKIT_ROOT/lib/log.sh"
  . "$OPSKIT_ROOT/lib/health.sh"
}

@test "higher-is-worse thresholds: exact boundaries" {
  [ "$(sev_high_bad 84 85 95)" = "ok" ]
  [ "$(sev_high_bad 85 85 95)" = "warn" ]
  [ "$(sev_high_bad 94 85 95)" = "warn" ]
  [ "$(sev_high_bad 95 85 95)" = "critical" ]
  [ "$(sev_high_bad 299 300 900)" = "ok" ]
  [ "$(sev_high_bad 300 300 900)" = "warn" ]
  [ "$(sev_high_bad 900 300 900)" = "critical" ]
}

@test "lower-is-worse thresholds: certificate days and free memory" {
  [ "$(sev_low_bad 15 14 3)" = "ok" ]
  [ "$(sev_low_bad 14 14 3)" = "warn" ]
  [ "$(sev_low_bad 4 14 3)" = "warn" ]
  [ "$(sev_low_bad 3 14 3)" = "critical" ]
  [ "$(sev_low_bad -1 14 3)" = "critical" ]
  [ "$(sev_low_bad 11 10 5)" = "ok" ]
  [ "$(sev_low_bad 5 10 5)" = "critical" ]
}

@test "oldest waiting job age" {
  [ "$(printf '' | oldest_job_age 1000)" = "0" ]
  [ "$(printf '990.5\n700.2\n995\n' | oldest_job_age 1000)" = "299" ]
  [ "$(printf '1000\n' | oldest_job_age 1000)" = "0" ]
}

@test "certificate days left" {
  now="$(date -u -d '2026-12-01 00:00:00 UTC' +%s)"
  [ "$(cert_days_left 'notAfter=Dec 15 00:00:00 2026 GMT' "$now")" = "14" ]
  [ "$(cert_days_left 'notAfter=Nov 30 00:00:00 2026 GMT' "$now")" = "-1" ]
  run cert_days_left 'garbage' "$now"
  [ "$status" -ne 0 ]
}
