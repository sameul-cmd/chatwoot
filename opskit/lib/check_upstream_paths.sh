#!/usr/bin/env bash
# List files changed vs the pinned upstream tag that are NOT in our allowed paths (SPEC 3.1 / Phase 1 accept).
# Exit 0 when only our paths changed (or the pinned tag is not available locally -> skipped with exit 3).
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Pin = tag (preferred) or the commit SHA recorded next to it (forks may not carry the tag).
TAG="$(sed -n 's/^| Pinned release tag | \(v[0-9.]*\) |$/\1/p' "$ROOT/docs/UPSTREAM_CHANGES.md")"
SHA="$(sed -n 's/^| Tag SHA | \([0-9a-f]\{7,40\}\).*$/\1/p' "$ROOT/docs/UPSTREAM_CHANGES.md")"
PIN=""
for cand in "${1:-}" "$TAG" "$SHA"; do
  [ -n "$cand" ] || continue
  if git -C "$ROOT" rev-parse -q --verify "${cand}^{commit}" >/dev/null; then
    PIN="$cand"
    break
  fi
done
[ -n "$PIN" ] || {
  echo "pinned release (tag '${TAG}' / sha '${SHA}') not available locally; skipping" >&2
  exit 3
}

ALLOWED='^(opskit/|aibot/|docs/|explore/|\.claude/|\.kilo/|\.kilocode/|\.cursor/|\.clinerules/|\.roo/|GEMINI\.md$|\.github/copilot-instructions\.md$|README-START-HERE\.md$|\.github/workflows/opskit-[^/]+\.yml$)'
bad=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # an upstream file may differ only if the owner approved the patch and it is in the ledger (docs/UPSTREAM_CHANGES.md)
  grep -qF "\`${f}\`" "$ROOT/docs/UPSTREAM_CHANGES.md" || bad+="${f}"$'\n'
done < <(git -C "$ROOT" diff --name-only "${PIN}" HEAD | grep -Ev "$ALLOWED" || true)
if [ -n "$bad" ]; then
  echo "files outside our paths changed vs ${PIN}:" >&2
  echo "$bad" >&2
  exit 1
fi
