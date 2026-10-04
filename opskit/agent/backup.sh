#!/usr/bin/env bash
# One backup of one client stack (SPEC 8). Standalone: runs ON the host, needs docker, age, flock, sha256sum, tar.
# Result: <out>/<id>/<UTC timestamp>/{db.dump, storage.tar.gz, escrow.tar.age, manifest.json}
# Written into .partial-<ts> and renamed only when every file is non-empty and the dump is readable.
# The manifest holds counts/ids/checksums only - never message text.
#
# Usage: backup.sh --id ID --compose-file FILE --out DIR --recipient AGE_PUBKEY \
#                  --escrow-dir DIR --escrow-file NAME [--escrow-file NAME ...] [--tag TAG] [--no-storage]
# Exit: 0 ok, 75 another backup is running, 1 failure.
set -euo pipefail

ID="" COMPOSE_FILE="" OUT="" RECIPIENT="" ESCROW_DIR="" TAG="unknown" NO_STORAGE=0
ESCROW_FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    --compose-file) COMPOSE_FILE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --recipient) RECIPIENT="$2"; shift 2 ;;
    --escrow-dir) ESCROW_DIR="$2"; shift 2 ;;
    --escrow-file) ESCROW_FILES+=("$2"); shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --no-storage) NO_STORAGE=1; shift ;;
    -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
for v in ID COMPOSE_FILE OUT RECIPIENT ESCROW_DIR; do
  [ -n "${!v}" ] || { echo "missing --$(echo "$v" | tr '[:upper:]_' '[:lower:]-')" >&2; exit 2; }
done
[ "${#ESCROW_FILES[@]}" -gt 0 ] || { echo "missing --escrow-file" >&2; exit 2; }
[[ "$ID" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "invalid id" >&2; exit 2; }
[[ "$RECIPIENT" =~ ^age1[a-z0-9]+$ ]] || { echo "invalid age public key" >&2; exit 2; }

log() { printf '%s [backup %s] %s\n' "$(date -u +%H:%M:%S)" "$ID" "$*" >&2; }
dc() { docker compose -p "$ID" -f "$COMPOSE_FILE" --project-directory "$(dirname "$COMPOSE_FILE")" "$@"; }

BASE="$OUT/$ID"
mkdir -p "$BASE"
chmod 700 "$BASE"
exec 9>"$BASE/.lock"
flock -n 9 || { log "another backup is already running"; exit 75; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
PARTIAL="$BASE/.partial-$TS"
DEST="$BASE/$TS"
cleanup() { [ -d "$PARTIAL" ] && rm -rf "$PARTIAL"; return 0; }
trap cleanup EXIT
(umask 077 && mkdir -p "$PARTIAL")

log "database dump"
dc exec -T postgres pg_dump -U postgres -Fc chatwoot >"$PARTIAL/db.dump"

if [ "$NO_STORAGE" -eq 0 ]; then
  log "uploads"
  dc exec -T rails tar czf - -C /app/storage . >"$PARTIAL/storage.tar.gz"
fi

log "secrets escrow (encrypted)"
tar -C "$ESCROW_DIR" -cf - "${ESCROW_FILES[@]}" | age -r "$RECIPIENT" -o "$PARTIAL/escrow.tar.age"

q() { dc exec -T postgres psql -U postgres -d chatwoot -tA -c "$1" 2>/dev/null | tr -d '\r' | head -n1; }
CONV_COUNT="$(q 'SELECT count(*) FROM conversations')"
CONV_MAX="$(q 'SELECT coalesce(max(id),0) FROM conversations')"
ATT_COUNT="$(q 'SELECT count(*) FROM active_storage_attachments')"
SAMPLE="$(q "SELECT key||'|'||checksum||'|'||byte_size FROM active_storage_blobs ORDER BY id DESC LIMIT 1")"

# integrity: every file non-empty, and the dump must be readable by pg_restore
for f in db.dump escrow.tar.age; do
  [ -s "$PARTIAL/$f" ] || { log "FAILED: $f is empty"; exit 1; }
done
if [ "$NO_STORAGE" -eq 0 ]; then
  [ -s "$PARTIAL/storage.tar.gz" ] || { log "FAILED: storage.tar.gz is empty"; exit 1; }
fi
dc exec -T postgres pg_restore -l <"$PARTIAL/db.dump" >/dev/null 2>&1 || { log "FAILED: db.dump is not a readable archive"; exit 1; }

files_json=""
for f in "$PARTIAL"/*; do
  name="$(basename "$f")"
  files_json+="${files_json:+,}\"$name\":{\"bytes\":$(stat -c %s "$f"),\"sha256\":\"$(sha256sum "$f" | cut -d' ' -f1)\"}"
done
sample_json="null"
if [ -n "$SAMPLE" ]; then
  IFS='|' read -r s_key s_sum s_size <<<"$SAMPLE"
  sample_json="{\"key\":\"$s_key\",\"checksum\":\"$s_sum\",\"byte_size\":${s_size:-0}}"
fi
printf '{"client_id":"%s","timestamp":"%s","chatwoot_tag":"%s","storage_included":%s,"conversations":%s,"latest_conversation_id":%s,"attachments":%s,"sample_blob":%s,"files":{%s}}\n' \
  "$ID" "$TS" "$TAG" "$([ "$NO_STORAGE" -eq 0 ] && echo true || echo false)" "${CONV_COUNT:-0}" "${CONV_MAX:-0}" "${ATT_COUNT:-0}" "$sample_json" "$files_json" \
  >"$PARTIAL/manifest.json"

mv "$PARTIAL" "$DEST"
trap - EXIT
log "done: $DEST"
printf '%s\n' "$DEST"
