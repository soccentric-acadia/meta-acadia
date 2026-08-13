#!/usr/bin/env bats
# test_size_bounds.bats — regression test for the per-file kernel/DTB
# size bounds in swupdate-bootcheck.sh and boot-watchdog.sh.
#
# Issue #26: the previous single `if SIZE < 1MB || SIZE > 10MB` shared
# between kernel and DTB always tripped on a 60 KB DTB.  A health
# check that always reports unhealthy is worse than no health check.
# Fix is per-file bounds (kernel 1-20 MB, DTB 10 KB-5 MB).
#
# This test inlines the same `case` block from both scripts.  If the
# bounds change in either script, this test must change in the same
# commit.

setup() {
    TMP=$(mktemp -d)
}

teardown() {
    rm -rf "${TMP}"
}

# Inline copy of the per-file size check used in BOTH
# swupdate-bootcheck.sh and boot-watchdog.sh.  IMPORTANT: the
# production code iterates `for f in kernel_2712.img bcm2712-rpi-5-b.dtb`
# and the `case` statement matches `f` (the basename, not a full
# path).  The test mirrors that: pass the basename, and the function
# uses `stat -c%s <full_path>` internally.
check_size() {
    local f="$1"
    local path="${TMP}/${f}"
    case "${f}" in
        kernel_2712.img)
            MIN=$((1024 * 1024))
            MAX=$((20 * 1024 * 1024))
            ;;
        *-rpi-*-b.dtb|*-rpi-*-cm*.dtb|*-rpi-*.dtb)
            MIN=$((10 * 1024))
            MAX=$((5 * 1024 * 1024))
            ;;
        *)
            MIN=1024
            MAX=$((50 * 1024 * 1024))
            ;;
    esac
    SIZE=$(stat -c%s "${path}" 2>/dev/null || echo 0)
    if [[ "${SIZE}" -lt "${MIN}" ]] || [[ "${SIZE}" -gt "${MAX}" ]]; then
        return 1
    fi
    return 0
}

@test "size bounds: healthy kernel (7 MB) passes" {
    dd if=/dev/zero of="${TMP}/kernel_2712.img" bs=1024 count=$((7 * 1024)) status=none
    check_size "kernel_2712.img"
}

@test "size bounds: healthy DTB (60 KB) passes" {
    # This is the regression case: 60 KB DTB was always tripping the
    # old shared 1MB-10MB bound.
    dd if=/dev/zero of="${TMP}/bcm2712-rpi-5-b.dtb" bs=1024 count=60 status=none
    check_size "bcm2712-rpi-5-b.dtb"
}

@test "size bounds: 0-byte kernel fails" {
    : > "${TMP}/kernel_2712.img"
    ! check_size "kernel_2712.img"
}

@test "size bounds: too-small DTB fails" {
    dd if=/dev/zero of="${TMP}/bcm2712-rpi-5-b.dtb" bs=1 count=512 status=none
    ! check_size "bcm2712-rpi-5-b.dtb"
}

@test "size bounds: oversize kernel fails" {
    # 25 MB kernel — too big (bound is 20 MB)
    dd if=/dev/zero of="${TMP}/kernel_2712.img" bs=1024 count=$((25 * 1024)) status=none
    ! check_size "kernel_2712.img"
}

@test "size bounds: oversize DTB fails" {
    # 6 MB DTB — too big (bound is 5 MB)
    dd if=/dev/zero of="${TMP}/bcm2712-rpi-5-b.dtb" bs=1024 count=$((6 * 1024)) status=none
    ! check_size "bcm2712-rpi-5-b.dtb"
}

@test "size bounds: rpi4 DTB (bcm2711-rpi-4-b.dtb) is recognised" {
    # RPi 4 / RPi 3 use different SoC numbers in their DTB names;
    # the wildcard pattern must match them all.
    dd if=/dev/zero of="${TMP}/bcm2711-rpi-4-b.dtb" bs=1024 count=60 status=none
    check_size "bcm2711-rpi-4-b.dtb"
}
