#!/usr/bin/env bash
set -euo pipefail

echo "============================================"
echo " Docker Entrypoint: Armbian Build"
echo " $(date)"
echo "============================================"
echo ""

WORKSPACE="/workspace"
LOCAL_BUILD="/armbian-build"
ARMBIAN_REPO="https://github.com/armbian/build.git"

ARMBIAN_TAG="${ARMBIAN_TAG:-v26.2.1}"
ARMBIAN_BOARD="${ARMBIAN_BOARD:-luckfox-pico-mini}"
ARMBIAN_BRANCH="${ARMBIAN_BRANCH:-vendor}"
ARMBIAN_RELEASE="${ARMBIAN_RELEASE:-bookworm}"
BUILD_REVISION="${BUILD_REVISION:-1}"
BUILD_NUMBER="$(date +%Y.%m).${BUILD_REVISION}"
OUTPUT_NAME="${OUTPUT_NAME:-openHop_Repeater_FemtoFox}"
FINAL_IMAGE="${OUTPUT_NAME}_${BUILD_NUMBER}"

echo "Configuration:"
echo "  ARMBIAN_TAG:     ${ARMBIAN_TAG}"
echo "  ARMBIAN_BOARD:   ${ARMBIAN_BOARD}"
echo "  ARMBIAN_BRANCH:  ${ARMBIAN_BRANCH}"
echo "  ARMBIAN_RELEASE: ${ARMBIAN_RELEASE}"
echo ""

echo "Cloning Armbian build framework (${ARMBIAN_TAG}) into Docker named volume..."
echo "  Volume mount: ${LOCAL_BUILD} (native ext4 inside WSL2 VM)"
if [[ ! -d "${LOCAL_BUILD}/.git" ]]; then
    git clone --depth 1 --branch "${ARMBIAN_TAG}" "${ARMBIAN_REPO}" "${LOCAL_BUILD}"
else
    cd "${LOCAL_BUILD}"
    git fetch --all --tags --force 2>/dev/null || true
    git checkout "${ARMBIAN_TAG}" 2>/dev/null || true
fi

echo "Injecting userpatches from workspace..."
USERPATCHES_DIR="${LOCAL_BUILD}/userpatches"
rm -rf "${USERPATCHES_DIR}" 2>/dev/null || true

mkdir -p "${LOCAL_BUILD}/userpatches/overlay/usr/local/lib/openhop-build/"
mkdir -p "${LOCAL_BUILD}/userpatches/overlay/etc/openhop_repeater"
mkdir -p "${LOCAL_BUILD}/userpatches/overlay/etc/systemd/system"
mkdir -p "${LOCAL_BUILD}/userpatches/overlay/etc/sudoers.d"
mkdir -p "${LOCAL_BUILD}/userpatches/overlay/usr/local/bin"

if [[ -d "${WORKSPACE}/userpatches" ]]; then
    cp -r "${WORKSPACE}/userpatches/"* "${LOCAL_BUILD}/userpatches/" 2>/dev/null || true
    echo "  Copied userpatches overlay"
else
    echo "  WARNING: No userpatches dir found"
fi

if [[ -d "${WORKSPACE}/scripts" ]]; then
    cp "${WORKSPACE}/scripts/"*.sh "${LOCAL_BUILD}/userpatches/overlay/usr/local/lib/openhop-build/" 2>/dev/null || true
    echo "  Copied scripts"
else
    echo "  WARNING: No scripts dir found"
fi

cat > "${LOCAL_BUILD}/userpatches/overlay/usr/local/lib/openhop-build/config.env" <<EOF
HOSTNAME="${HOSTNAME:-openhop-repeater}"
TIMEZONE="${TIMEZONE:-UTC}"
LUCKFOX_PASSWORD="${LUCKFOX_PASSWORD:-changeme}"
LUCKFOX_SSH_KEY="${LUCKFOX_SSH_KEY:-}"
OPENHOP_REPO="${OPENHOP_REPO:-https://github.com/openhop-dev/openhop_repeater.git}"
OPENHOP_BRANCH="${OPENHOP_BRANCH:-main}"
SWAP_SIZE_MB=${SWAP_SIZE_MB:-256}
SWAPPINESS=${SWAPPINESS:-10}
EOF
echo "  Wrote config.env"

echo ""
echo "Starting Armbian build (all I/O in container-local storage)..."
echo ""

cd "${LOCAL_BUILD}"

./compile.sh \
    BOARD="${ARMBIAN_BOARD}" \
    BRANCH="${ARMBIAN_BRANCH}" \
    RELEASE="${ARMBIAN_RELEASE}" \
    BUILD_MINIMAL="yes" \
    BUILD_DESKTOP="no" \
    KERNEL_CONFIGURE="no" \
    KERNEL_GIT="shallow" \
    COMPRESS_OUTPUTIMAGE="sha,img"

BUILD_EXIT=$?

echo ""
if [[ ${BUILD_EXIT} -eq 0 ]]; then
    echo "BUILD SUCCEEDED"
    echo "Flushing disk caches before copy..."
    /bin/sync.real
    echo "Copying output images to /output/..."
    mkdir -p /output
    cp -v "${LOCAL_BUILD}/output/images/"*.img /output/ 2>/dev/null || true
    cp -v "${LOCAL_BUILD}/output/images/"*.img.xz /output/ 2>/dev/null || true
    cp -v "${LOCAL_BUILD}/output/images/"*.sha /output/ 2>/dev/null || true
    echo "Renaming to ${FINAL_IMAGE}..."
    for f in /output/Armbian*.img; do
        [ -f "$f" ] && mv -v "$f" "/output/${FINAL_IMAGE}.img"
    done
    for f in /output/Armbian*.img.xz; do
        [ -f "$f" ] && mv -v "$f" "/output/${FINAL_IMAGE}.img.xz"
    done
    (cd /output && sha256sum ${FINAL_IMAGE}*.img* > "${FINAL_IMAGE}.sha" 2>/dev/null || true)
    echo "Images copied:"
    ls -lh /output/ 2>/dev/null || true
else
    echo "BUILD FAILED (exit code ${BUILD_EXIT})"
    exit ${BUILD_EXIT}
fi
