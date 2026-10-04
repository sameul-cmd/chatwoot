#!/usr/bin/env bash
# Prepare a fresh Ubuntu 24.04 host for one Chatwoot client stack. Standalone: runs ON the host as root.
# Idempotent. Usage: bootstrap.sh [--dry-run]
# Installs Docker + compose, ufw (22/80/443), unattended-upgrades, 2 GB swap; REPORTS (never changes) SSH settings.
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

step() { printf '[bootstrap] %s\n' "$*"; }
run() {
  if [ "$DRY" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

if [ "$DRY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "must run as root" >&2
  exit 1
fi

step "base packages"
run apt-get update -qq
run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl ufw unattended-upgrades

step "docker"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  step "docker + compose already installed"
else
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2
  run systemctl enable --now docker
fi

step "firewall (ufw: 22, 80, 443)"
run ufw allow 22/tcp
run ufw allow 80/tcp
run ufw allow 443/tcp
run ufw --force enable

step "unattended upgrades"
run systemctl enable --now unattended-upgrades

step "swap (2 GB if none)"
if [ "$DRY" -eq 1 ] || [ -z "$(swapon --show --noheadings 2>/dev/null)" ]; then
  if [ ! -f /swapfile ]; then
    run fallocate -l 2G /swapfile
    run chmod 600 /swapfile
    run mkswap /swapfile
  fi
  run swapon /swapfile
  if [ "$DRY" -eq 1 ] || ! grep -q '^/swapfile ' /etc/fstab; then
    run sh -c "echo '/swapfile none swap sw 0 0' >> /etc/fstab"
  fi
else
  step "swap already active"
fi

step "SSH hardening check (report only)"
if [ -r /etc/ssh/sshd_config ]; then
  for key in PasswordAuthentication PermitRootLogin; do
    value="$(sshd -T 2>/dev/null | awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '$1==k{print $2}')"
    printf '[bootstrap] sshd %s = %s\n' "$key" "${value:-unknown}"
  done
  echo "[bootstrap] recommended: PasswordAuthentication no, PermitRootLogin prohibit-password/no (not changed automatically)"
fi
step "done"
