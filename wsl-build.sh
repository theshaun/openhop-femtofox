#!/usr/bin/env bash
set -euo pipefail

DISTRO="${WSL_DISTRO:-Ubuntu-22.04}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WIN_SCRIPT_DIR="$(wslpath -u "${SCRIPT_DIR}" 2>/dev/null || echo "/mnt/c/GIT/test_luckfox")"

source config.env

BUILD_REVISION="${BUILD_REVISION:-1}"
BUILD_NUMBER="$(date +%Y.%m).${BUILD_REVISION}"
OUTPUT_NAME="${OUTPUT_NAME:-openHop_Repeater_FemtoFox}"
FINAL_IMAGE="${OUTPUT_NAME}_${BUILD_NUMBER}"

echo "============================================"
echo " WSL2 Native Build: Luckfox Pico Mini Armbian"
echo " Distro: ${DISTRO}"
echo " Build:   ${FINAL_IMAGE}"
echo "============================================"
echo ""

wsl -d "${DISTRO}" -- bash -c "
set -euo pipefail

WORKSPACE='${WIN_SCRIPT_DIR}'
BUILD_DIR=\$HOME/openhop-armbian-build
OUTPUT_DIR='\$WORKSPACE/output'
ARMBIAN_TAG='${ARMBIAN_TAG:-v26.2.1}'

echo '=========================================='
echo ' Phase 1: Install build dependencies'
echo '=========================================='
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    autoconf automake bc bison build-essential ccache cpio curl \
    device-tree-compiler dialog flex gawk gdisk git jq kmod \
    lib32gcc-s1 libc6-dev-armhf-cross libfdt-dev libfile-fcntllock-perl \
    libfl-dev libgmp-dev libmpc-dev libncurses-dev libpython3-dev \
    libssl-dev libtool libudev-dev linux-headers-generic locales make \
    mtools parted patchutils pkg-config python3 python3-dev \
    python3-distutils python3-pkg-resources python3-venv rsync swig \
    u-boot-tools unzip uuid-dev wget xxd zlib1g-dev \
    gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi \
    dosfstools dwarfs qemu-user-static binfmt-support \
    psmisc uuid-runtime linux-base bsdextrautils imagemagick \
    libbison-dev libelf-dev lz4 libusb-1.0-0-dev lsof ncurses-term \
    ntpsec-ntpdate pv arch-test udev tree expect colorized-logs zip \
    pigz pbzip2 lzop zstd fdisk aria2 axel parallel rdfind binwalk \
    libffi-dev libgnutls28-dev

if ! command -v yq &>/dev/null; then
    sudo curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 \
        -o /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
fi

sudo locale-gen en_US.UTF-8

echo ''
echo '=========================================='
echo ' Phase 2: Clone Armbian build framework'
echo '=========================================='
mkdir -p \"\${BUILD_DIR}\"
if [[ ! -d \"\${BUILD_DIR}/.git\" ]]; then
    git clone --depth 1 --branch \"\${ARMBIAN_TAG}\" \
        https://github.com/armbian/build.git \"\${BUILD_DIR}\"
else
    cd \"\${BUILD_DIR}\"
    git fetch --all --tags --force 2>/dev/null || true
    git checkout \"\${ARMBIAN_TAG}\" 2>/dev/null || true
fi

echo ''
echo '=========================================='
echo ' Phase 3: Inject userpatches and scripts'
echo '=========================================='
rm -rf \"\${BUILD_DIR}/userpatches\" 2>/dev/null || true

mkdir -p \"\${BUILD_DIR}/userpatches/overlay/usr/local/lib/openhop-build/\"
mkdir -p \"\${BUILD_DIR}/userpatches/overlay/etc/openhop_repeater\"
mkdir -p \"\${BUILD_DIR}/userpatches/overlay/etc/systemd/system\"
mkdir -p \"\${BUILD_DIR}/userpatches/overlay/etc/sudoers.d\"
mkdir -p \"\${BUILD_DIR}/userpatches/overlay/usr/local/bin\"

if [[ -d \"\${WORKSPACE}/userpatches\" ]]; then
    cp -r \"\${WORKSPACE}/userpatches/\"* \"\${BUILD_DIR}/userpatches/\" 2>/dev/null || true
    echo '  Copied userpatches'
fi

if [[ -d \"\${WORKSPACE}/scripts\" ]]; then
    cp \"\${WORKSPACE}/scripts/\"*.sh \"\${BUILD_DIR}/userpatches/overlay/usr/local/lib/openhop-build/\" 2>/dev/null || true
    echo '  Copied scripts'
fi

cat > \"\${BUILD_DIR}/userpatches/overlay/usr/local/lib/openhop-build/config.env\" <<'ENVEOF'
$(cat "${SCRIPT_DIR}/config.env")
ENVEOF
echo '  Wrote config.env'

echo ''
echo '=========================================='
echo ' Phase 4: Run Armbian build'
echo '=========================================='
cd \"\${BUILD_DIR}\"

mkdir -p \"\${OUTPUT_DIR}\"

./compile.sh \
    BOARD=luckfox-pico-mini \
    BRANCH=vendor \
    RELEASE=bookworm \
    BUILD_MINIMAL=yes \
    BUILD_DESKTOP=no \
    KERNEL_CONFIGURE=no \
    KERNEL_GIT=shallow \
    COMPRESS_OUTPUTIMAGE=sha,img

BUILD_EXIT=\$?

echo ''
if [[ \${BUILD_EXIT} -eq 0 ]]; then
    echo 'BUILD SUCCEEDED'
    echo 'Copying output images...'
    mkdir -p \"\${OUTPUT_DIR}\"
    cp -v \"\${BUILD_DIR}/output/images/\"*.img \"\${OUTPUT_DIR}/\" 2>/dev/null || true
    cp -v \"\${BUILD_DIR}/output/images/\"*.img.xz \"\${OUTPUT_DIR}/\" 2>/dev/null || true
    cp -v \"\${BUILD_DIR}/output/images/\"*.sha \"\${OUTPUT_DIR}/\" 2>/dev/null || true
    echo ''
    echo 'Renaming output to ${FINAL_IMAGE}...'
    for f in \"\${OUTPUT_DIR}/\"Armbian*.img; do
        [ -f \"\$f\" ] && mv -v \"\$f\" \"\${OUTPUT_DIR}/${FINAL_IMAGE}.img\"
    done
    for f in \"\${OUTPUT_DIR}/\"Armbian*.img.xz; do
        [ -f \"\$f\" ] && mv -v \"\$f\" \"\${OUTPUT_DIR}/${FINAL_IMAGE}.img.xz\"
    done
    (cd \"\${OUTPUT_DIR}\" && sha256sum \"${FINAL_IMAGE}.img\" > \"${FINAL_IMAGE}.sha\" 2>/dev/null || true)
    echo ''
    echo 'Output files:'
    ls -lh \"\${OUTPUT_DIR}/\" 2>/dev/null || true
else
    echo \"BUILD FAILED (exit code \${BUILD_EXIT})\"
    exit \${BUILD_EXIT}
fi
"
