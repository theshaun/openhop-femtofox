#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
elif [[ -f "${SCRIPT_DIR}/../config.env" ]]; then
    source "${SCRIPT_DIR}/../config.env"
fi

SWAP_FILE="/var/swap.img"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-256}"
SWAPPINESS="${SWAPPINESS:-10}"

echo "[setup-swap] Configuring ${SWAP_SIZE_MB}MB swap..."

if [[ -f "${SWAP_FILE}" ]]; then
    swapoff "${SWAP_FILE}" 2>/dev/null || true
    rm -f "${SWAP_FILE}"
fi

fallocate -l "${SWAP_SIZE_MB}M" "${SWAP_FILE}"
chmod 600 "${SWAP_FILE}"
mkswap "${SWAP_FILE}"

echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab

echo "vm.swappiness=${SWAPPINESS}" > /etc/sysctl.d/99-swap.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-swap.conf

echo "[setup-swap] Swap configured: ${SWAP_SIZE_MB}MB, swappiness=${SWAPPINESS}"
echo "[setup-swap] Swap will be activated on first boot by openhop-first-boot.service"
