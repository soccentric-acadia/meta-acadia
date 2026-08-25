#!/usr/bin/env bats
# test_swu_board_support.bats — OTA board support consistency (task 48).
#
# The OTA/SWUpdate interface must only advertise boards that have a valid A/B
# layout and scripts. Unsupported boards must be rejected, not silently built
# with the wrong kernel/DTB. (These are static checks against the Makefile and
# WKS declarations; real image tests are target-required.)

setup() {
    MAKEFILE="$(dirname "${BATS_TEST_DIRNAME}")/../../../../Makefile"
    [ -f "${MAKEFILE}" ] || skip "OS Makefile not found"
}

@test "swu target restricts to rpi5 and cm5 only" {
    # The bundled SWUpdate flow writes an inactive slot and is only defined for
    # boards that select sdimage-rpi5.wks.
    grep -qE 'rpi5\|cm5' "${MAKEFILE}"
    grep -qE 'supported only for BOARD=rpi5 or BOARD=cm5' "${MAKEFILE}"
}

@test "swu target fails closed for unsupported boards" {
    # Non-rpi5/cm5 boards must hit an explicit exit 1, not build a broken .swu.
    grep -qE 'exit 1' "${MAKEFILE}"
}

@test "cm5 selects the A/B WKS layout" {
    grep -q 'WKS_FILE = "sdimage-rpi5.wks"' "$(dirname "${BATS_TEST_DIRNAME}")/../../../../kas/boards/cm5.yaml"
}

@test "rpi5 selects the A/B WKS layout" {
    grep -q 'WKS_FILE = "sdimage-rpi5.wks"' "$(dirname "${BATS_TEST_DIRNAME}")/../../../../kas/boards/rpi5.yaml"
}

@test "swu kernel/DTB table has an entry for rpi5 and cm5" {
    grep -qE 'ifeq \(\$\(BOARD\),rpi5\)' "${MAKEFILE}"
    grep -qE 'else ifeq \(\$\(BOARD\),cm5\)' "${MAKEFILE}"
}
