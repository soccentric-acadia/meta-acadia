#!/bin/sh
# rtc-sync.sh — keep the system clock and the battery-backed RTC in step.
#
# The i2c-rtc overlay (dtoverlay=i2c-rtc,pcf8523 in kas/common.yaml)
# exposes the RTC as /dev/rtc0 (its driver is a module, so the kernel's
# RTC_HCTOSYS does not run for it).
#   * boot (read):      unless NTP/PTP/GNSS already synchronised the clock,
#     load the time from the RTC. T-P30 (OS-055): the old "only if before
#     2020" test never fired — systemd already moves the clock to the build
#     epoch — so the RTC was never read and an offline unit booted with the
#     build date.
#   * shutdown (write): save the time to the RTC only when the clock is
#     synchronised, so a wrong clock never overwrites a good RTC.
#
# Usage: rtc-sync.sh read|write

MODE="${1:-read}"
RTC_DEV="${RTC_DEV:-/dev/rtc0}"

if [ ! -e "${RTC_DEV}" ]; then
    logger -t rtc-sync -p user.warning \
        "${RTC_DEV} not present — RTC overlay not active?" || true
    exit 0
fi

synchronized() {
    [ "$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)" = "yes" ]
}

case "${MODE}" in
    read)
        if synchronized; then
            logger -t rtc-sync "clock already synchronised; RTC not read" || true
        elif hwclock -r -f "${RTC_DEV}" >/dev/null 2>&1; then
            hwclock -s -f "${RTC_DEV}" \
                && logger -t rtc-sync "system clock set from RTC" || true
        else
            logger -t rtc-sync -p user.warning "RTC unreadable (battery?)" || true
        fi
        ;;
    write)
        if synchronized; then
            hwclock -w -f "${RTC_DEV}" \
                && logger -t rtc-sync "system time written to RTC" || true
        else
            logger -t rtc-sync "clock not synchronised; RTC left unchanged" || true
        fi
        ;;
    *)
        echo "usage: rtc-sync.sh read|write" >&2
        exit 1
        ;;
esac

exit 0
