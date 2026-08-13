#!/usr/bin/env bats
# test_expand_rootfs.bats — regression test for the device-name
# parsing in expand-rootfs.sh.
#
# Issue #110: the previous regex (`mmcblk[0-9]+p[0-9]+` first,
# `^([a-z]+)([0-9]+)$` second) silently mis-parses NVMe.  For
# `/dev/nvme0n1p2` the generic catch-all groups the literal `p`
# into the disk name → DISK_NAME=`nvme0n1p`, which is not a valid
# block device.  The fix is the same `lsblk -ndo PKNAME` +
# `/sys/class/block/.../partition` pattern that rpi5-home-init.sh
# already uses (C1).
#
# This test verifies the *script source* because the device-parsing
# logic is exercised at first-boot against a real block device, which
# is not reproducible from a unit test.  We test the code paths that
# would have regressed.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/expand-rootfs.sh"
    [ -f "${SUT}" ] || skip "expand-rootfs.sh not found at ${SUT}"
}

@test "expand-rootfs.sh: NO mmcblk regex on executable line (issue #110)" {
    # The bug pattern: explicit `mmcblk[0-9]+p[0-9]+` regex.
    # CLAUDE.md C2 explicitly forbids this; the lsblk + sysfs
    # pattern is the portable replacement.
    # Anchor on a non-comment line that contains an `=~` (regex match).
    ! grep -vE '^[[:space:]]*#' "${SUT}" | grep -qE 'mmcblk\[0-9\]'
}

@test "expand-rootfs.sh: NO generic alpha+digit catch-all regex" {
    # The bug pattern (second branch of the old two-arm regex):
    # `[a-z]+([0-9]+)`.  This silently mis-parses NVMe.
    # Anchor on a non-comment line that contains an `=~` (regex match).
    ! grep -vE '^[[:space:]]*#' "${SUT}" | grep -qE '\[a-z\]\+.*\[0-9\]\+'
}

@test "expand-rootfs.sh: uses lsblk -ndo PKNAME for parent disk" {
    # The fix: `lsblk -ndo PKNAME "/dev/${ROOT_DEV_NAME}"`
    grep -qE 'lsblk[[:space:]]+-ndo[[:space:]]+PKNAME' "${SUT}"
}

@test "expand-rootfs.sh: reads partition number from /sys/class/block" {
    # The fix: `cat "/sys/class/block/${ROOT_DEV_NAME}/partition"`
    grep -qE 'cat[[:space:]]+"/sys/class/block/.*partition"' "${SUT}"
}

@test "expand-rootfs.sh: fails clearly when lsblk cannot resolve parent" {
    # When PKNAME is empty (unrecognised layout), the script must
    # abort with a clear error, NOT silently fall through to a wrong
    # disk name.
    grep -qE 'cannot determine parent disk' "${SUT}"
}

@test "expand-rootfs.sh: fails clearly when partition number is unknown" {
    # When /sys/class/block/.../partition is unreadable, the script
    # must abort with a clear error.
    grep -qE 'cannot determine partition number' "${SUT}"
}

@test "expand-rootfs.sh: set -euo pipefail at the top" {
    # Defensive: any regression that introduces an unhandled error
    # will abort the script loudly.  expand-rootfs resizes the
    # *root* partition on first boot; silent partial-failure would
    # brick the device on next reboot.
    grep -qE '^set -euo pipefail' "${SUT}"
}

@test "expand-rootfs.sh: idempotent via FLAG file" {
    # First-boot idempotency — a FLAG file under /var/lib is touched
    # on success.  The flag must live on the *root* partition (the
    # one being grown) so that a re-flash re-runs the script.
    grep -qE '^FLAG="/var/lib/expand-rootfs-done"' "${SUT}"
    grep -qF 'touch "$FLAG"' "${SUT}"
}

@test "expand-rootfs.sh: still uses parted + resize2fs" {
    # README §12 documents `parted` + `resize2fs`.  Verify the
    # fix didn't drop either binary.
    grep -qE '^[[:space:]]*parted[[:space:]]+-s' "${SUT}"
    grep -qE '^[[:space:]]*resize2fs[[:space:]]+"\$ROOT_DEV"' "${SUT}"
}
