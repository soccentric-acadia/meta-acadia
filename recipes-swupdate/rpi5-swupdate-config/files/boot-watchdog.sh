#!/bin/bash
# boot-watchdog.sh — C1 boot rollback watchdog
#
# Runs early on every boot (before basic.target, after local-fs.target).
# Reads /boot/boot_state and:
#   - If confirmed=true  → nothing to do, slot is healthy.
#   - If confirmed=false → verify boot health, then decrement
#     tries_remaining. If tries_remaining reaches 0 (or boot health
#     fails outright) → restore cmdline.txt.prev and reboot.
#
# Health verification (mirrors swupdate-bootcheck.sh so that a failure
# is caught as early as possible — at the kernel cmdline + /boot
# integrity layer, not after acadia-client has had a chance to misbehave):
#   1. /proc/cmdline root= must match the PARTUUID in /boot/cmdline.txt
#      (kernel and DTB actually loaded the new slot).
#   2. kernel_2712.img and bcm2712-rpi-5-b.dtb exist on /boot and have
#      plausible sizes (kernel > 1 MB, DTB < 10 MB). A failed OTA can
#      leave a zero-byte kernel behind, which the RPi firmware will
#      happily try to boot — we want to catch that here.
#
# On a cmdline mismatch, the script rolls back immediately (does not
# burn a try) since the new slot is provably unbootable. On a size
# check failure, the script decrements tries_remaining by 2 (faster
# path to rollback) since a partially-written kernel is a strong
# signal of an aborted OTA.
#
# /boot/boot_state format (written by post-install.sh after each OTA):
#   slot=<a|b>
#   tries_remaining=<N>
#   confirmed=<true|false>

set -euo pipefail

BOOT_STATE=/boot/boot_state

# Nothing to do if no pending update or already confirmed
if [[ ! -f "${BOOT_STATE}" ]]; then
    exit 0
fi

# Parse /boot/boot_state as key=value lines.  Do NOT `source`: /boot is
# writable (FAT32), and a `source` would execute any shell metacharacters
# an attacker wrote into the file — running arbitrary code as root.
slot=""
tries_remaining=""
confirmed=""
while IFS='=' read -r key value; do
    case "${key}" in
        slot)            slot="${value}" ;;
        tries_remaining) tries_remaining="${value}" ;;
        confirmed)       confirmed="${value}" ;;
        \#*|"")          : ;;
    esac
done < "${BOOT_STATE}"

if [[ "${confirmed:-false}" == "true" ]]; then
    exit 0
fi

rollback() {
    echo "[boot-watchdog] $* — rolling back" | tee /dev/console
    logger -t boot-watchdog "$* — rolling back"
    mount -o remount,rw /boot
    if [[ -f /boot/cmdline.txt.prev ]]; then
        cp /boot/cmdline.txt.prev /boot/cmdline.txt
    fi
    for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
        [[ -f "/boot/${f}.prev" ]] && cp "/boot/${f}.prev" "/boot/${f}" || true
    done
    rm -f "${BOOT_STATE}" /boot/cmdline.txt.prev \
          /boot/kernel_2712.img.prev /boot/bcm2712-rpi-5-b.dtb.prev
    mount -o remount,ro /boot
    reboot
}

# ── Health check 1: kernel command line matches expected slot ──────────────
CURRENT_ROOT=$(cat /proc/cmdline | tr ' ' '\n' | grep '^root=PARTUUID=' | head -1)
EXPECTED_ROOT=$(grep '^root=' /boot/cmdline.txt 2>/dev/null | tr -d '\n')

if [[ -z "${EXPECTED_ROOT}" ]]; then
    logger -t boot-watchdog "WARNING: cannot determine expected root PARTUUID"
elif [[ "${CURRENT_ROOT}" != "${EXPECTED_ROOT}" ]]; then
    rollback "cmdline mismatch (expected='${EXPECTED_ROOT}' got='${CURRENT_ROOT}')"
fi

# ── Health check 2: kernel + DTB integrity (per-file bounds, issue #26) ───
# Each file has a different reasonable size range — kernel is multi-MB,
# DTB is tens-of-KB.  The previous shared `if SIZE < 1MB || SIZE > 10MB`
# always tripped on a 60 KB DTB and caused spurious rollbacks.
INTEGRITY_OK=true
for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
    if [[ ! -f "/boot/${f}" ]]; then
        INTEGRITY_OK=false
        logger -t boot-watchdog "${f} missing after boot"
        break
    fi
    SIZE=$(stat -c%s "/boot/${f}" 2>/dev/null || echo 0)
    case "${f}" in
        kernel_2712.img)
            MIN=$((1024 * 1024))
            MAX=$((20 * 1024 * 1024))
            ;;
        *-rpi-*-b.dtb|*-rpi-*-cm*.dtb|*-rpi-*.dtb)
            MIN=$((10 * 1024))
            MAX=$((5 * 1024 * 1024))
            ;;
        *)
            MIN=1024
            MAX=$((50 * 1024 * 1024))
            ;;
    esac
    if [[ "${SIZE}" -lt "${MIN}" ]] || [[ "${SIZE}" -gt "${MAX}" ]]; then
        INTEGRITY_OK=false
        logger -t boot-watchdog \
            "${f} size ${SIZE} bytes outside [${MIN}, ${MAX}]"
        break
    fi
done

mount -o remount,rw /boot

if [[ "${INTEGRITY_OK}" != "true" ]]; then
    # Skip the normal decrement — set tries_remaining directly so the
    # next iteration of this same boot (post-reboot) trips rollback.
    sed -i "s/tries_remaining=.*/tries_remaining=0/" "${BOOT_STATE}"
    mount -o remount,ro /boot
    rollback "kernel/DTB integrity check failed"
fi

# ── Normal path: decrement tries_remaining ─────────────────────────────────
TRIES=$(( ${tries_remaining:-0} - 1 ))

if [[ "${TRIES}" -le 0 ]]; then
    # Don't bother decrementing — just rollback.
    mount -o remount,ro /boot
    rollback "tries_remaining exhausted"
else
    sed -i "s/tries_remaining=.*/tries_remaining=${TRIES}/" "${BOOT_STATE}"
    mount -o remount,ro /boot
fi
