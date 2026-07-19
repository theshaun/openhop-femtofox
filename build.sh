#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_FILE}"
    exit 1
fi

source "${CONFIG_FILE}"

BUILD_REVISION="${BUILD_REVISION:-1}"
BUILD_NUMBER="$(date +%Y.%m).${BUILD_REVISION}"
OUTPUT_NAME="${OUTPUT_NAME:-openHop_Repeater_FemtoFox}"
FINAL_IMAGE="${OUTPUT_NAME}_${BUILD_NUMBER}"

ARMBIAN_BUILD_DIR="${SCRIPT_DIR}/armbian-build"
ARMBIAN_REPO="https://github.com/armbian/build.git"

echo "============================================"
echo " Luckfox Pico Mini - Armbian + openHop Repeater"
echo " Image Builder"
echo "============================================"
echo ""

if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Detected WSL2 environment"
    if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null; then
        echo "Installing build dependencies for WSL2..."
        sudo apt-get update
        sudo apt-get install -y make gcc ccache locales dialog \
            python3 python3-dev python3-pip python3-venv \
            swig bison flex gawk wget curl unzip rsync \
            bc cpio jq yq git lsb-release
    fi
fi

if [[ ! -d "${ARMBIAN_BUILD_DIR}" ]]; then
    echo "Cloning Armbian build framework (${ARMBIAN_TAG})..."
    git clone --depth 1 --branch "${ARMBIAN_TAG}" "${ARMBIAN_REPO}" "${ARMBIAN_BUILD_DIR}"
else
    echo "Armbian build directory exists, updating..."
    cd "${ARMBIAN_BUILD_DIR}"
    git fetch --all --tags
    git checkout "${ARMBIAN_TAG}"
    cd "${SCRIPT_DIR}"
fi

echo "Injecting userpatches..."
USERPATCHES_DIR="${ARMBIAN_BUILD_DIR}/userpatches"

if [[ -d "${USERPATCHES_DIR}" && ! -L "${USERPATCHES_DIR}" ]]; then
    rm -rf "${USERPATCHES_DIR}"
fi

if [[ -L "${USERPATCHES_DIR}" ]]; then
    rm "${USERPATCHES_DIR}"
fi

ln -sf "${SCRIPT_DIR}/userpatches" "${USERPATCHES_DIR}"

echo "Copying scripts into overlay for chroot access..."
mkdir -p "${SCRIPT_DIR}/userpatches/overlay/usr/local/lib/openhop-build/"
cp "${SCRIPT_DIR}/scripts/"*.sh "${SCRIPT_DIR}/userpatches/overlay/usr/local/lib/openhop-build/"
cp "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/userpatches/overlay/usr/local/lib/openhop-build/config.env"

echo ""
echo "Starting Armbian build..."
echo "  Board:    ${ARMBIAN_BOARD}"
echo "  Branch:   ${ARMBIAN_BRANCH}"
echo "  Release:  ${ARMBIAN_RELEASE}"
echo "  Hostname: ${HOSTNAME}"
echo "  Swap:     ${SWAP_SIZE_MB}MB (swappiness=${SWAPPINESS})"
echo "  Output:   ${FINAL_IMAGE}"
echo ""

cd "${ARMBIAN_BUILD_DIR}"

./compile.sh \
    BOARD="${ARMBIAN_BOARD}" \
    BRANCH="${ARMBIAN_BRANCH}" \
    RELEASE="${ARMBIAN_RELEASE}" \
    BUILD_MINIMAL="yes" \
    BUILD_DESKTOP="no" \
    KERNEL_CONFIGURE="no" \
    KERNEL_GIT="shallow" \
    LEGACY_DEBOOTSTRAP="yes" \
    COMPRESS_OUTPUTIMAGE="sha,img"

BUILD_EXIT=$?

cd "${SCRIPT_DIR}"

if [[ ${BUILD_EXIT} -eq 0 ]]; then
    echo ""
    echo "============================================"
    echo " BUILD SUCCESSFUL"
    echo "============================================"
    echo ""

    OUTPUT_DIR="${ARMBIAN_BUILD_DIR}/output/images"
    for f in "${OUTPUT_DIR}/"Armbian*.img; do
        [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img"
    done
    for f in "${OUTPUT_DIR}/"Armbian*.img.xz; do
        [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img.xz"
    done
    (cd "${OUTPUT_DIR}" && sha256sum ${FINAL_IMAGE}*.img* > "${FINAL_IMAGE}.sha" 2>/dev/null || true)

    echo "Output images:"
    find "${OUTPUT_DIR}/" -name "${FINAL_IMAGE}*" 2>/dev/null || true
    echo ""
    echo "Flash to SD card:"
    echo "  sudo dd if=${OUTPUT_DIR}/${FINAL_IMAGE}.img of=/dev/sdX bs=4M status=progress"
    echo ""
    echo "Default logins after flashing:"
    echo "  luckfox / ${LUCKFOX_PASSWORD}  (admin with sudo)"
    echo "  root                           (disabled)"
    echo ""
    echo "openHop Repeater dashboard will be at: http://<device-ip>:8000"
else
    echo ""
    echo "BUILD FAILED with exit code ${BUILD_EXIT}"
    echo "Check the output above for errors."
    exit ${BUILD_EXIT}
fi
