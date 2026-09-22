#!/bin/bash
# boot-watchdog.sh — C1 boot rollback watchdog (OS-016: tryboot-aware)
#
# Runs early on every boot (before basic.target, after local-fs.target).
# Reads /boot/boot_state and:
#   - If confirmed=true  → nothing to do, slot is healthy.
#   - If confirmed=false → verify boot health, then decrement
#     tries_remaining. If tries_remaining reaches 0 (or boot health
#     fails outright) → restore the confirmed slot in autoboot.txt
#     and reboot.
#
# tryboot model (OS-016): the firmware already rolled back by itself if the
# new slot hung/panicked before userspace (tryboot flag is consumed by the
# single tryboot boot; the next boot uses boot_prefix). This watchdog covers
# the remaining window: the new slot boots userspace but /boot state or
# kernel/DTB integrity is broken.
#
# Health verification (mirrors swupdate-bootcheck.sh):
#   1. /proc/cmdline root= must match the PARTUUID in
#      /boot/<slot>/cmdline.txt (kernel + cmdline actually from the slot).
#   2. kernel_2712.img and bcm2712-rpi-5-b.dtb exist in /boot/<slot>/ and
#      have plausible sizes (kernel > 1 MB, DTB < 10 MB). A failed OTA can
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
#   slot=<a|b>            slot this boot came from
#   prev_slot=<a|b>       confirmed slot to roll back to
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
prev_slot=""
tries_remaining=""
confirmed=""
while IFS='=' read -r key value; do
    case "${key}" in
        slot)            slot="${value}" ;;
        prev_slot)       prev_slot="${value}" ;;
        tries_remaining) tries_remaining="${value}" ;;
        confirmed)       confirmed="${value}" ;;
        \#*|"")          : ;;
    esac
done < "${BOOT_STATE}"

if [[ "${confirmed:-false}" == "true" ]]; then
    exit 0
fi

SLOT_DIR="/boot/$(echo "${slot:-a}" | tr 'a-z' 'A-Z')"
PREV_DIR="/boot/$(echo "${prev_slot:-b}" | tr 'a-z' 'A-Z')"

# ---------------------------------------------------------------------------
# Atomic write helper (task 46): write temp → fsync → rename.
# ---------------------------------------------------------------------------
atomic_write() {
    local dst="$1" tmp="${1}.tmp"
    cat > "${tmp}"
    sync -f "${tmp}" 2>/dev/null || sync
    mv -f "${tmp}" "${dst}"
}

# Roll back to the confirmed slot: autoboot.txt keeps boot_prefix=<PREV>/
# and drops any stale boot_prefix_try. If boot_state has no usable prev_slot,
# fall back to the legacy .prev-file restore (pre-tryboot layout).
rollback() {
    echo "[boot-watchdog] $* — rolling back" | tee /dev/console
    logger -t boot-watchdog "$* — rolling back"
    mount -o remount,rw /boot
    if [[ -d "${PREV_DIR}" && -f "${PREV_DIR}/cmdline.txt" ]]; then
        printf '[all]\nboot_prefix=%s/\n' "$(basename "${PREV_DIR}")" \
            | atomic_write /boot/autoboot.txt
        # Keep the root-level fallback mirror consistent with the confirmed slot.
        cp -f "${PREV_DIR}/cmdline.txt" /boot/cmdline.txt
        for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
            [[ -f "${PREV_DIR}/${f}" ]] && cp -f "${PREV_DIR}/${f}" "/boot/${f}" || true
        done
    else
        # Legacy layout fallback (slot dirs never created).
        [[ -f /boot/cmdline.txt.prev ]] && cp /boot/cmdline.txt.prev /boot/cmdline.txt || true
        for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
            [[ -f "/boot/${f}.prev" ]] && cp "/boot/${f}.prev" "/boot/${f}" || true
        done
        [[ -f /boot/autoboot.txt ]] && rm -f /boot/autoboot.txt
    fi
    rm -f "${BOOT_STATE}" /boot/cmdline.txt.prev \
          /boot/kernel_2712.img.prev /boot/bcm2712-rpi-5-b.dtb.prev
    mount -o remount,ro /boot
    reboot
}

if [[ ! -d "${SLOT_DIR}" ]]; then
    rollback "slot dir ${SLOT_DIR} missing after tryboot"
fi

# ── Health check 1: kernel command line matches expected slot ──────────────
CURRENT_ROOT=$(cat /proc/cmdline | tr ' ' '\n' | grep '^root=PARTUUID=' | head -1)
EXPECTED_ROOT=$(grep '^root=' "${SLOT_DIR}/cmdline.txt" 2>/dev/null | tr -d '\n')

if [[ -z "${EXPECTED_ROOT}" ]]; then
    logger -t boot-watchdog "WARNING: cannot determine expected root PARTUUID for ${SLOT_DIR}"
elif [[ "${CURRENT_ROOT}" != "${EXPECTED_ROOT}" ]]; then
    rollback "cmdline mismatch (expected='${EXPECTED_ROOT}' got='${CURRENT_ROOT}')"
fi

# ── Health check 2: kernel + DTB integrity (per-file bounds, issue #26) ───
# Each file has a different reasonable size range — kernel is multi-MB,
# DTB is tens-of-KB.  The previous shared `if SIZE < 1MB || SIZE > 10MB`
# always tripped on a 60 KB DTB and caused spurious rollbacks.
INTEGRITY_OK=true
for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
    if [[ ! -f "${SLOT_DIR}/${f}" ]]; then
        INTEGRITY_OK=false
        logger -t boot-watchdog "${f} missing in ${SLOT_DIR} after boot"
        break
    fi
    SIZE=$(stat -c%s "${SLOT_DIR}/${f}" 2>/dev/null || echo 0)
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