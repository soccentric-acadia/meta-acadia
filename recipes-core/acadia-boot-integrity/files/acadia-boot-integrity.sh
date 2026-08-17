#!/bin/sh
set -eu

log() {
    logger -t acadia-boot-integrity "$*" || true
    printf '%s\n' "$*"
}

secure_boot="unknown"
for path in \
    /sys/firmware/devicetree/base/secure-boot \
    /sys/firmware/devicetree/base/chosen/bootloader/secure-boot \
    /proc/device-tree/chosen/bootloader/secure-boot; do
    if [ -e "$path" ]; then
        secure_boot="enabled"
        break
    fi
done
log "secure-boot=${secure_boot}"

verity_count=0
for uuid_file in /sys/block/dm-*/dm/uuid; do
    [ -r "$uuid_file" ] || continue
    uuid=$(cat "$uuid_file" 2>/dev/null || true)
    case "$uuid" in
        *verity*) verity_count=$((verity_count + 1)) ;;
    esac
done
log "dm-verity-mappings=${verity_count}"

if command -v rpi-eeprom-update >/dev/null 2>&1; then
    eeprom_status=$(rpi-eeprom-update 2>/dev/null | tr '\n' ' ' || true)
    log "eeprom=${eeprom_status:-unavailable}"
else
    log "eeprom=tool-unavailable"
fi

exit 0
