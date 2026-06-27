#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE_NAME="openhop-armbian-builder"
IMAGE_TAG="latest"
CONTAINER_NAME="openhop-build-$(date +%Y%m%d-%H%M%S)"

source config.env

BUILD_REVISION="${BUILD_REVISION:-1}"
BUILD_NUMBER="$(date +%Y.%m).${BUILD_REVISION}"
OUTPUT_NAME="${OUTPUT_NAME:-openHop_Repeater_FemtoFox}"
FINAL_IMAGE="${OUTPUT_NAME}_${BUILD_NUMBER}"

echo "============================================"
echo " Docker Build: Luckfox Pico Mini Armbian"
echo " Build: ${FINAL_IMAGE}"
echo "============================================"
echo ""

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found. Install Docker Desktop or Docker Engine."
    echo "  WSL2: https://docs.docker.com/desktop/wsl/"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "ERROR: Docker daemon not running. Start Docker and try again."
    exit 1
fi

echo "[1/4] Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

OUTPUT_DIR="${SCRIPT_DIR}/output"
mkdir -p "${OUTPUT_DIR}"

BUILD_VOL="openhop-armbian-build"
CCACHE_VOL="openhop-armbian-ccache"

echo ""
echo "[2/4] Running build inside container..."
echo "  Board:    ${ARMBIAN_BOARD}"
echo "  Branch:   ${ARMBIAN_BRANCH}"
echo "  Release:  ${ARMBIAN_RELEASE}"
echo "  Output:   ${OUTPUT_DIR}"
echo "  Build volume: ${BUILD_VOL} (WSL2 native ext4)"
echo ""

docker run --rm \
    --name "${CONTAINER_NAME}" \
    --privileged \
    -v "${SCRIPT_DIR}:/workspace:rw" \
    -v "${BUILD_VOL}:/armbian-build:rw" \
    -v "${OUTPUT_DIR}:/output:rw" \
    -v "${CCACHE_VOL}:/root/.ccache:rw" \
    -e ARMBIAN_TAG="${ARMBIAN_TAG}" \
    -e ARMBIAN_BOARD="${ARMBIAN_BOARD}" \
    -e ARMBIAN_BRANCH="${ARMBIAN_BRANCH}" \
    -e ARMBIAN_RELEASE="${ARMBIAN_RELEASE}" \
    -e HOSTNAME="${HOSTNAME}" \
    -e TIMEZONE="${TIMEZONE}" \
    -e LUCKFOX_PASSWORD="${LUCKFOX_PASSWORD}" \
    -e LUCKFOX_SSH_KEY="${LUCKFOX_SSH_KEY:-}" \
    -e OPENHOP_REPO="${OPENHOP_REPO}" \
    -e OPENHOP_BRANCH="${OPENHOP_BRANCH}" \
    -e SWAP_SIZE_MB="${SWAP_SIZE_MB}" \
    -e SWAPPINESS="${SWAPPINESS}" \
    -e BUILD_REVISION="${BUILD_REVISION}" \
    -e OUTPUT_NAME="${OUTPUT_NAME}" \
    -e FINAL_IMAGE="${FINAL_IMAGE}" \
    -e TERM=xterm-256color \
    -e COLUMNS=160 \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "[3/4] Renaming output to ${FINAL_IMAGE}..."
for f in "${OUTPUT_DIR}/"Armbian*.img; do
    [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img"
done
for f in "${OUTPUT_DIR}/"Armbian*.img.xz; do
    [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img.xz"
done
for f in "${OUTPUT_DIR}/"Armbian_*.img.xz; do
    [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img.xz"
done
(cd "${OUTPUT_DIR}" && sha256sum ${FINAL_IMAGE}*.img* > "${FINAL_IMAGE}.sha" 2>/dev/null || true)

echo ""
echo "[4/4] Done!"
echo ""
echo "============================================"
echo " BUILD OUTPUT"
echo "============================================"
echo ""
ls -lh "${OUTPUT_DIR}/" 2>/dev/null || echo "No output files found"
echo ""
echo "Flash to SD card:"
echo "  sudo dd if=${OUTPUT_DIR}/${FINAL_IMAGE}.img of=/dev/sdX bs=4M status=progress"
echo ""
echo "Default login: luckfox / ${LUCKFOX_PASSWORD}"
echo "Dashboard:     http://<device-ip>:8000"
