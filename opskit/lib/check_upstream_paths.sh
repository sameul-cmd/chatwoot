#!/usr/bin/env bash
# List files changed vs the pinned upstream tag that are NOT in our allowed paths (SPEC 3.1 / Phase 1 accept).
# Exit 0 when only our paths changed (or the pinned tag is not available locally -> skipped with exit 3).
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="${1:-$(sed -n 's/^| Pinned release tag | \(v[0-9.]*\) |$/\1/p' "$ROOT/docs/UPSTREAM_CHANGES.md")}"

git -C "$ROOT" rev-parse -q --verify "refs/tags/${PIN}^{commit}" >/dev/null || {
  echo "pinned tag '${PIN}' not available locally; skipping" >&2
  exit 3
}

ALLOWED='^(opskit/|aibot/|docs/|explore/|\.claude/|README-START-HERE\.md$|\.github/workflows/opskit-[^/]+\.yml$)'
bad="$(git -C "$ROOT" diff --name-only "${PIN}" HEAD | grep -Ev "$ALLOWED" || true)"
if [ -n "$bad" ]; then
  echo "files outside our paths changed vs ${PIN}:" >&2
  echo "$bad" >&2
  exit 1
fi
