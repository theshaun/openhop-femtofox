#!/usr/bin/env bash
set -euo pipefail

MARKER="/etc/pymc-first-boot-done"
SWAP_FILE="/var/swap.img"

if [[ -f "${MARKER}" ]]; then
    echo "[first-boot] Already initialized, skipping."
    exit 0
fi

derive_stable_mac() {
    local INTERFACES=/etc/network/interfaces

    # Bail out if a stable MAC is already configured.
    if grep -Eq '^[[:space:]]*hwaddress[[:space:]]+ether' "$INTERFACES" 2>/dev/null; then
        echo "[first-boot] Stable MAC already present in ${INTERFACES}, skipping."
        return 0
    fi

    # Pull the CPU serial (Rockchip exposes a 16-hex-char value on the
    # Luckfox Pico). Fall back to /proc/cmdline on kernels that don't
    # expose it via cpuinfo.
    local serial=""
    serial=$(awk '/^Serial[[:space:]]*:/ {print $3; exit}' /proc/cpuinfo 2>/dev/null)
    if [[ -z "$serial" ]]; then
        serial=$(grep -oE '(serialno|chipid|sid)=[0-9a-fA-F]+' /proc/cmdline 2>/dev/null \
                 | head -n1 | cut -d= -f2)
    fi
    if [[ -z "$serial" ]]; then
        echo "[first-boot] No CPU serial available; skipping MAC derivation."
        return 0
    fi

    # Derive a locally-administered MAC (a2:... prefix) from the serial.
    # sha256 gives a uniform distribution; first 10 hex chars = 5 bytes.
    local hash mac
    hash=$(printf '%s' "$serial" | sha256sum | cut -c1-10)
    mac="a2:${hash:0:2}:${hash:2:2}:${hash:4:2}:${hash:6:2}:${hash:8:2}"

    # Validate before writing.
    if ! [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
        echo "[first-boot] Derived MAC '${mac}' is malformed; skipping."
        return 0
    fi

    echo "[first-boot] Setting eth0 MAC to ${mac} (derived from CPU serial)."

    # Insert `hwaddress ether` directly under the `iface eth0 inet dhcp`
    # stanza so ifupdown picks it up. If that stanza is missing, append a
    # complete eth0 block.
    if grep -q '^iface eth0 inet dhcp' "$INTERFACES"; then
        sed -i "/^iface eth0 inet dhcp/a\\    hwaddress ether ${mac}" "$INTERFACES"
    else
        printf '\nauto eth0\niface eth0 inet dhcp\n    hwaddress ether %s\n' "$mac" >> "$INTERFACES"
    fi

    echo "[first-boot] MAC written to ${INTERFACES}; reboot to apply."
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

echo "[first-boot] Configuring stable eth0 MAC address..."
derive_stable_mac || echo "[first-boot] MAC derivation skipped (non-fatal)"

echo "[first-boot] Enabling pymc-repeater service..."
systemctl enable pymc-repeater.service

# Write the marker BEFORE starting pymc-repeater, because the service
# unit has ConditionPathExists=/etc/pymc-first-boot-done. Without the
# marker in place the start call below is a no-op.
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER}"
echo "[first-boot] First boot setup complete. Marker written to ${MARKER}"

echo "[first-boot] Starting pymc-repeater service..."
systemctl start pymc-repeater.service
echo "[first-boot] pymc-repeater started."
