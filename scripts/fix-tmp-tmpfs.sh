#!/usr/bin/env bash
# fix-tmp-tmpfs.sh — patch deployed Femtofoxes to not use zram-backed /tmp (Armbian's default)
#
# Usage:
#   sudo bash fix-tmp-tmpfs.sh              # apply
#   sudo bash fix-tmp-tmpfs.sh --check      # report status only, no changes
#   sudo bash fix-tmp-tmpfs.sh --rollback   # undo (best-effort)

set -euo pipefail

log()  { printf '[fix-tmp-tmpfs] %s\n' "$*"; }
warn() { printf '[fix-tmp-tmpfs] WARNING: %s\n' "$*" >&2; }
die()  { printf '[fix-tmp-tmpfs] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "must be root (try: sudo bash $0)"

ACTION="apply"
case "${1:-}" in
    --rollback) ACTION="rollback" ;;
    --check)    ACTION="check" ;;
    "")         ;;
    *)  die "unknown arg: $1 (expected: --rollback | --check)" ;;
esac

FSTAB="/etc/fstab"
ZRAM_CFG="/etc/default/armbian-zram-config"
ZRAM_SVC="armbian-zram-config.service"

fstab_has_tmpfs_tmp() {
    grep -qE '^[^#].*[[:space:]]/tmp[[:space:]].*tmpfs' "$FSTAB" 2>/dev/null
}

tmp_is_ram_backed() {
    local src fstype
    src="$(findmnt -rn -o SOURCE /tmp 2>/dev/null || echo "")"
    fstype="$(findmnt -rn -o FSTYPE /tmp 2>/dev/null || echo "")"
    [[ "$fstype" == "tmpfs" ]] && return 0
    [[ "$src" =~ ^/dev/zram[0-9]+$ ]] && return 0
    return 1
}

tmp_mount_exists()   { systemctl cat tmp.mount >/dev/null 2>&1; }
tmp_mount_masked()   { [[ "$(systemctl is-enabled tmp.mount 2>&1)" == "masked" ]]; }
tmp_mount_enabled()  { local s; s="$(systemctl is-enabled tmp.mount 2>&1 || true)"; [[ "$s" == "enabled" || "$s" == "static" ]]; }

zram_svc_exists()    { systemctl cat "$ZRAM_SVC" >/dev/null 2>&1; }
zram_svc_masked()    { [[ "$(systemctl is-enabled "$ZRAM_SVC" 2>&1)" == "masked" ]]; }

zram_cfg_disabled() {
    [[ -f "$ZRAM_CFG" ]] && grep -qE '^ENABLED=false\b' "$ZRAM_CFG"
}

# --- CHECK ------------------------------------------------------------------

if [[ "$ACTION" == "check" ]]; then
    log "status check:"
    if fstab_has_tmpfs_tmp; then
        log "  [ ] $FSTAB still has tmpfs /tmp line  (should be stripped)"
    else
        log "  [x] $FSTAB has no tmpfs /tmp line"
    fi
    if tmp_mount_exists; then
        if tmp_mount_masked; then
            log "  [x] tmp.mount is masked"
        elif tmp_mount_enabled; then
            log "  [ ] tmp.mount exists and is enabled  (should be masked)"
        else
            log "  [ ] tmp.mount exists, state: $(systemctl is-enabled tmp.mount 2>&1)"
        fi
    else
        log "  [x] no tmp.mount unit on this system"
    fi
    if [[ -f "$ZRAM_CFG" ]]; then
        if zram_cfg_disabled; then
            log "  [x] $ZRAM_CFG has ENABLED=false"
        else
            log "  [ ] $ZRAM_CFG has ENABLED=$(grep -E '^ENABLED=' "$ZRAM_CFG" | cut -d= -f2 | head -1)  (should be false)"
        fi
    elif zram_svc_exists; then
        if zram_svc_masked; then
            log "  [x] $ZRAM_SVC is masked (no config file present)"
        else
            log "  [ ] $ZRAM_SVC exists, state: $(systemctl is-enabled "$ZRAM_SVC" 2>&1)  (config absent — should mask)"
        fi
    else
        log "  [x] no $ZRAM_SVC and no $ZRAM_CFG on this system"
    fi
    if tmp_is_ram_backed; then
        free_mb=$(( $(stat -f -c '%a' /tmp 2>/dev/null || echo 0) * $(stat -f -c '%s' /tmp 2>/dev/null || echo 0) / 1024 / 1024 ))
        src="$(findmnt -rn -o SOURCE /tmp 2>/dev/null)"
        log "  [ ] /tmp is currently RAM-backed  (${free_mb} MB free, source=${src})"
    else
        avail=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}')
        src="$(findmnt -rn -o SOURCE /tmp 2>/dev/null)"
        log "  [x] /tmp is SD-backed (${avail} available on ${src})"
    fi
    exit 0
fi

# --- ROLLBACK ---------------------------------------------------------------

if [[ "$ACTION" == "rollback" ]]; then
    log "rolling back changes (best-effort)"
    latest_bak=$(ls -1t "${FSTAB}".bak.* "${FSTAB}".orig.tmpfs-tmp 2>/dev/null | head -1 || true)
    if [[ -n "$latest_bak" ]]; then
        cp -a "$latest_bak" "$FSTAB"
        log "restored $FSTAB from $latest_bak"
    else
        warn "no $FSTAB backup found — leaving as-is"
    fi
    if [[ -f "${ZRAM_CFG}.bak" ]]; then
        cp -a "${ZRAM_CFG}.bak" "$ZRAM_CFG"
        log "restored $ZRAM_CFG from ${ZRAM_CFG}.bak"
    else
        latest_zram_bak=$(ls -1t "${ZRAM_CFG}".bak.* 2>/dev/null | head -1 || true)
        if [[ -n "$latest_zram_bak" ]]; then
            cp -a "$latest_zram_bak" "$ZRAM_CFG"
            log "restored $ZRAM_CFG from $latest_zram_bak"
        fi
    fi
    tmp_mount_masked && systemctl unmask tmp.mount && log "unmasked tmp.mount"
    zram_svc_masked  && systemctl unmask "$ZRAM_SVC" && log "unmasked $ZRAM_SVC"
    if ! tmp_is_ram_backed; then
        log "/tmp is currently SD-backed — reboot to restore RAM-backed /tmp"
    else
        log "/tmp is already RAM-backed"
    fi
    log "rollback complete (reboot recommended to fully apply)"
    exit 0
fi

# --- APPLY ------------------------------------------------------------------

log "applying /tmp RAM-backed OTA fix"

# 1. /etc/fstab
if fstab_has_tmpfs_tmp; then
    cp -a "$FSTAB" "${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
    sed -i '/^[^#].*[[:space:]]\/tmp[[:space:]].*tmpfs/d' "$FSTAB"
    log "stripped tmpfs /tmp from $FSTAB"
else
    log "$FSTAB already has no tmpfs /tmp line"
fi

# 2. tmp.mount — mask so systemd can't auto-mount /tmp as tmpfs
if tmp_mount_exists && ! tmp_mount_masked; then
    systemctl mask tmp.mount
    log "masked tmp.mount"
elif tmp_mount_masked; then
    log "tmp.mount already masked"
else
    log "no tmp.mount unit on this system"
fi

# 3. armbian-zram-config — preferred disable path is the config file
#    (survives package upgrades, idiomatically correct). Fall back to
#    masking the service if the config file is absent.
if [[ -f "$ZRAM_CFG" ]]; then
    if zram_cfg_disabled; then
        log "$ZRAM_CFG already has ENABLED=false"
    else
        cp -a "$ZRAM_CFG" "${ZRAM_CFG}.bak.$(date +%Y%m%d_%H%M%S)"
        sed -i 's/^ENABLED=.*/ENABLED=false/' "$ZRAM_CFG"
        log "set ENABLED=false in $ZRAM_CFG (backup at ${ZRAM_CFG}.bak.*)"
    fi
elif zram_svc_exists && ! zram_svc_masked; then
    systemctl mask "$ZRAM_SVC"
    log "masked $ZRAM_SVC (no config file present)"
elif zram_svc_masked; then
    log "$ZRAM_SVC already masked"
else
    log "no $ZRAM_SVC and no $ZRAM_CFG on this system"
fi

# 4. Try live umount. /tmp may be busy (systemd PrivateTmp bind-mounts,
#    open files in /tmp, etc.) — restart repeater to release, retry once.
systemctl daemon-reload
if tmp_is_ram_backed; then
    if umount /tmp 2>/dev/null; then
        log "unmounted RAM-backed /tmp — /tmp is now SD-backed"
        log "  free space: $(df -h /tmp | awk 'NR==2 {print $4 " available"}')"
    else
        if systemctl cat openhop-repeater.service >/dev/null 2>&1; then
            log "/tmp busy — restarting openhop-repeater.service to release PrivateTmp bind"
            systemctl restart openhop-repeater.service 2>/dev/null || true
            sleep 2
            if umount /tmp 2>/dev/null; then
                log "unmounted RAM-backed /tmp after service restart"
                log "  free space: $(df -h /tmp | awk 'NR==2 {print $4 " available"}')"
            else
                warn "could not unmount /tmp live (still busy) — REBOOT to apply"
                warn "  fstab + tmp.mount mask + zram config are all persisted"
                warn "  OTA will work after reboot"
            fi
        else
            warn "could not unmount /tmp live (busy) — REBOOT to apply"
            warn "  fstab + tmp.mount mask + zram config are all persisted"
            warn "  OTA will work after reboot"
        fi
    fi
else
    log "/tmp is already not RAM-backed"
fi

# 5. Restart the repeater so its PrivateTmp bind-mount picks up the new
#    SD-backed /tmp.
if systemctl cat openhop-repeater.service >/dev/null 2>&1; then
    if systemctl is-active --quiet openhop-repeater.service; then
        systemctl restart openhop-repeater.service
        log "restarted openhop-repeater.service"
    else
        log "openhop-repeater.service not currently running"
    fi
fi

# --- summary ----------------------------------------------------------------
log ""
log "done."
log ""
log "verify with:"
log "  sudo bash $0 --check"
log "  df -h /tmp"
log "  findmnt /tmp                  # SOURCE should be /dev/mmcblk*p1, FSTYPE ext4"
log "  systemctl is-enabled tmp.mount                       # should print 'masked'"
log "  grep '^ENABLED=' /etc/default/armbian-zram-config   # should print 'ENABLED=false'"
log ""
log "if OTA still fails after this, capture the real error with:"
log "  sudo journalctl -u openhop-repeater -b --no-pager | tail -200"
log "and look for 'No space left on device' or 'ENOSPC'."
log ""
log "rollback:"
log "  sudo bash $0 --rollback"
