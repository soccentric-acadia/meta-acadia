#!/usr/bin/env bats
# test_health_services.bats — regression test for the thermal-check,
# fan-control, rtc-sync, and hardware-watchdog units added to
# acadia-services during the task.md hardware-enablement pass.

setup() {
    FILES="${BATS_TEST_DIRNAME}/../../../recipes-core/acadia-services/files"
}

@test "thermal-check.sh: reads a thermal zone and warns above threshold" {
    [ -f "${FILES}/thermal-check.sh" ]
    grep -qF 'thermal_zone0/temp' "${FILES}/thermal-check.sh"
    grep -qF 'THERMAL WARNING' "${FILES}/thermal-check.sh"
}

@test "thermal-check.service: Type=oneshot, ExecStart points at script" {
    grep -qF 'Type=oneshot' "${FILES}/thermal-check.service"
    grep -qF 'ExecStart=/usr/sbin/thermal-check.sh' "${FILES}/thermal-check.service"
}

@test "thermal-check.timer: periodic (OnUnitActiveSec)" {
    grep -qF 'OnUnitActiveSec=5min' "${FILES}/thermal-check.timer"
}

@test "fan-control.sh: thermal-based PWM fan controller" {
    [ -f "${FILES}/fan-control.sh" ]
    grep -qF 'pwm1' "${FILES}/fan-control.sh"
    grep -qF 'set_pwm' "${FILES}/fan-control.sh"
}

@test "fan-control.service + timer: present and wired" {
    grep -qF 'ExecStart=/usr/sbin/fan-control.sh' "${FILES}/fan-control.service"
    grep -qF 'OnUnitActiveSec=30s' "${FILES}/fan-control.timer"
}

@test "rtc-sync.sh: reads RTC on boot, writes on shutdown" {
    [ -f "${FILES}/rtc-sync.sh" ]
    grep -qF 'hwclock -r' "${FILES}/rtc-sync.sh"
    grep -qF 'hwclock -w' "${FILES}/rtc-sync.sh"
}

@test "rtc-sync.service: runs before timesyncd" {
    grep -qF 'Before=systemd-timesyncd.service' "${FILES}/rtc-sync.service"
}

@test "rtc-sync-shutdown.service: WantedBy=shutdown.target" {
    grep -qF 'WantedBy=shutdown.target' "${FILES}/rtc-sync-shutdown.service"
}

@test "watchdog.conf: points at /dev/watchdog" {
    grep -qF 'watchdog-device = /dev/watchdog' "${FILES}/watchdog.conf"
}

@test "80-acadia-watchdog.preset: enables watchdog.service" {
    grep -qF 'enable watchdog.service' "${FILES}/80-acadia-watchdog.preset"
}
