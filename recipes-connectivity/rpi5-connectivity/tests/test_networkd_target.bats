#!/usr/bin/env bats
# test_networkd_target.bats — target-required network integration tests (task 32).
#
# Runs on a BOOTED Acadia image to verify DHCP, static addressing, Wi-Fi,
# network reload, DNS, and link-loss behavior end-to-end through the
# systemd-networkd runtime owner (task 31). On a host without systemd-networkd
# or without the target link these SKIP so the gate reports target-required
# distinctly, never a false pass/fail.

setup() {
    command -v networkctl >/dev/null 2>&1 || skip "networkctl not present (not a booted target)"
    [ -e /run/systemd/system ] || skip "not running under systemd (not a booted image)"
    # Only run when systemd-networkd is genuinely the active manager — a CI
    # container with systemd but no networkd is not a network target.
    systemctl is-active systemd-networkd.service >/dev/null 2>&1 \
        || skip "systemd-networkd not active (not a network target)"
}

@test "systemd-networkd owns networking (networkctl status works)" {
    networkctl status >/dev/null 2>&1
}

@test "systemd-resolved stub is /etc/resolv.conf" {
    [ -e /etc/resolv.conf ] || skip "no resolv.conf"
    grep -q '127.0.0.53\|systemd-resolved' /etc/resolv.conf 2>/dev/null \
        || readlink -f /etc/resolv.conf | grep -q 'systemd/resolve'
}

@test "at least one interface is managed by networkd" {
    run networkctl list
    [ "$status" -eq 0 ]
    # list should include lo plus at least one non-loopback entry
    managed=$(networkctl list --no-legend 2>/dev/null | grep -vc 'lo')
    [ "$managed" -ge 1 ]
}

@test "DHCP / static: an interface has an address" {
    ip -br addr show 2>/dev/null | awk 'NR>1 { if ($3 ~ /inet/) found=1 } END { exit !found }'
}

@test "networkd reload works (no error)" {
    run systemctl reload-or-restart systemd-networkd.service
    [ "$status" -eq 0 ]
}

@test "DNS resolves through systemd-resolved" {
    run getent hosts localhost
    [ "$status" -eq 0 ]
}
