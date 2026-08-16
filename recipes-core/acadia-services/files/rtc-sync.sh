#!/bin/sh
# rtc-sync.sh — sync the system clock with the battery-backed RTC.
#
# The i2c-rtc overlay (dtoverlay=i2c-rtc,pcf8523 in kas/common.yaml)
# exposes a battery-backed RTC as /dev/rtc0.  This script:
#   * on boot  (mode=read):  if the system clock is invalid (before the
#     kernel build epoch), set it from the RTC so timestamps are accurate
#     even when offline (relevant since chrony is only in the optional
#     cloud packagegroup).
#   * on shutdown (mode=write): write the current system time to the RTC
#     so it survives power-off.
#
# Usage: rtc-sync.sh read|write

MODE="${1:-read}"
RTC_DEV="${RTC_DEV:-/dev/rtc0}"

if [ ! -e "${RTC_DEV}" ]; then
    logger -t rtc-sync -p user.warning \
        "${RTC_DEV} not present — RTC overlay not active?" || true
    exit 0
fi

case "${MODE}" in
    read)
        # If the system clock is before the kernel build epoch, it is
        # invalid — pull the time from the RTC.
        NOW=$(date +%s 2>/dev/null || echo 0)
        if [ "${NOW}" -lt 1600000000 ]; then
            hwclock -r -f "${RTC_DEV}" 2>/dev/null \
                && hwclock -s -f "${RTC_DEV}" 2>/dev/null \
                && logger -t rtc-sync "system clock set from RTC" || true
        fi
        ;;
    write)
        hwclock -w -f "${RTC_DEV}" 2>/dev/null \
            && logger -t rtc-sync "system time written to RTC" || true
        ;;
    *)
        echo "usage: rtc-sync.sh read|write" >&2
        exit 1
        ;;
esac

exit 0
