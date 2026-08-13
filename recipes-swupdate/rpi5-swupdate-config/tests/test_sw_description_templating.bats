#!/usr/bin/env bats
# test_sw_description_templating.bats — regression test for the
# per-board kernel/DTB templating in sw-description.
#
# Issue #113: sw-description hardcoded `kernel_2712.img` and
# `bcm2712-rpi-5-b.dtb` (the rpi5 names).  The Makefile correctly
# derived the per-board kernel/DTB and copied them into the cpio,
# but the sw-description still referenced the rpi5 names.  The
# fix adds @@KERNEL@@ and @@DTB@@ tokens to sw-description and
# the sed pipeline in the `swu` target substitutes them.
#
# This test verifies the *source* files (sw-description and
# Makefile) and the *generated* sw-description for two boards.

setup() {
    # tests/ is 5 levels deep: tests → rpi5-swupdate-config → recipes-swupdate
    # → meta-acadia → meta → Acadia-OS.  Up 5 = repo root.
    SUT_DESC="${BATS_TEST_DIRNAME}/../../../../../meta/meta-acadia/swupdate/sw-description"
    SUT_MK="${BATS_TEST_DIRNAME}/../../../../../Makefile"
    [ -f "${SUT_DESC}" ] || skip "sw-description not found at ${SUT_DESC}"
    [ -f "${SUT_MK}" ]    || skip "Makefile not found at ${SUT_MK}"

    # Build a templated sw-description into TMP for end-to-end checks.
    export TMPDIR_TEST=$(mktemp -d)
    sed -e "s|@@VERSION@@|1.2.3|" \
        -e "s|@@KERNEL@@|${TEST_KERNEL:-kernel_2711.img}|g" \
        -e "s|@@DTB@@|${TEST_DTB:-bcm2711-rpi-4-b.dtb}|g" \
        "${SUT_DESC}" > "${TMPDIR_TEST}/sw-description"
}

teardown() {
    rm -rf "${TMPDIR_TEST}"
}

# --- sw-description source has the tokens -------------------------------

@test "sw-description: contains @@KERNEL@@ token (issue #113)" {
    grep -qF '@@KERNEL@@' "${SUT_DESC}"
}

@test "sw-description: contains @@DTB@@ token" {
    grep -qF '@@DTB@@' "${SUT_DESC}"
}

@test "sw-description: contains @@VERSION@@ token" {
    grep -qF '@@VERSION@@' "${SUT_DESC}"
}

@test "sw-description: NO hardcoded kernel_2712.img in filename/path" {
    # The bug: sw-description hardcoded rpi5's kernel image.  The
    # fix replaces it with @@KERNEL@@ tokens.  Verify the literal
    # 'kernel_2712.img' is gone (it may still appear in comments
    # as historical context, which is fine).
    ! grep -qE 'filename.*=.*"kernel_2712\.img"' "${SUT_DESC}"
    ! grep -qE 'path.*=.*"/boot/kernel_2712\.img"' "${SUT_DESC}"
}

@test "sw-description: NO hardcoded bcm2712-rpi-5-b.dtb in filename/path" {
    ! grep -qE 'filename.*=.*"bcm2712-rpi-5-b\.dtb"' "${SUT_DESC}"
    ! grep -qE 'path.*=.*"/boot/bcm2712-rpi-5-b\.dtb"' "${SUT_DESC}"
}

# --- Makefile substitutes the tokens ------------------------------------

@test "Makefile swu target: sed substitutes @@KERNEL@@" {
    # The fix uses a 3-expression sed: version, kernel, dtb.
    grep -qF '@@KERNEL@@|$(SWU_KERNEL)|g' "${SUT_MK}"
}

@test "Makefile swu target: sed substitutes @@DTB@@" {
    grep -qF '@@DTB@@|$(SWU_DTB)|g' "${SUT_MK}"
}

@test "Makefile swu target: uses sed -e (multiple expressions)" {
    # The old Makefile used a single `sed "s|...|...|"` invocation.
    # The fix uses `sed -e ... -e ... -e ...` for the three tokens.
    grep -qE '^[[:space:]]*@sed -e' "${SUT_MK}"
    # And specifically references the version token in the first -e
    grep -qF '@@VERSION@@|$(SWU_VERSION)|' "${SUT_MK}"
}

# --- End-to-end templating for rpi4-64 ---------------------------------

@test "templating rpi4-64: produces kernel_2711.img filename" {
    TEST_KERNEL=kernel_2711.img TEST_DTB=bcm2711-rpi-4-b.dtb \
        bash -c 'setup() { :; }; source <(echo "TMPDIR_TEST=$(mktemp -d)"; echo "TEST_KERNEL=kernel_2711.img"; echo "TEST_DTB=bcm2711-rpi-4-b.dtb"); sed -e "s|@@VERSION@@|1.2.3|" -e "s|@@KERNEL@@|kernel_2711.img|g" -e "s|@@DTB@@|bcm2711-rpi-4-b.dtb|g" '"${SUT_DESC}"' > $TMPDIR_TEST/sw-description; grep -q "filename.*=.*\"kernel_2711.img\"" $TMPDIR_TEST/sw-description; rm -rf $TMPDIR_TEST'
}

@test "templating rpi5: produces kernel_2712.img filename" {
    run bash -c '
        SWUTMP=$(mktemp -d)
        sed -e "s|@@VERSION@@|1.0.0|" \
            -e "s|@@KERNEL@@|kernel_2712.img|g" \
            -e "s|@@DTB@@|bcm2712-rpi-5-b.dtb|g" \
            "'"${SUT_DESC}"'" > "$SWUTMP/sw-description"
        grep -q "filename.*=.*\"kernel_2712.img\"" "$SWUTMP/sw-description"
        rm -rf "$SWUTMP"
    '
    [ "$status" -eq 0 ]
}

@test "templating: no @@ tokens remain in generated sw-description" {
    run bash -c '
        SWUTMP=$(mktemp -d)
        sed -e "s|@@VERSION@@|1.0.0|" \
            -e "s|@@KERNEL@@|kernel.img|g" \
            -e "s|@@DTB@@|bcm2708-rpi-zero.dtb|g" \
            "'"${SUT_DESC}"'" > "$SWUTMP/sw-description"
        # If any @@ token remains, sed would not have substituted it
        # correctly.  grep with -c and check the count is 0.
        count=$(grep -c "@@" "$SWUTMP/sw-description" || true)
        [ "$count" -eq 0 ]
        rm -rf "$SWUTMP"
    '
    [ "$status" -eq 0 ]
}

@test "templating: /boot/<KERNEL> path uses the templated value" {
    run bash -c '
        SWUTMP=$(mktemp -d)
        sed -e "s|@@VERSION@@|1.0.0|" \
            -e "s|@@KERNEL@@|kernel7.img|g" \
            -e "s|@@DTB@@|bcm2709-rpi-2-b.dtb|g" \
            "'"${SUT_DESC}"'" > "$SWUTMP/sw-description"
        # rpi2: kernel is kernel7.img, not kernel_2712.img
        grep -q "path.*=.*\"/boot/kernel7.img\"" "$SWUTMP/sw-description"
        ! grep -q "/boot/kernel_2712.img" "$SWUTMP/sw-description"
        rm -rf "$SWUTMP"
    '
    [ "$status" -eq 0 ]
}
