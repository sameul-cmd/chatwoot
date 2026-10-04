#!/usr/bin/env bash
# age encryption helpers for the secrets escrow (SPEC 3.6). Needs lib/log.sh. Never handles a private key
# except the identity FILE path the owner passes to decrypt.
# shellcheck shell=bash

# age_recipient -> prints the owner's public key (env OPSKIT_AGE_RECIPIENT or keys/owner.age.pub). Fails if none.
age_recipient() {
  local rec="${OPSKIT_AGE_RECIPIENT:-}" file="${OPSKIT_KEYS_DIR:-${OPSKIT_ROOT:-.}/keys}/owner.age.pub"
  if [ -z "$rec" ] && [ -r "$file" ]; then
    rec="$(grep -E '^age1[a-z0-9]+$' "$file" | head -n1 || true)"
  fi
  if [[ ! "$rec" =~ ^age1[a-z0-9]+$ ]]; then
    log_error "no age public key: set OPSKIT_AGE_RECIPIENT or put your public key (age1...) in opskit/keys/owner.age.pub"
    return 1
  fi
  printf '%s' "$rec"
}

# encrypt_file IN OUT -> OUT is age-encrypted to the owner key (mode 600). IN is not removed.
encrypt_file() {
  local in="$1" out="$2" rec
  rec="$(age_recipient)" || return 1
  [ -f "$in" ] || {
    log_error "encrypt: input not found"
    return 1
  }
  (umask 077 && age -r "$rec" -o "$out" "$in") || {
    rm -f "$out"
    log_error "encrypt failed"
    return 1
  }
}

# decrypt_file IN OUT IDENTITY_FILE -> plaintext OUT (mode 600).
decrypt_file() {
  local in="$1" out="$2" identity="$3"
  [ -r "$identity" ] || {
    log_error "identity file not readable: $identity"
    return 1
  }
  (umask 077 && age -d -i "$identity" -o "$out" "$in") 2>/dev/null || {
    rm -f "$out"
    log_error "decrypt failed (wrong key or damaged file)"
    return 1
  }
}
