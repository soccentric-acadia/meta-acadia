#!/usr/bin/env bats
# test_bootcount_reset_service.bats — regression test for the
# bootcount-reset.service ordering and binary-path gating.
#
# Issue #29: the previous service declared
#   After=network-online.target acadia-client.service
#   Wants=network-online.target
# The reset confirms a healthy slot; if the network never comes up
# (DHCP timeout, link down, lab isolation), the reset never runs and
# U-Boot's firmware-level bootcount keeps ticking, eventually rolling
# back a healthy slot.  The fix is to gate the reset on the same
# local-fs / pre-network checks as swupdate-bootcheck.service.
#
# Issue #57: the previous service hardcoded
#   ConditionPathExists=|/usr/bin/fw_setenv
#   ConditionPathExists=|/usr/sbin/fw_setenv
# libubootenv installs fw_setenv to ${bindir} (typically /usr/bin)
# via GNUInstallDirs, but the path can vary.  The script already
# resolves the binary at runtime via `command -v`; the service should
# not be stricter than the script.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/bootcount-reset.service"
    [ -f "${SUT}" ] || skip "bootcount-reset.service not found at ${SUT}"
}

@test "bootcount-reset.service: NO After=network-online.target" {
    # The reset is the OPPOSITE of rollback — it confirms a healthy
    # slot.  Gate it on local-fs, not on the network.
    ! grep -qE '^[[:space:]]*After=.*network-online\.target' "${SUT}"
}

@test "bootcount-reset.service: NO Wants=network-online.target" {
    ! grep -qE '^[[:space:]]*Wants=.*network-online\.target' "${SUT}"
}

@test "bootcount-reset.service: After=local-fs.target present" {
    grep -qE '^[[:space:]]*After=.*local-fs\.target' "${SUT}"
}

@test "bootcount-reset.service: After=swupdate-bootcheck.service present" {
    # Order after the health check — if the slot is unhealthy,
    # boot-watchdog.sh has already rolled it back; this service
    # would not run.  But for the happy path, run AFTER the
    # health check has flipped confirmed=true.
    grep -qE '^[[:space:]]*After=.*swupdate-bootcheck\.service' "${SUT}"
}

@test "bootcount-reset.service: NO ConditionPathExists=fw_setenv (issue #57)" {
    # The script resolves the binary at runtime.  The service
    # should not be stricter than the script.  If libubootenv
    # ever moves fw_setenv to /opt/, the service would silently
    # stop running and the env would never be cleared.
    ! grep -qE '^[[:space:]]*ConditionPathExists=.*fw_setenv' "${SUT}"
}

@test "bootcount-reset.service: no acadia-client.service dependency" {
    # acadia-client talks to a remote gRPC server; if the server
    # is down, the client is unhealthy, and the reset is gated.
    # Same defect as #29 in a different wrapper.
    ! grep -qE '^[[:space:]]*After=.*acadia-client\.service' "${SUT}"
    ! grep -qE '^[[:space:]]*Wants=.*acadia-client\.service' "${SUT}"
}

@test "bootcount-reset.service: ExecStart points to script in /usr/lib/swupdate/" {
    grep -qE '^[[:space:]]*ExecStart=/usr/lib/swupdate/bootcount-reset\.sh' "${SUT}"
}
