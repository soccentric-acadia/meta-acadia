#!/bin/sh
# fan-control.sh — thermal-based fan controller for the Pi5 Active Cooler /
# PoE+ HAT fan header.
#
# The official Pi5 Active Cooler and PoE+ HAT expose a PWM fan.  When the
# pwm-fan / rpi-poe overlay is active, the kernel exposes the fan as a
# hwmon device (e.g. /sys/class/hwmon/hwmon*/pwm1).  This service reads
# the SoC thermal zone and sets the fan PWM duty cycle accordingly,
# providing a userspace fan-control policy on top of the kernel thermal
# governor.
#
# Override the paths via environment in the unit if the hwmon index
# differs on a given board.

ZONE="${FAN_THERMAL_ZONE:-/sys/class/thermal/thermal_zone0/temp}"
# Fan PWM sysfs — resolved at runtime by globbing hwmon* for a pwm1 node.
FAN_PWM="${FAN_PWM:-}"

# Temperature thresholds (millidegrees) → PWM duty cycle (0-255).
#   < 50 °C : fan off (0)
#   50-60 °C: 25%  (64)
#   60-70 °C: 50%  (128)
#   70-80 °C: 75%  (192)
#   >= 80 °C: 100% (255)
set_pwm() {
    pwm="$1"
    if [ -n "${FAN_PWM}" ] && [ -w "${FAN_PWM}" ]; then
        printf '%s' "${pwm}" > "${FAN_PWM}" 2>/dev/null
        return
    fi
    # Resolve the fan PWM node by globbing hwmon devices.
    for hw in /sys/class/hwmon/hwmon*; do
        [ -e "${hw}/pwm1" ] || continue
        if [ -w "${hw}/pwm1" ]; then
            printf '%s' "${pwm}" > "${hw}/pwm1" 2>/dev/null
            return
        fi
    done
}

if [ ! -r "${ZONE}" ]; then
    logger -t fan-control -p user.warning \
        "thermal zone ${ZONE} not readable — skipping" || true
    exit 0
fi

TEMP=$(cat "${ZONE}" 2>/dev/null | tr -d '\n')
[ -n "${TEMP}" ] || exit 0

case "${TEMP}" in
    *[0-9][0-9][0-9][0-9][0-9]) DEG=$((TEMP / 1000)) ;;
    *) DEG="${TEMP}" ;;
esac

if [ "${DEG}" -lt 50 ]; then
    set_pwm 0
elif [ "${DEG}" -lt 60 ]; then
    set_pwm 64
elif [ "${DEG}" -lt 70 ]; then
    set_pwm 128
elif [ "${DEG}" -lt 80 ]; then
    set_pwm 192
else
    set_pwm 255
fi

logger -t fan-control -p user.info "SoC ${DEG}°C → fan PWM set" || true
exit 0
