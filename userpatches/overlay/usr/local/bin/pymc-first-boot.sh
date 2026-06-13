#!/usr/bin/env bash
set -euo pipefail

MARKER="/etc/pymc-first-boot-done"
SWAP_FILE="/var/swap.img"

if [[ -f "${MARKER}" ]]; then
    echo "[first-boot] Already initialized, skipping."
    exit 0
fi

echo "[first-boot] Running first-boot setup..."

echo "[first-boot] Resizing root filesystem..."
if command -v resize2fs &>/dev/null; then
    ROOT_PART=$(findmnt -n -o SOURCE /)
    resize2fs "${ROOT_PART}" 2>/dev/null || echo "[first-boot] Filesystem resize skipped (may already be max)"
fi

echo "[first-boot] Activating swap..."
if [[ -f "${SWAP_FILE}" ]]; then
    swapon "${SWAP_FILE}" 2>/dev/null || true
fi

sysctl --system 2>/dev/null || true

echo "[first-boot] Regenerating SSH host keys..."
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

echo "[first-boot] Creating required directories..."
mkdir -p /var/log/pymc_repeater
mkdir -p /var/lib/pymc_repeater
mkdir -p /opt/pymc_repeater/data
chown pymc:pymc /var/log/pymc_repeater
chown pymc:pymc /var/lib/pymc_repeater
chown pymc:pymc /opt/pymc_repeater/data

echo "[first-boot] Enabling pymc-repeater service..."
systemctl enable pymc-repeater.service

date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER}"
echo "[first-boot] First boot setup complete. Marker written to ${MARKER}"
echo "[first-boot] pymc-repeater will start on next boot or run: systemctl start pymc-repeater"
