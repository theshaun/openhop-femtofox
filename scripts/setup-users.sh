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

# Set root's password explicitly at build time. Armbian's first-login
# script (/usr/lib/armbian/armbian-firstlogin) only applies
# PRESET_ROOT_PASSWORD AFTER the user has already authenticated once,
# so without this line the actual build-time root password is whatever
# Armbian ships with (e.g. 1234) — not LUCKFOX_PASSWORD. That mismatch
# locks users out of the first SSH session before first-login can run.
echo "root:${LUCKFOX_PASSWORD:-changeme}" | chpasswd

if id "repeater" &>/dev/null; then
    echo "[setup-users] repeater user already exists, updating..."
    usermod -aG spi,gpio,dialout repeater
else
    adduser --disabled-password --disabled-login --gecos "openHop Repeater Service" --home /opt/openhop_repeater --shell /usr/sbin/nologin repeater
    usermod -aG spi,gpio,dialout repeater
    echo "[setup-users] Created repeater service user"
fi

mkdir -p /opt/openhop_repeater
chown repeater:repeater /opt/openhop_repeater

echo "[setup-users] User setup complete"
echo "  root - enabled for first boot (password='${LUCKFOX_PASSWORD}')"
echo "  repeater - service account, no interactive login"
