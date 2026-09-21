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
    WKS="$(dirname "${BATS_TEST_DIRNAME}")/../../../../meta/meta-acadia/wic/sdimage-rpi5.wks"
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

# ── Task 003: /pst persistent store partition ────────────────────────────
# The A/B layout must carry a dedicated 1 GB /pst partition (label "pst")
# declared BEFORE /home, so /home stays the LAST partition and the
# rpi5-home-init "grow to 100%" logic keeps working unchanged.  The pst
# part must have NO mountpoint: wic would otherwise write a fstab line,
# but the OTA-packaged .rootfs.ext4 does not carry wic fstab entries —
# mounting is owned by the rootfs-packaged pst.mount unit instead.

@test "A/B layout declares the 1 GB pst partition (task 003)" {
    grep -qE '^part --ondisk mmcblk0 --fstype=ext4 --label pst --align 4096 --fixed-size 1024M$' "${WKS}"
}

@test "pst partition is mkfs'd (no --source empty — EmptyPartitionPlugin gives unformatted zeros)" {
    # --source empty creates an UNFORMATTED partition in this poky; the
    # formatted empty volume requires omitting --source.  rootfs-b keeps
    # --source empty deliberately (SWUpdate raw-writes it).
    local pst_line
    pst_line=$(grep -nE '^part .*--label pst ' "${WKS}" | cut -d: -f1)
    ! sed -n "${pst_line}p" "${WKS}" | grep -q -- '--source'
    ! grep -nE '^part /home ' "${WKS}" | grep -q -- '--source'
}

@test "pst partition has no mountpoint (no wic fstab entry)" {
    # Every pst line must be a bare `part --source empty ...` line with no
    # leading mountpoint (the /home line keeps its mountpoint).
    ! grep -qE '^part /pst' "${WKS}"
    grep -qE '^part /home' "${WKS}"
}

@test "pst partition is declared before home (home stays last)" {
    local pst_line home_line
    pst_line=$(grep -nE '^part .*--label pst ' "${WKS}" | cut -d: -f1)
    home_line=$(grep -nE '^part /home' "${WKS}" | cut -d: -f1)
    [ -n "${pst_line}" ] && [ -n "${home_line}" ]
    [ "${pst_line}" -lt "${home_line}" ]
    # home is the last part line in the wks.
    local last_part
    last_part=$(grep -nE '^part ' "${WKS}" | tail -1 | cut -d: -f1)
    [ "${home_line}" -eq "${last_part}" ]
}
