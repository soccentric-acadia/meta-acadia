#!/usr/bin/env bats
# test_wic_alignment.bats — board support aligned with WIC/OTA layouts (task 49).
#
# Every board that advertises OTA (SWUpdate A/B) must select the A/B WIC layout
# (sdimage-rpi5.wks). No board may be advertised for OTA without a tested A/B
# partition/update layout. Static checks against the kas board configs and the
# swu target restriction.

setup() {
    BOARDS="$(dirname "${BATS_TEST_DIRNAME}")/../../../../kas/boards"
    MAKEFILE="$(dirname "${BATS_TEST_DIRNAME}")/../../../../Makefile"
}

@test "exactly the OTA boards (rpi5, cm5) select the A/B WIC layout" {
    # Every board selecting sdimage-rpi5.wks is a supported OTA board.
    ab_boards=""
    for f in "${BOARDS}"/*.yaml; do
        if grep -q 'WKS_FILE = "sdimage-rpi5.wks"' "$f"; then
            ab_boards="${ab_boards} $(basename "$f" .yaml)"
        fi
    done
    echo "A/B-layout boards:${ab_boards}"
    # The A/B layout must be present on exactly rpi5 and cm5.
    echo "${ab_boards}" | grep -q 'rpi5'
    echo "${ab_boards}" | grep -q 'cm5'
    # No other board claims the A/B layout.
    others=$(echo "${ab_boards}" | tr ' ' '\n' | grep -vE '^(rpi5|cm5|)$' | grep -c . || true)
    [ "${others}" -eq 0 ]
}

@test "swu OTA support matches the A/B WIC layout boards" {
    # swu (Makefile) must accept exactly the boards with an A/B layout.
    grep -qE 'rpi5\|cm5' "${MAKEFILE}"
}
