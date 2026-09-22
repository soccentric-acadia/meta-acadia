#!/bin/bash
# SWUpdate post-install script — included in every .swu package
#
# OS-016: slot activation uses the RPi firmware **tryboot** mechanism instead
# of permanently rewriting /boot/cmdline.txt. The old approach left the
# device unrecoverable if the new slot hung/panicked before userspace (the
# custom /boot/boot_state file is not read by the RPi firmware).
#
# tryboot layout on /boot (FAT, P1):
#   /boot/A/  — slot A boot files: cmdline.txt, kernel_2712.img, DTB, config.txt
#   /boot/B/  — slot B boot files
#   /boot/autoboot.txt —
#       boot_prefix=<confirmed-slot>/   (used on every normal boot)
#       boot_prefix_try=<new-slot>/     (used for the single tryboot boot)
#   /boot/boot_state      — userspace health-check state (unchanged format,
#                           plus prev_slot for rollback)
#   /boot/config.txt, kernel_2712.img, bcm2712-rpi-5-b.dtb, cmdline.txt
#                         — root copies, kept as the mirror of the CONFIRMED
#                           slot so the firmware still boots if autoboot.txt
#                           is unreadable.
#
# Activation flow:
#   post-install.sh  → prepares /boot/<NEW>/, writes autoboot.txt with
#                      boot_prefix_try=<NEW>/
#   reboot (tryboot) → firmware boots the new slot ONCE via boot_prefix_try.
#                      A kernel panic / hang consumes the tryboot flag and the
#                      NEXT boot falls back to boot_prefix (the old slot) with
#                      zero userspace involvement.
#   healthy boot     → swupdate-bootcheck confirms: boot_prefix=<NEW>/ is
#                      made permanent (and root-level files mirrored).

set -euo pipefail

TARGET_SLOT=$(cat /run/swupdate-target-slot)
TARGET_DEV=$(cat  /run/swupdate-target-dev)
PREV_SLOT=$(cat /run/swupdate-prev-slot 2>/dev/null || true)

echo "[swupdate post-install] activating slot ${TARGET_SLOT} (${TARGET_DEV}) via tryboot"

# Resolve the PARTUUID of the target partition
TARGET_PARTUUID=$(blkid -s PARTUUID -o value "${TARGET_DEV}")
if [[ -z "${TARGET_PARTUUID}" ]]; then
    echo "[swupdate post-install] ERROR: cannot read PARTUUID from ${TARGET_DEV}" >&2
    exit 1
fi

mount -o remount,rw /boot

# ---------------------------------------------------------------------------
# Atomic write helper: write temp → fsync → rename (task 46).
# ---------------------------------------------------------------------------
atomic_write() {
    local dst="$1" tmp="${1}.tmp"
    cat > "${tmp}"
    sync -f "${tmp}" 2>/dev/null || sync
    mv -f "${tmp}" "${dst}"
}

# ---------------------------------------------------------------------------
# One-time migration: create per-slot boot dirs from the legacy root layout.
# ---------------------------------------------------------------------------
SLOT_DIR_A=/boot/A
SLOT_DIR_B=/boot/B
NEW_DIR="/boot/$(echo "${TARGET_SLOT}" | tr 'a-z' 'A-Z')"

if [[ ! -d "${SLOT_DIR_A}" || ! -d "${SLOT_DIR_B}" ]]; then
    echo "[swupdate post-install] migrating legacy /boot layout to per-slot dirs"
    mkdir -p "${SLOT_DIR_A}" "${SLOT_DIR_B}"
    # Legacy (pre-tryboot) files live at /boot root and describe the
    # currently-confirmed slot; duplicate them into BOTH dirs so either slot
    # can boot before the first OTA payload lands.
    for dir in "${SLOT_DIR_A}" "${SLOT_DIR_B}"; do
        cp -f /boot/cmdline.txt  "${dir}/cmdline.txt"
        cp -f /boot/config.txt   "${dir}/config.txt"
        for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
            [[ -f "/boot/${f}" ]] && cp -f "/boot/${f}" "${dir}/${f}" || true
        done
    done
fi

# Derive the previous (confirmed) slot if not provided by pre-install.
if [[ -z "${PREV_SLOT}" ]]; then
    ACTIVE_DEV=$(findmnt -n -o SOURCE /)
    case "$(lsblk -n -o LABEL "${ACTIVE_DEV}" 2>/dev/null | head -1 | tr -d ' ')" in
        rootfs-a) PREV_SLOT=a ;;
        rootfs-b) PREV_SLOT=b ;;
        *)        PREV_SLOT="${TARGET_SLOT}" ;; # unknown — fall back to new slot
    esac
fi
PREV_DIR="/boot/$(echo "${PREV_SLOT}" | tr 'a-z' 'A-Z')"

# Keep per-slot config.txt in sync with the image's root config.txt.
for dir in "${SLOT_DIR_A}" "${SLOT_DIR_B}"; do
    [[ -f /boot/config.txt ]] && cp -f /boot/config.txt "${dir}/config.txt"
done

# ---------------------------------------------------------------------------
# Install the freshly written payload files into the NEW slot dir.
# The swu writes @@KERNEL@@/@@DTB@@ to /boot root (sw-description); move them
# into /boot/<NEW>/, then restore the root mirror from the PREV slot so the
# firmware's no-prefix fallback keeps booting the confirmed slot.
# ---------------------------------------------------------------------------
for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
    if [[ -f "/boot/${f}" ]]; then
        mv -f "/boot/${f}" "${NEW_DIR}/${f}"
        if [[ -f "${PREV_DIR}/${f}" ]]; then
            cp -f "${PREV_DIR}/${f}" "/boot/${f}"
        fi
    fi
done

# Switch root= to the new slot inside the NEW slot's cmdline (atomic).
sed "s|root=PARTUUID=[a-fA-F0-9-]*|root=PARTUUID=${TARGET_PARTUUID}|" \
    "${NEW_DIR}/cmdline.txt" > "${NEW_DIR}/cmdline.txt.tmp"
sync -f "${NEW_DIR}/cmdline.txt.tmp" 2>/dev/null || sync
mv -f "${NEW_DIR}/cmdline.txt.tmp" "${NEW_DIR}/cmdline.txt"

# ---------------------------------------------------------------------------
# Arm tryboot: autoboot.txt keeps the confirmed slot as boot_prefix and points
# boot_prefix_try at the new slot. The firmware uses the try prefix only for
# the single boot triggered by `reboot "0 tryboot"`; a failed boot falls back
# to boot_prefix automatically (firmware-level rollback, no userspace needed).
# ---------------------------------------------------------------------------
printf '[all]\nboot_prefix=%s/\nboot_prefix_try=%s/\n' \
    "$(echo "${PREV_SLOT}" | tr 'a-z' 'A-Z')" \
    "$(echo "${TARGET_SLOT}" | tr 'a-z' 'A-Z')" \
    | atomic_write /boot/autoboot.txt

# Write boot_state for the watchdog — 3 tries before userspace rollback
# (also atomic, so a power cut cannot leave a half-written boot_state).
printf 'slot=%s\nprev_slot=%s\ntries_remaining=3\nconfirmed=false\n' \
    "${TARGET_SLOT}" "${PREV_SLOT}" \
    | atomic_write /boot/boot_state

# Remove stale rollback files from the legacy layout (slot dirs are the
# rollback copy now).
rm -f /boot/cmdline.txt.prev \
      /boot/kernel_2712.img.prev /boot/bcm2712-rpi-5-b.dtb.prev \
      /boot/kernel_2712.img.prev.tmp /boot/bcm2712-rpi-5-b.dtb.prev.tmp

mount -o remount,ro /boot

echo "[swupdate post-install] tryboot armed: boot_prefix=$(echo "${PREV_SLOT}" | tr 'a-z' 'A-Z')/ boot_prefix_try=$(echo "${TARGET_SLOT}" | tr 'a-z' 'A-Z')/"
echo "[swupdate post-install] boot_state written (slot=${TARGET_SLOT} prev=${PREV_SLOT} tries=3)"

# T051: Set U-Boot environment variables for firmware-level rollback.
# U-Boot increments bootcount on every boot; if bootcount >= bootlimit and
# upgrade_available==1, altbootcmd reverts the slot. The bootcount-reset
# systemd service clears upgrade_available on a healthy boot.
#
# NOTE: RPi5/CM5 use RPi firmware (not U-Boot) as primary bootloader; the
# tryboot mechanism above handles rollback on those boards. Boards using
# U-Boot (CM1, CM3, etc.) have fw_setenv and benefit from the U-Boot
# rollback mechanism.
if command -v fw_setenv &>/dev/null; then
    # Each call wrapped in `||` + a logger line so a corrupt or
    # read-only U-Boot env produces a visible journal entry, not a
    # silent abort (issue #50).
    fw_setenv upgrade_available 1 \
        || logger -t swupdate-post-install \
              "ERROR: fw_setenv upgrade_available 1 failed — U-Boot env may be read-only or corrupt"
    fw_setenv bootcount 0 \
        || logger -t swupdate-post-install \
              "ERROR: fw_setenv bootcount 0 failed — U-Boot env may be read-only or corrupt"
    fw_setenv bootlimit 3 \
        || logger -t swupdate-post-install \
              "ERROR: fw_setenv bootlimit 3 failed — U-Boot env may be read-only or corrupt"
    echo "[swupdate post-install] U-Boot env: upgrade_available=1 bootcount=0 bootlimit=3"
else
    echo "[swupdate post-install] fw_setenv not available — relying on RPi firmware tryboot"
fi

# Clean up temp files and symlink
rm -f /dev/swupdate-inactive \
      /run/swupdate-target-slot \
      /run/swupdate-target-dev \
      /run/swupdate-prev-slot