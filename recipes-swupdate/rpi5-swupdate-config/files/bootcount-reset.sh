#!/bin/bash
# bootcount-reset.sh — T051: U-Boot env OTA rollback confirmation
#
# Runs once after a successful boot as a systemd oneshot service.
# Sets upgrade_available=0 and bootcount=0 in the U-Boot environment to
# signal that the current slot is healthy and rollback is not needed.
#
# The U-Boot bootlimit / upgrade_available mechanism works as follows:
#   1. swupdate post-install sets:   upgrade_available=1  bootcount=0  bootlimit=3
#   2. On every boot, U-Boot increments bootcount.
#      If bootcount >= bootlimit and upgrade_available==1 → U-Boot reverts to
#      the previous rootfs (via altbootcmd) and clears upgrade_available.
#   3. This script runs on a healthy boot and calls fw_setenv to clear
#      upgrade_available so the counter stops accumulating.

set -euo pipefail

# libubootenv installs fw_setenv/fw_printenv to ${bindir} (typically /usr/bin).
# Resolve at runtime so the script works regardless of the host layout.
FW_SETENV=$(command -v fw_setenv  || true)
FW_PRINTENV=$(command -v fw_printenv || true)

# Do nothing if fw_setenv is not present (factory images, non-OTA builds)
if [[ -z "${FW_SETENV}" || ! -x "${FW_SETENV}" ]]; then
    logger -t bootcount-reset "fw_setenv not found in PATH — skipping"
    exit 0
fi

# Read current value; if upgrade_available is already 0 nothing to do
CURRENT=$(${FW_PRINTENV:-/bin/true} -n upgrade_available 2>/dev/null || echo "0")
case "${CURRENT}" in
    0|"")
        logger -t bootcount-reset "upgrade_available already '${CURRENT}' — nothing to do"
        exit 0
        ;;
    1)
        : # expected post-OTA state — proceed to confirm
        ;;
    *)
        # Treat anything unexpected (corrupt env, wrong tool) as a warning, not a
        # silent skip. We still attempt to clear it so the counter doesn't tick
        # forever; the boot-watchdog will catch the slot if it really is bad.
        logger -t bootcount-reset \
            "WARNING: upgrade_available='${CURRENT}' is unexpected — clearing anyway"
        ;;
esac

# Confirm the update: clear upgrade_available and reset bootcount.
# Use `||` so a single failure is logged but the other still runs — we'd
# rather leave the counter half-reset than abort after the first call.
if ! ${FW_SETENV} upgrade_available 0; then
    logger -t bootcount-reset "ERROR: fw_setenv upgrade_available 0 failed"
    exit 1
fi
if ! ${FW_SETENV} bootcount 0; then
    logger -t bootcount-reset "ERROR: fw_setenv bootcount 0 failed"
    exit 1
fi

logger -t bootcount-reset \
    "Upgrade confirmed — upgrade_available cleared, bootcount reset to 0"
