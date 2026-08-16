#!/bin/sh
# thermal-check.sh — warn when the SoC temperature exceeds a threshold.
#
# Mirrors the disk-usage-check pattern in acadia-services.  Reads the
# thermal zone exposed by the BCM2712 (thermal_zone0) and logs a warning
# when the temperature crosses the threshold.  Also captures the
# undervoltage / throttling state from the kernel's throttling sysfs
# (equivalent of vcgencmd get_throttled, which is Raspbian-specific and
# not available in a Yocto build).
#
# Threshold in millidegrees Celsius (default 80 °C = 80000).

THRESHOLD="${THERMAL_THRESHOLD:-80000}"
ZONE="${THERMAL_ZONE:-/sys/class/thermal/thermal_zone0/temp}"

if [ ! -r "${ZONE}" ]; then
    logger -t thermal-check -p user.warning \
        "thermal zone ${ZONE} not readable — skipping" || true
    exit 0
fi

TEMP=$(cat "${ZONE}" 2>/dev/null | tr -d '\n')
if [ -z "${TEMP}" ]; then
    exit 0
fi

# Some kernels report millidegrees, some degrees; normalise to degrees.
case "${TEMP}" in
    *[0-9][0-9][0-9][0-9][0-9]) DEG=$((TEMP / 1000)) ;;  # millidegrees
    *) DEG="${TEMP}" ;;                                  # degrees
esac

if [ "${DEG}" -ge "$((THRESHOLD / 1000))" ]; then
    msg="THERMAL WARNING: SoC at ${DEG}°C (threshold: $((THRESHOLD / 1000))°C)"
    echo "${msg}" >&2
    logger -t thermal-check -p user.warning "${msg}" || true
fi

# ── Undervoltage / throttling capture ───────────────────────────────────────
# BCM2712 exposes throttling state via the cpufreq/thermal sysfs.  The
# kernel logs "CPU frequency is limited" / "undervoltage detected" to the
# ring buffer; surface the most recent occurrence so an operator can see
# it without a serial console.
if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | grep -iE 'undervoltage|throttl|frequency is limited' \
        | tail -3 | while read -r line; do
            logger -t thermal-check -p user.warning "throttle: ${line}" || true
        done
fi

exit 0
