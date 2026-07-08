#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
elif [[ -f "${SCRIPT_DIR}/../config.env" ]]; then
    source "${SCRIPT_DIR}/../config.env"
fi

OPENHOP_REPO="${OPENHOP_REPO:-https://github.com/openhop-dev/openhop_repeater.git}"
OPENHOP_BRANCH="${OPENHOP_BRANCH:-main}"
INSTALL_DIR="/opt/openhop_repeater"
VENV_DIR="${INSTALL_DIR}/venv"

echo "[install-openhop] Installing openHop Repeater..."
echo "  Repo:   ${OPENHOP_REPO}"
echo "  Branch: ${OPENHOP_BRANCH}"
echo "  Target: ${INSTALL_DIR}"

apt-get update

apt-get install -y \
    python3 python3-dev python3-venv python3-pip \
    git libgpiod2 libgpiod-dev spi-tools \
    build-essential swig libffi-dev \
    python3-rrdtool librrd-dev \
    device-tree-compiler

if ! command -v python3 &>/dev/null; then
    echo "[install-openhop] ERROR: python3 not found after install"
    exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "[install-openhop] Python version: ${PY_VERSION}"

if [[ -d "${INSTALL_DIR}/openhop_repeater" ]]; then
    echo "[install-openhop] Updating existing checkout..."
    cd "${INSTALL_DIR}/openhop_repeater"
    git fetch --all --tags
    git checkout "${OPENHOP_BRANCH}"
    git reset --hard "origin/${OPENHOP_BRANCH}"
else
    echo "[install-openhop] Cloning repository..."
    git clone --branch "${OPENHOP_BRANCH}" "${OPENHOP_REPO}" "${INSTALL_DIR}/openhop_repeater"
fi

cd "${INSTALL_DIR}"
echo "[install-openhop] Creating Python virtual environment..."
python3 -m venv "${VENV_DIR}"

# PyPI has no linux_armv7l wheels for the native deps below, so pip would
# fall back to sdist and C-compile them under qemu-user-static (PyNaCl alone
# takes ~13 min). piwheels hosts prebuilt armv7l wheels, and the workflow
# prefetches them into /opt/openhop-wheels so install is a fast local copy.
PIP_NATIVE_FLAGS=()
if [[ -d "/opt/openhop-wheels" ]] && ls /opt/openhop-wheels/*.whl >/dev/null 2>&1; then
    echo "[install-openhop] Using prebuilt wheels from /opt/openhop-wheels:"
    ls -1 /opt/openhop-wheels/*.whl | sed 's/^/  /'
    PIP_NATIVE_FLAGS+=(--find-links=/opt/openhop-wheels)
fi
PIP_NATIVE_FLAGS+=(--extra-index-url=https://www.piwheels.org/simple)

echo "[install-openhop] Installing openHop Repeater and dependencies..."
PIP_DISABLE_PIP_VERSION_CHECK=1 "${VENV_DIR}/bin/pip" install --no-cache-dir \
    "${PIP_NATIVE_FLAGS[@]}" "${INSTALL_DIR}/openhop_repeater[hardware]" \
    2>&1 || echo "[install-openhop] WARNING: pip install failed, will retry on first boot"

# rrdtool: Python binding for librrd, needed by RRDToolHandler for dashboard
# metrics graphs.
echo "[install-openhop] Installing rrdtool Python binding..."
PIP_DISABLE_PIP_VERSION_CHECK=1 "${VENV_DIR}/bin/pip" install --no-cache-dir \
    "${PIP_NATIVE_FLAGS[@]}" rrdtool \
    2>&1 || echo "[install-openhop] WARNING: rrdtool install failed, dashboard graphs will be unavailable"

echo "[install-openhop] Pre-compiling optimized bytecode..."
"${VENV_DIR}/bin/python" -OO -m compileall -q "${VENV_DIR}" 2>/dev/null || \
    echo "[install-openhop] WARNING: bytecode compile incomplete, Python will compile on first import"

chown -R repeater:repeater "${INSTALL_DIR}"

RADIO_SETTINGS="${SCRIPT_DIR}/radio-settings.json"

if [[ -f "${RADIO_SETTINGS}" ]]; then
    cp "${RADIO_SETTINGS}" "${INSTALL_DIR}/openhop_repeater/radio-settings.json"
    chown repeater:repeater "${INSTALL_DIR}/openhop_repeater/radio-settings.json"
    echo "[install-openhop] Installed radio-settings.json -> ${INSTALL_DIR}/openhop_repeater/radio-settings.json"
fi

if [[ -f /etc/openhop_repeater/config.yaml ]]; then
    chown repeater:repeater /etc/openhop_repeater/config.yaml
    chmod 640 /etc/openhop_repeater/config.yaml
    echo "[install-openhop] Apply default config.yaml"
fi

# Merges SPI0 overlay into the board DTB so the SPI framework
# drives CS0 via cs-gpios instead of the driver bit-banging it because RightUp wouldn't shut up about trying it.
# I am pretty sure the guy never sleeps either, too busy thinking about all the bit-banging
DTB=$(find /boot/dtb-* -name "rv1103g-luckfox-pico-mini.dtb" 2>/dev/null | head -1)

if [[ -f "$DTB" ]]; then
    echo "[install-openhop] Applying SPI0 hardware-CS DTB overlay..."

    # Skip if already patched, which it shouldn't be lol? but who knows, amirite
    if dtc -I dtb -O dts "$DTB" 2>/dev/null | grep -q "cs-gpios"; then
        echo "[install-openhop]   DTB already patched (cs-gpios present) — skipping"
    elif ! command -v dtc &>/dev/null; then
        echo "[install-openhop]   WARNING: dtc not available — skipping DTB overlay"
    else
        cp "$DTB" "${DTB}.orig"
        TMP_DTS="$(mktemp --suffix=.dts)"

        dtc -I dtb -O dts "$DTB" > "$TMP_DTS" 2>/dev/null
        # and then I sed, hey lets muddle up the DTB with a sed, because why not!
        # it's not like this is a production system or anything, just a little hobby project for some bit-banging fun, right? RightUp would be proud.
        sed -i $'s|pinctrl-0 = <0x48 0x49 0x4a 0x4b>;|pinctrl-0 = <0x48 0x49 0x4a>;\\n\t\tcs-gpios = <0x36 0x10 0x00>;|' "$TMP_DTS"
        sed -i $'s|fbtft@0 {|fbtft@0 {\\n\t\t\tstatus = "disabled";|' "$TMP_DTS"

        dtc -I dts -O dtb "$TMP_DTS" > "${DTB}.new" 2>/dev/null
        rm -f "$TMP_DTS"

        VERIFY_CS=$(dtc -I dtb -O dts "${DTB}.new" 2>/dev/null | grep -c "cs-gpios")

        if [[ "${VERIFY_CS:-0}" -gt 0 ]]; then
            mv "${DTB}.new" "$DTB"
            echo "[install-openhop]   DTB patched: cs-gpios active, backup at ${DTB}.orig"
        else
            echo "[install-openhop]   WARNING: DTB patch failed — restoring original"
            rm -f "${DTB}.new"
            cp "${DTB}.orig" "$DTB"
        fi
    fi
elif [[ ! -f "$DTB" ]]; then
    echo "[install-openhop]   DTB not found ($DTB) — skipping overlay"
fi

echo "[install-openhop] Installation complete"
echo "  Binary:  ${VENV_DIR}/bin/python -m repeater.main"
echo "  Config:  /etc/openhop_repeater/config.yaml"
echo "  Radio:   ${INSTALL_DIR}/openhop_repeater/radio-settings.json"
echo "  Data:    ${INSTALL_DIR}/openhop_repeater"
