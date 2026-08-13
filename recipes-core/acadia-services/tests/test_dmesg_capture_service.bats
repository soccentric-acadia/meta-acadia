#!/usr/bin/env bats
# test_dmesg_capture_service.bats — regression test for the dmesg-capture
# service's persistent-storage strategy.
#
# Issue #56: the previous service wrote the dmesg output to
# /var/log/dmesg.boot.  Poky makes /var/log a symlink to
# /var/volatile/log by default, so the file was lost on every
# reboot — the dmesg you wanted to inspect was gone by the time
# you looked for it.  The fix is to pipe dmesg into systemd-cat
# (tag "dmesg-boot"), which writes to the persistent journal.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../../../recipes-core/acadia-services/files/dmesg-capture.service"
    [ -f "${SUT}" ] || skip "dmesg-capture.service not found at ${SUT}"
}

@test "dmesg-capture.service: NO redirect to /var/log/dmesg.boot" {
    # The bug pattern: \`> /var/log/dmesg.boot\`
    ! grep -qF '> /var/log/dmesg.boot' "${SUT}"
}

@test "dmesg-capture.service: uses systemd-cat" {
    # The fix: \`dmesg --color=never --since=@0 | systemd-cat -t dmesg-boot -p info\`
    grep -qF 'systemd-cat' "${SUT}"
}

@test "dmesg-capture.service: tags output with syslog identifier 'dmesg-boot'" {
    # \`systemd-cat -t dmesg-boot\` makes the journal entry filterable
    # via \`journalctl -t dmesg-boot -b\`.  Without -t, the entry is
    # tagged with the systemd unit name and the operator has to
    # remember it across reboots.
    grep -qE 'systemd-cat.*-t[[:space:]]+dmesg-boot' "${SUT}"
}

@test "dmesg-capture.service: After=systemd-journald.service" {
    # The journald daemon must be running before we can pipe into
    # systemd-cat.  Without this ordering, the pipe would block or
    # silently drop entries.
    grep -qE '^After=.*systemd-journald\.service' "${SUT}"
}

@test "dmesg-capture.service: After=local-fs.target" {
    grep -qE '^After=.*local-fs\.target' "${SUT}"
}

@test "dmesg-capture.service: Type=oneshot RemainAfterExit=yes" {
    # First-boot semantics: run once per boot, marked as active.
    grep -qE '^Type=oneshot' "${SUT}"
    grep -qE '^RemainAfterExit=yes' "${SUT}"
}
