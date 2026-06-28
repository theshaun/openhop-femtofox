#!/usr/bin/env bash
set -euo pipefail

MARKER="/etc/openhop-first-boot-done"
SWAP_FILE="/var/swap.img"

if [[ -f "${MARKER}" ]]; then
    echo "[first-boot] Already initialized, skipping."
    exit 0
fi

derive_stable_mac() {
    local INTERFACES=/etc/network/interfaces
    local SYS_MAC="/sys/class/net/eth0/address"

    # Bail out if a stable MAC is already configured.
    if grep -Eq '^[[:space:]]*hwaddress[[:space:]]+ether' "$INTERFACES" 2>/dev/null; then
        echo "[first-boot] Stable MAC already present in ${INTERFACES}, skipping."
        return 0
    fi

    # Grab the MAC the kernel randomly assigned to eth0 on this boot.
    # The Rockchip driver calls eth_random_addr() at probe time (very
    # early boot), so the interface already has a MAC by the time
    # userspace runs. We pin that random MAC so it stays stable across
    # reboots instead of regenerating every boot.
    local mac=""
    if [[ -r "$SYS_MAC" ]]; then
        mac=$(cat "$SYS_MAC" 2>/dev/null | tr -d '[:space:]')
    else
        echo "[first-boot] eth0 not found (${SYS_MAC} unreadable); skipping MAC pin."
        return 0
    fi

    # Validate before writing.
    if ! [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
        echo "[first-boot] Read MAC '${mac}' is malformed; skipping."
        return 0
    fi

    echo "[first-boot] Pinning eth0 MAC to ${mac} (kernel-assigned random)."

    # Insert `hwaddress ether` directly under the `iface eth0 inet dhcp`
    # stanza so ifupdown re-applies it on every subsequent boot.
    if grep -q '^iface eth0 inet dhcp' "$INTERFACES"; then
        sed -i "/^iface eth0 inet dhcp/a\\    hwaddress ether ${mac}" "$INTERFACES"
    else
        printf '\nauto eth0\niface eth0 inet dhcp\n    hwaddress ether %s\n' "$mac" >> "$INTERFACES"
    fi

    echo "[first-boot] MAC written to ${INTERFACES}; stable across reboots."
}

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

echo "[first-boot] Regenerating SSH host keys atomically..."
(
    set -e
    STAGING="$(mktemp -d /etc/ssh/.hostkeys-staging.XXXXXX)"
    trap 'rm -rf "${STAGING}"' EXIT

    for kt in rsa ecdsa ed25519; do
        ssh-keygen -q -t "${kt}" -N "" -f "${STAGING}/ssh_host_${kt}_key"
    done

    # Atomic rename into place — sshd (gated by Before=ssh.service) never
    # observes a missing or half-written key file.
    for kf in "${STAGING}"/ssh_host_*_key; do
        base="$(basename "${kf}")"
        mv -f "${kf}"     "/etc/ssh/${base}"
        mv -f "${kf}.pub" "/etc/ssh/${base}.pub"
    done
)

echo "[first-boot] Creating required directories..."
mkdir -p /var/log/openhop_repeater
mkdir -p /var/lib/openhop_repeater
mkdir -p /opt/openhop_repeater/data
chown repeater:repeater /var/log/openhop_repeater
chown repeater:repeater /var/lib/openhop_repeater
chown repeater:repeater /opt/openhop_repeater/data

echo "[first-boot] Configuring stable eth0 MAC address..."
derive_stable_mac || echo "[first-boot] MAC derivation skipped (non-fatal)"

echo "[first-boot] Enabling openhop-repeater service..."
systemctl enable openhop-repeater.service

# Write the marker BEFORE starting openhop-repeater, because the service
# unit has ConditionPathExists=/etc/openhop-first-boot-done. Without the
# marker in place the start call below is a no-op.
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER}"
echo "[first-boot] First boot setup complete. Marker written to ${MARKER}"

echo "[first-boot] Starting openhop-repeater service..."
systemctl start openhop-repeater.service
echo "[first-boot] openhop-repeater started."
