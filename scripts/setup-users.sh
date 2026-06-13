#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
fi

echo "[setup-users] Configuring user accounts..."

groupadd -f spi 2>/dev/null || true
groupadd -f gpio 2>/dev/null || true
groupadd -f dialout 2>/dev/null || true

if id "pymc" &>/dev/null; then
    echo "[setup-users] pymc user already exists, updating..."
    usermod -aG spi,gpio,dialout pymc
else
    adduser --disabled-password --disabled-login --gecos "pyMC Repeater Service" --home /opt/pymc_repeater --shell /usr/sbin/nologin pymc
    usermod -aG spi,gpio,dialout pymc
    echo "[setup-users] Created pymc service user"
fi

mkdir -p /opt/pymc_repeater
chown pymc:pymc /opt/pymc_repeater

echo "[setup-users] User setup complete"
echo "  root - enabled for first boot (password='${LUCKFOX_PASSWORD}')"
echo "  pymc - service account, no interactive login"
