#!/usr/bin/env bats
# test_health_services.bats — regression test for the thermal-check,
# rtc-sync and hardware-watchdog units (fan control is kernel-owned, T-P30) added to
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

@test "fan control is kernel-owned (T-P30, OS-052/053): no userspace fan loop" {
    [ ! -e "${FILES}/fan-control.sh" ]
    [ ! -e "${FILES}/fan-control.service" ]
    ! grep -q 'fan-control' "${BATS_TEST_DIRNAME}/../acadia-services.bb"
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

# ── T-P30 (OS-055): rtc-sync behaviour with stubbed tools ─────────────────
_rtc_stub() {
    STUB="${BATS_TEST_TMPDIR}/bin"; mkdir -p "${STUB}"
    printf '#!/bin/sh\necho "$@" >> %s/hwclock.log\n' "${BATS_TEST_TMPDIR}" > "${STUB}/hwclock"
    printf '#!/bin/sh\necho "%s"\n' "$1" > "${STUB}/timedatectl"
    printf '#!/bin/sh\nexit 0\n' > "${STUB}/logger"
    chmod +x "${STUB}"/*
    touch "${BATS_TEST_TMPDIR}/rtc0"
}

@test "rtc-sync read: loads the RTC when the clock is not synchronised" {
    _rtc_stub no
    PATH="${STUB}:${PATH}" RTC_DEV="${BATS_TEST_TMPDIR}/rtc0" sh "${FILES}/rtc-sync.sh" read
    grep -q -- '-s -f' "${BATS_TEST_TMPDIR}/hwclock.log"
}

@test "rtc-sync read: leaves a synchronised clock alone" {
    _rtc_stub yes
    PATH="${STUB}:${PATH}" RTC_DEV="${BATS_TEST_TMPDIR}/rtc0" sh "${FILES}/rtc-sync.sh" read
    [ ! -e "${BATS_TEST_TMPDIR}/hwclock.log" ]
}

@test "rtc-sync write: only a synchronised clock is saved to the RTC" {
    _rtc_stub no
    PATH="${STUB}:${PATH}" RTC_DEV="${BATS_TEST_TMPDIR}/rtc0" sh "${FILES}/rtc-sync.sh" write
    [ ! -e "${BATS_TEST_TMPDIR}/hwclock.log" ]
    _rtc_stub yes
    PATH="${STUB}:${PATH}" RTC_DEV="${BATS_TEST_TMPDIR}/rtc0" sh "${FILES}/rtc-sync.sh" write
    grep -q -- '-w -f' "${BATS_TEST_TMPDIR}/hwclock.log"
}
