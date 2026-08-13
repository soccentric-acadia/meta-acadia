#!/bin/bash
# SWUpdate post-install script — included in every .swu package
#
# Updates /boot/cmdline.txt so that the RPi firmware boots the newly
# written slot on the next reboot, writes boot_state for the watchdog,
# and backs up cmdline.txt for rollback recovery.

set -euo pipefail

TARGET_SLOT=$(cat /run/swupdate-target-slot)
TARGET_DEV=$(cat  /run/swupdate-target-dev)

echo "[swupdate post-install] activating slot ${TARGET_SLOT} (${TARGET_DEV})"

# Resolve the PARTUUID of the target partition
TARGET_PARTUUID=$(blkid -s PARTUUID -o value "${TARGET_DEV}")
if [[ -z "${TARGET_PARTUUID}" ]]; then
    echo "[swupdate post-install] ERROR: cannot read PARTUUID from ${TARGET_DEV}" >&2
    exit 1
fi

mount -o remount,rw /boot

# Backup current cmdline.txt for rollback (boot-watchdog / swupdate-bootcheck)
cp /boot/cmdline.txt /boot/cmdline.txt.prev

# Switch root= to the new slot
sed -i "s|root=PARTUUID=[a-fA-F0-9-]*|root=PARTUUID=${TARGET_PARTUUID}|" \
    /boot/cmdline.txt

# Write boot_state for the watchdog — 3 tries before automatic rollback
printf 'slot=%s\ntries_remaining=3\nconfirmed=false\n' "${TARGET_SLOT}" \
    > /boot/boot_state

mount -o remount,ro /boot

echo "[swupdate post-install] cmdline.txt → root=PARTUUID=${TARGET_PARTUUID}"
echo "[swupdate post-install] boot_state written (slot=${TARGET_SLOT} tries=3)"

# T051: Set U-Boot environment variables for firmware-level rollback.
# U-Boot increments bootcount on every boot; if bootcount >= bootlimit and
# upgrade_available==1, altbootcmd reverts the slot. The bootcount-reset
# systemd service clears upgrade_available on a healthy boot.
#
# NOTE: RPi5/CM5 use RPi firmware (not U-Boot) as primary bootloader.
# fw_setenv may not be available on those boards. The RPi firmware's
# tryboot mechanism handles rollback automatically via boot_state.
# Boards using U-Boot (CM1, CM3, etc.) will have fw_setenv and benefit
# from the full U-Boot rollback mechanism.
if command -v fw_setenv &>/dev/null; then
    # Each call wrapped in `||` + a logger line so a corrupt or
    # read-only U-Boot env produces a visible journal entry, not a
    # silent abort (issue #50).  bootcount-reset.service depends on
    # upgrade_available=1 being set, so this branch must succeed or
    # the rollback chain silently regresses.
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
      /run/swupdate-target-dev
