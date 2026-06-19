#!/bin/bash
set -e

echo "============================================"
echo " customise-image.sh running in chroot"
echo " $(date)"
echo "============================================"

BUILD_SCRIPTS="/usr/local/lib/pymc-build"

if [[ -d /tmp/overlay ]]; then
    echo "Copying overlay files to rootfs..."
    cp -a /tmp/overlay/. /
    chown -R root:root /etc/sudoers.d /etc/systemd/system /etc/network /etc/udev /etc/hostname /etc/pymc_repeater /usr/local/bin /usr/local/lib 2>/dev/null || true
    chmod 440 /etc/sudoers.d/* 2>/dev/null || true
    chmod 755 /usr/local/bin/*.sh 2>/dev/null || true
fi

if [[ ! -d "${BUILD_SCRIPTS}" ]]; then
    echo "ERROR: Build scripts not found at ${BUILD_SCRIPTS}"
    exit 1
fi

cd "${BUILD_SCRIPTS}"

if [[ -f config.env ]]; then
    source config.env
    echo "Loaded config.env"
    echo "  HOSTNAME: ${HOSTNAME}"
    echo "  SWAP:     ${SWAP_SIZE_MB}MB"
fi

echo ""
echo "[1/10] Configuring hostname..."
echo "${HOSTNAME:-femtofox}" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t${HOSTNAME:-femtofox}/" /etc/hosts 2>/dev/null || true
echo "127.0.1.1\t${HOSTNAME:-femtofox}" >> /etc/hosts 2>/dev/null || true

echo ""
echo "[2/10] Setting timezone and locales..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE:-UTC}" /etc/localtime
echo "${TIMEZONE:-UTC}" > /etc/timezone

sed -i 's/^#\s*en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
sed -i 's/^#\s*en_AU\.UTF-8/en_AU.UTF-8/' /etc/locale.gen 2>/dev/null || true
sed -i 's/^#\s*en_GB\.UTF-8/en_GB.UTF-8/' /etc/locale.gen 2>/dev/null || true
grep -q "^en_AU.UTF-8" /etc/locale.gen 2>/dev/null || echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
grep -q "^en_US.UTF-8" /etc/locale.gen 2>/dev/null || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
grep -q "^en_GB.UTF-8" /etc/locale.gen 2>/dev/null || echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
setupcon --save --force 2>/dev/null || true

echo ""
echo "[3/10] Setting up user accounts..."
bash "${BUILD_SCRIPTS}/setup-users.sh"

echo "Configuring first-login flow..."
cat > /root/.not_logged_in_yet <<FIRSTLOGIN
PRESET_ROOT_PASSWORD="${LUCKFOX_PASSWORD:-changeme}"
PRESET_TIMEZONE="${TIMEZONE:-UTC}"
PRESET_LOCALE="en_US.UTF-8"
SET_LANG_BASED_ON_LOCATION=Y
FIRSTLOGIN

echo "Locking root password after first-login..."
cat > /etc/profile.d/lock-root-after-firstboot.sh <<'PROFILEEOF'
if [ -f /root/.not_logged_in_yet ]; then
    :
elif [ "$(id -u)" = "0" ]; then
    if passwd -S root 2>/dev/null | grep -q " P "; then
        echo "Locking root account..."
        passwd -l root
        usermod -s /usr/sbin/nologin root
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
        rm -f /etc/profile.d/lock-root-after-firstboot.sh
    fi
fi
PROFILEEOF

echo ""
echo "[4/10] Configuring swap..."
bash "${BUILD_SCRIPTS}/setup-swap.sh"

echo ""
echo "[5/10] Installing pyMC_Repeater..."
bash "${BUILD_SCRIPTS}/install-pymc.sh"

echo ""
echo "[6/10] Configuring network..."
ln -sf /dev/null /etc/udev/rules.d/80-net-setup-link.rules
# Mask (not just disable) the network managers we don't want. Armbian's
# runtime generators re-enable systemd-networkd every boot, and socket
# activation can still bring it up despite `disable`. Masking blocks all
# activation paths so only ifupdown (networking.service) touches eth0.
systemctl mask systemd-networkd.service 2>/dev/null || true
systemctl mask systemd-networkd.socket 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
systemctl mask NetworkManager.service 2>/dev/null || true
systemctl mask NetworkManager-dispatcher.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
# Drop Armbian's runtime netplan generator so it can't write .network files
# into /run/systemd/network/ that would otherwise match eth0 even with the
# service masked.
rm -f /lib/systemd/system-generators/*netplan* 2>/dev/null || true
rm -f /etc/systemd/network/*.network 2>/dev/null || true
apt-get install -y --no-install-recommends ifupdown isc-dhcp-client fake-hwclock systemd-timesyncd net-tools

echo "Configuring NTP time sync (no RTC on this board)..."
systemctl enable systemd-timesyncd.service 2>/dev/null || true
systemctl enable fake-hwclock.service 2>/dev/null || true
# Stop chrony/ntp if the image shipped them; timesyncd is lighter and sufficient.
systemctl disable chrony 2>/dev/null || true
systemctl disable ntp 2>/dev/null || true
# Seed fake-hwclock with the build time so the first cold boot isn't in 1970.
date -u '+%Y-%m-%d %H:%M:%S' > /etc/fake-hwclock.data 2>/dev/null || true

echo ""
echo "[7/10] Enabling services..."
systemctl daemon-reload
systemctl enable pymc-repeater.service
systemctl enable pymc-first-boot.service
systemctl disable pymc-repeater.service 2>/dev/null || true

echo ""
echo "[8/10] Pre-generating SSH host keys..."
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

echo ""
echo "[9/10] Disabling unnecessary cron jobs and services..."
rm -f /etc/cron.daily/armbian-quotes 2>/dev/null || true
rm -f /etc/cron.daily/armbian-truncate-logout 2>/dev/null || true
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl mask apt-daily.timer 2>/dev/null || true
systemctl mask apt-daily-upgrade.timer 2>/dev/null || true
# Armbian ships its own daily update timer + helper that bypasses the
# standard apt-daily path. Disable and mask both the timer and the
# oneshot service so nothing re-enables them, and neutralise the apt
# config snippet that drives APT::Periodic from the Armbian side.
systemctl disable armbian-apt-updates.timer 2>/dev/null || true
systemctl mask armbian-apt-updates.timer 2>/dev/null || true
systemctl disable armbian-apt-updates.service 2>/dev/null || true
systemctl mask armbian-apt-updates.service 2>/dev/null || true
rm -f /etc/apt/apt.conf.d/02-armbian-periodic 2>/dev/null || true
echo 'APT::Periodic::Update-Package-Lists "0";' > /etc/apt/apt.conf.d/02-armbian-periodic
echo 'APT::Periodic::Unattended-Upgrade "0";' >> /etc/apt/apt.conf.d/02-armbian-periodic

chmod -x /etc/update-motd.d/15-ap-info 2>/dev/null || true
chmod -x /etc/update-motd.d/20-ip-info 2>/dev/null || true
chmod -x /etc/update-motd.d/25-containers-info 2>/dev/null || true
chmod -x /etc/update-motd.d/35-armbian-tips 2>/dev/null || true
chmod -x /etc/update-motd.d/41-commands 2>/dev/null || true
chmod -x /etc/update-motd.d/10-armbian-header 2>/dev/null || true
chmod +x /etc/update-motd.d/10-femtofox-header 2>/dev/null || true

echo "  Remaining cron jobs:"
ls -la /etc/cron.daily/ /etc/cron.weekly/ /etc/cron.hourly/ 2>/dev/null
echo "  Remaining MOTD scripts:"
ls -la /etc/update-motd.d/ 2>/dev/null

echo ""
echo "[10/10] Final cleanup..."
apt-get autoremove -y
apt-get clean
rm -rf /var/cache/apt/archives/*
find /tmp -mindepth 1 -maxdepth 1 ! -name 'overlay' -exec rm -rf {} +
rm -rf /var/tmp/*

truncate -s 0 /var/log/syslog 2>/dev/null || true
truncate -s 0 /var/log/auth.log 2>/dev/null || true

echo "nameserver 8.8.8.8" > /etc/resolv.conf.head 2>/dev/null || true
echo "nameserver 8.8.4.4" >> /etc/resolv.conf.head 2>/dev/null || true

echo ""
echo "============================================"
echo " customise-image.sh COMPLETE"
echo "============================================"
