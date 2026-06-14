#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
elif [[ -f "${SCRIPT_DIR}/../config.env" ]]; then
    source "${SCRIPT_DIR}/../config.env"
fi

PYMC_REPO="${PYMC_REPO:-https://github.com/pyMC-dev/pyMC_Repeater.git}"
PYMC_BRANCH="${PYMC_BRANCH:-develop}"
INSTALL_DIR="/opt/pymc_repeater"
VENV_DIR="${INSTALL_DIR}/venv"

echo "[install-pymc] Installing pyMC_Repeater..."
echo "  Repo:   ${PYMC_REPO}"
echo "  Branch: ${PYMC_BRANCH}"
echo "  Target: ${INSTALL_DIR}"

apt-get update

apt-get install -y \
    python3 python3-dev python3-venv python3-pip \
    git libgpiod2 libgpiod-dev spi-tools \
    build-essential swig libffi-dev \
    python3-rrdtool librrd-dev

if ! command -v python3 &>/dev/null; then
    echo "[install-pymc] ERROR: python3 not found after install"
    exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "[install-pymc] Python version: ${PY_VERSION}"

if [[ -d "${INSTALL_DIR}/pyMC_Repeater" ]]; then
    echo "[install-pymc] Updating existing checkout..."
    cd "${INSTALL_DIR}/pyMC_Repeater"
    git fetch --all
    git checkout "${PYMC_BRANCH}"
    git reset --hard "origin/${PYMC_BRANCH}"
else
    echo "[install-pymc] Cloning repository..."
    git clone --depth 1 --branch "${PYMC_BRANCH}" "${PYMC_REPO}" "${INSTALL_DIR}/pyMC_Repeater"
fi

cd "${INSTALL_DIR}"

echo "[install-pymc] Creating Python virtual environment..."
python3 -m venv "${VENV_DIR}"

echo "[install-pymc] Upgrading pip..."
"${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel 2>&1 || echo "[install-pymc] WARNING: pip upgrade failed"

echo "[install-pymc] Installing PyNaCl from wheel..."
"${VENV_DIR}/bin/pip" install --only-binary=:all: PyNaCl 2>&1 || echo "[install-pymc] WARNING: PyNaCl binary wheel not available, will build from source"

echo "[install-pymc] Installing pycryptodome from wheel..."
"${VENV_DIR}/bin/pip" install --only-binary=:all: pycryptodome 2>&1 || echo "[install-pymc] WARNING: pycryptodome binary wheel not available"

echo "[install-pymc] Installing pyyaml from wheel..."
"${VENV_DIR}/bin/pip" install --only-binary=:all: pyyaml 2>&1 || echo "[install-pymc] WARNING: pyyaml binary wheel not available"

echo "[install-pymc] Installing psutil from wheel..."
"${VENV_DIR}/bin/pip" install --only-binary=:all: psutil 2>&1 || echo "[install-pymc] WARNING: psutil binary wheel not available"

echo "[install-pymc] Installing pyMC_Repeater and remaining dependencies..."
"${VENV_DIR}/bin/pip" install "${INSTALL_DIR}/pyMC_Repeater[hardware]" 2>&1 || echo "[install-pymc] WARNING: pip install failed, will retry on first boot"

echo "[install-pymc] Pre-compiling bytecode (avoids lazy compile on slow CPU)..."
"${VENV_DIR}/bin/python" -m compileall -q "${VENV_DIR}/lib/python"*/site-packages "${INSTALL_DIR}/pyMC_Repeater" 2>/dev/null || \
    "${VENV_DIR}/bin/python" -m compileall -q "${VENV_DIR}" "${INSTALL_DIR}/pyMC_Repeater" 2>/dev/null || true

chown -R pymc:pymc "${INSTALL_DIR}"

RADIO_SETTINGS=""
if [[ -f "${SCRIPT_DIR}/radio-settings.json" ]]; then
    RADIO_SETTINGS="${SCRIPT_DIR}/radio-settings.json"
elif [[ -f "${SCRIPT_DIR}/../radio-profiles/radio-settings.json" ]]; then
    RADIO_SETTINGS="${SCRIPT_DIR}/../radio-profiles/radio-settings.json"
fi

if [[ -n "${RADIO_SETTINGS}" ]]; then
    cp "${RADIO_SETTINGS}" /etc/pymc_repeater/radio-settings.json
    chown pymc:pymc /etc/pymc_repeater/radio-settings.json
    echo "[install-pymc] Installed radio-settings.json"
fi

echo "[install-pymc] Installation complete"
echo "  Binary:  ${VENV_DIR}/bin/python -m repeater.main"
echo "  Config:  /etc/pymc_repeater/config.yaml"
echo "  Radio:   /etc/pymc_repeater/radio-settings.json"
echo "  Data:    ${INSTALL_DIR}/pyMC_Repeater"
