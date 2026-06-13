#!/bin/bash
set -euo pipefail
WORKSPACE=/mnt/c/GIT/test_luckfox
LOG_FILE="${WORKSPACE}/logs/build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${WORKSPACE}/logs"
exec > >(tee "${LOG_FILE}") 2>&1

echo "=== Log file: ${LOG_FILE} ==="
echo "=== $(date) Build started ==="

export DEBIAN_FRONTEND=noninteractive
export PATH=$(echo "$PATH" | sed 's|:/Docker/host/bin||g')
unset ARMBIAN_RUNNING_IN_CONTAINER
BUILD_DIR=/home/shaun/pymc-build/armbian-build
OUTPUT_DIR=/home/shaun/pymc-build/output
ARMBIAN_TAG=v26.2.1

source "${WORKSPACE}/config.env"
BUILD_REVISION="${BUILD_REVISION:-1}"
BUILD_NUMBER="$(date +%Y.%m).${BUILD_REVISION}"
OUTPUT_NAME="${OUTPUT_NAME:-pyMC_Repeater_FemtoFox}"
FINAL_IMAGE="${OUTPUT_NAME}_${BUILD_NUMBER}"

echo '=== Phase 1: Install dependencies ==='
sudo apt-get update -qq 2>&1 | tail -1
sudo apt-get install -y -qq --no-install-recommends \
    autoconf automake bc bison build-essential ccache cpio curl \
    device-tree-compiler dialog flex gawk gdisk git jq kmod \
    lib32gcc-s1 libc6-dev-armhf-cross libfdt-dev libfile-fcntllock-perl \
    libfl-dev libgmp-dev libmpc-dev libncurses-dev libpython3-dev \
    libssl-dev libtool libudev-dev linux-headers-generic locales make \
    mtools parted patchutils pkg-config python3 python3-dev \
    python3-pkg-resources python3-venv rsync swig \
    u-boot-tools unzip uuid-dev wget xxd zlib1g-dev \
    gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi \
    dosfstools binfmt-support \
    psmisc uuid-runtime linux-base bsdextrautils imagemagick \
    libbison-dev libelf-dev lz4 libusb-1.0-0-dev lsof ncurses-term \
    pv arch-test udev tree expect colorized-logs zip \
    pigz pbzip2 lzop zstd fdisk aria2 axel parallel rdfind binwalk \
    libffi-dev libgnutls28-dev 2>&1 | tail -3

if ! command -v yq >/dev/null 2>&1; then
    sudo curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 \
        -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq
fi
echo '=== Phase 1 complete ==='

echo '=== Phase 2: Clone Armbian ==='
mkdir -p "${BUILD_DIR}"
if [ ! -d "${BUILD_DIR}/.git" ]; then
    git clone --depth 1 --branch "${ARMBIAN_TAG}" https://github.com/armbian/build.git "${BUILD_DIR}"
else
    cd "${BUILD_DIR}"
    git fetch --all --tags --force 2>/dev/null || true
    git checkout "${ARMBIAN_TAG}" 2>/dev/null || true
fi
echo '=== Phase 2 complete ==='

echo '=== Phase 3: Inject userpatches ==='
rm -rf "${BUILD_DIR}/userpatches" 2>/dev/null || true
mkdir -p "${BUILD_DIR}/userpatches/overlay/usr/local/lib/pymc-build/"
mkdir -p "${BUILD_DIR}/userpatches/overlay/etc/pymc_repeater"
mkdir -p "${BUILD_DIR}/userpatches/overlay/etc/systemd/system"
mkdir -p "${BUILD_DIR}/userpatches/overlay/etc/sudoers.d"
mkdir -p "${BUILD_DIR}/userpatches/overlay/usr/local/bin"

cp -r "${WORKSPACE}/userpatches/"* "${BUILD_DIR}/userpatches/" 2>/dev/null || true
cp "${WORKSPACE}/scripts/"*.sh "${BUILD_DIR}/userpatches/overlay/usr/local/lib/pymc-build/" 2>/dev/null || true
cp "${WORKSPACE}/radio-profiles/"*.json "${BUILD_DIR}/userpatches/overlay/usr/local/lib/pymc-build/" 2>/dev/null || true
cp "${WORKSPACE}/config.env" "${BUILD_DIR}/userpatches/overlay/usr/local/lib/pymc-build/config.env"
echo '=== Phase 3 complete ==='

echo '=== Phase 4: Build ==='
cd "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}"

./compile.sh \
    BOARD=luckfox-pico-mini \
    BRANCH=vendor \
    RELEASE=bookworm \
    BUILD_MINIMAL=yes \
    BUILD_DESKTOP=no \
    KERNEL_CONFIGURE=no \
    KERNEL_GIT=shallow \
    COMPRESS_OUTPUTIMAGE=sha,img

echo "=== $(date) Build finished, copying output ==="
mkdir -p "${OUTPUT_DIR}"
echo "Files in build output:"
ls -lh "${BUILD_DIR}/output/images/" 2>/dev/null || true
cp -v "${BUILD_DIR}/output/images/"*.img "${OUTPUT_DIR}/" 2>/dev/null || true
cp -v "${BUILD_DIR}/output/images/"*.img.xz "${OUTPUT_DIR}/" 2>/dev/null || true
cp -v "${BUILD_DIR}/output/images/"*.sha "${OUTPUT_DIR}/" 2>/dev/null || true

echo "=== Renaming output to ${FINAL_IMAGE} ==="
echo "Files before rename:"
ls -lh "${OUTPUT_DIR}/" 2>/dev/null || true
for f in "${OUTPUT_DIR}/"Armbian*.img; do
    [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img"
done
for f in "${OUTPUT_DIR}/"Armbian*.img.xz; do
    [ -f "$f" ] && mv -v "$f" "${OUTPUT_DIR}/${FINAL_IMAGE}.img.xz"
done
(cd "${OUTPUT_DIR}" && sha256sum "${FINAL_IMAGE}"*.img* > "${FINAL_IMAGE}.sha" 2>/dev/null || true)

echo '=== ALL DONE ==='
ls -lh "${OUTPUT_DIR}/" 2>/dev/null || true

echo '=== Copying to Windows filesystem ==='
WIN_OUTPUT=/mnt/c/GIT/test_luckfox/output
mkdir -p "${WIN_OUTPUT}"
cp -v "${OUTPUT_DIR}/"* "${WIN_OUTPUT}/" 2>/dev/null || true
echo '=== Windows copy done ==='
ls -lh "${WIN_OUTPUT}/" 2>/dev/null || true
