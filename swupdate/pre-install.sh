#!/bin/bash
# SWUpdate pre-install script — included in every .swu package
#
# Identifies the inactive rootfs slot and creates the /dev/swupdate-inactive
# symlink. Also backs up kernel and DTB for rollback recovery.
#
# Issue #54: the previous version hardcoded /dev/mmcblk0p2/p3, which
# failed on NVMe (/dev/nvme0n1p2) and USB (/dev/sda1) boot.  The
# WKS partitions are labelled rootfs-a and rootfs-b regardless of
# underlying device, so we use the LABEL to find the inactive slot
# — this works on mmcblk, NVMe, and USB block devices.

set -euo pipefail

# Find the currently active root device
ACTIVE_DEV=$(findmnt -n -o SOURCE /)
echo "[swupdate pre-install] active root: ${ACTIVE_DEV}"

# Derive the inactive slot by GPT partition label.  The WKS labels the
# A/B rootfs partitions "rootfs-a" and "rootfs-b" on every supported
# device (mmcblk, NVMe, USB), so the inactive device is the one with
# the opposite label — no matter what /dev/<x>y<p> path it lives at.
ACTIVE_LABEL=$(lsblk -n -o LABEL "${ACTIVE_DEV}" 2>/dev/null | head -1 | tr -d ' ')

case "${ACTIVE_LABEL}" in
    rootfs-a)
        INACTIVE_LABEL=rootfs-b
        INACTIVE_SLOT=b
        ;;
    rootfs-b)
        INACTIVE_LABEL=rootfs-a
        INACTIVE_SLOT=a
        ;;
    *)
        echo "[swupdate pre-install] ERROR: active label '${ACTIVE_LABEL:-<empty>}' is not rootfs-a/b" >&2
        echo "[swupdate pre-install]        (WKS must label the A/B partitions rootfs-a and rootfs-b)" >&2
        exit 1
        ;;
esac

# Look up the inactive device by its label.  lsblk -n -o PATH returns
# /dev/<x>y<p> paths for every partition; pick the one whose final
# column is the LABEL we want.  head -1 defends against duplicate
# labels (which would be a separate bug, not this one).
INACTIVE_DEV=$(lsblk -n -o PATH,LABEL | awk -v want="${INACTIVE_LABEL}" '$2 == want {print $1; exit}')

if [[ -z "${INACTIVE_DEV}" ]]; then
    echo "[swupdate pre-install] ERROR: no device with label '${INACTIVE_LABEL}'" >&2
    exit 1
fi

echo "[swupdate pre-install] target slot: ${INACTIVE_SLOT} (${INACTIVE_DEV})"

# Backup kernel and DTB so boot-watchdog / bootcheck can restore them on rollback
# Task 46: atomic copy (write temp, fsync, rename) so a power loss never leaves
# a truncated .prev file that would fail the rollback restore.
mount -o remount,rw /boot
for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
    if [[ -f "/boot/${f}" ]]; then
        cp "/boot/${f}" "/boot/${f}.prev.tmp"
        sync -f "/boot/${f}.prev.tmp" 2>/dev/null || sync
        mv -f "/boot/${f}.prev.tmp" "/boot/${f}.prev"
        echo "[swupdate pre-install] backed up /boot/${f}"
    fi
done
mount -o remount,ro /boot

# Create the stable symlink the image handler will write to
ln -sf "${INACTIVE_DEV}" /dev/swupdate-inactive

# Persist slot info for post-install
echo "${INACTIVE_SLOT}" > /run/swupdate-target-slot
echo "${INACTIVE_DEV}"  > /run/swupdate-target-dev
