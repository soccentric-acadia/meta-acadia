#!/usr/bin/env bats
# test_rpi5_home_init_service.bats — regression test for the
# systemd ordering of rpi5-home-init.service.
#
# Issue #109: the unit declared only `After=local-fs.target`,
# which races against a slow p4 mount.  `local-fs.target` is
# reached while local filesystems are *being* processed, not
# when they are *all* mounted.  The fix is `RequiresMountsFor=/home`
# which makes systemd block until the p4 mount is actually present.
#
# This test verifies the *unit source* because the mount-timing
# race is exercised at first boot against real storage, which is
# not reproducible from a unit test.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/rpi5-home-init.service"
    [ -f "${SUT}" ] || skip "rpi5-home-init.service not found at ${SUT}"
}

@test "rpi5-home-init.service: Has RequiresMountsFor=/home (issue #109)" {
    # The fix: `RequiresMountsFor=/home` makes systemd wait for the
    # p4 mount to be present before starting the service.  Without
    # this, `findmnt -n -o SOURCE /home` inside the script races
    # against the mount and silently returns empty.
    grep -qE '^RequiresMountsFor=/home' "${SUT}"
}

@test "rpi5-home-init.service: After=local-fs.target preserved" {
    # Defensive: the fix adds RequiresMountsFor without dropping
    # After=local-fs.target (the existing ordering anchor).
    grep -qE '^After=local-fs\.target' "${SUT}"
}

@test "rpi5-home-init.service: Before=getty.target sshd.service preserved" {
    # Defensive: must complete before login services start, or the
    # user cannot log in on first boot.
    grep -qE '^Before=getty\.target[[:space:]]+sshd\.service' "${SUT}"
}

@test "rpi5-home-init.service: Type=oneshot" {
    grep -qE '^Type=oneshot' "${SUT}"
}

@test "rpi5-home-init.service: RemainAfterExit=yes" {
    grep -qE '^RemainAfterExit=yes' "${SUT}"
}

@test "rpi5-home-init.service: ExecStart points to /usr/lib/.../rpi5-home-init.sh" {
    grep -qE '^ExecStart=/usr/lib/rpi5-home-init/rpi5-home-init\.sh' "${SUT}"
}

@test "rpi5-home-init.service: WantedBy=multi-user.target" {
    grep -qE '^WantedBy=multi-user\.target' "${SUT}"
}

@test "rpi5-home-init.service: Description mentions /home" {
    grep -qF 'Description=Initialise /home' "${SUT}"
}
