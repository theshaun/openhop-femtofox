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
    if grep -Eq '^[[:space:]]*hwaddress[[:space:]]+ether' "$INTERFACES" 2>/dev/null; then
        echo "[first-boot] Stable MAC already present in ${INTERFACES}, skipping."
        return 0
    fi

    local hex desc="" d pat s seed=""

    for pat in '*efuse*' '*otp*' '*sid*' '*chipid*' '*uid*'; do
        for d in /sys/bus/nvmem/devices/${pat}/nvmem; do
            [[ -r "$d" ]] || continue
            hex=$(od -An -v -tx1 "$d" 2>/dev/null | tr -d ' \n') || continue
            if [[ -n "$hex" && "$hex" == *[1-9a-fA-F]* ]]; then
                desc="$d"; seed="$hex"; break 2
            fi
        done
    done

    if [[ -z "$seed" ]]; then
        for d in /sys/bus/nvmem/devices/*/nvmem; do
            [[ -r "$d" ]] || continue
            hex=$(od -An -v -tx1 "$d" 2>/dev/null | tr -d ' \n') || continue
            if [[ -n "$hex" && "$hex" == *[1-9a-fA-F]* ]]; then
                desc="$d"; seed="$hex"; break
            fi
        done
    fi

    if [[ -z "$seed" ]]; then
        s=$(awk '/^Serial[[:space:]]*:/ {print $3; exit}' /proc/cpuinfo 2>/dev/null)
        if [[ -n "$s" && "$s" == *[1-9a-fA-F]* ]]; then
            desc="/proc/cpuinfo Serial"; seed="$s"
        fi
    fi

    if [[ -z "$seed" ]]; then
        s=$(grep -oE '(serialno|chipid|sid)=[0-9a-fA-F]+' /proc/cmdline 2>/dev/null | head -n1 | cut -d= -f2)
        if [[ -n "$s" ]]; then
            desc="/proc/cmdline"; seed="$s"
        fi
    fi

    local persisted=/var/lib/pymc_repeater/mac-seed
    if [[ -z "$seed" ]]; then
        if [[ -s "$persisted" ]]; then
            seed=$(cat "$persisted")
            desc="persisted random seed"
        else
            seed=$(head -c 16 /dev/urandom | od -An -v -tx1 | tr -d ' \n')
            printf '%s\n' "$seed" > "$persisted"
            desc="new persisted random seed"
        fi
    fi

    local hash
    hash=$(printf '%s' "$seed" | sha256sum | cut -c1-10)
    local mac="a2:${hash:0:2}:${hash:2:2}:${hash:4:2}:${hash:6:2}:${hash:8:2}"

    echo "[first-boot] Stable eth0 MAC derived from ${desc}: ${mac}"

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

date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER}"
echo "[first-boot] First boot setup complete. Marker written to ${MARKER}"
echo "[first-boot] pymc-repeater will start on next boot or run: systemctl start pymc-repeater"
