#!/usr/bin/env bats
# test_pre_install_sh.bats — regression test for the SWUpdate
# pre-install slot-detection logic.
#
# Issue #54: the previous pre-install.sh hardcoded /dev/mmcblk0p2
# and /dev/mmcblk0p3, which broke OTA on NVMe and USB boot
# devices.  The fix derives the inactive slot from the GPT
# partition label (rootfs-a / rootfs-b), which is independent of
# the underlying block device.
#
# We test the script's slot-resolution logic by mocking the
# external commands it calls (findmnt, lsblk, mount, cp, ln)
# via a temporary PATH.  The script is run unchanged in
# subshell, so this is a behaviour test, not a string match.
#
# Run with:  bats meta/meta-acadia/recipes-swupdate/rpi5-swupdate-config/tests/

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/pre-install.sh"
    [ -f "${SUT}" ] || skip "pre-install.sh not found at ${SUT}"

    # Stubs live in ${BIN}, prepended to PATH so the script picks
    # them up first.  BIN is created in setup() and torn down
    # in teardown().
    BIN=$(mktemp -d)
    TMP=$(mktemp -d)
    export PATH="${BIN}:${PATH}"
    export SWUPDATE_INACTIVE_SYMLINK="${TMP}/swupdate-inactive"
    export SWUPDATE_SLOT_FILE="${TMP}/swupdate-target-slot"
    export SWUPDATE_DEV_FILE="${TMP}/swupdate-target-dev"

    # /dev/swupdate-inactive and /run/swupdate-target-* are fixed
    # paths the script writes to.  We can't touch /dev or /run as
    # a normal user, so we sed-rewrite the SUT to write into TMP
    # and run the rewritten copy.
    SUT_RW="${TMP}/pre-install.sh"
    sed -e "s|/dev/swupdate-inactive|${TMP}/swupdate-inactive|g" \
        -e "s|/run/swupdate-target-slot|${SWUPDATE_SLOT_FILE}|g" \
        -e "s|/run/swupdate-target-dev|${SWUPDATE_DEV_FILE}|g" \
        "${SUT}" > "${SUT_RW}"
    chmod +x "${SUT_RW}"
    SUT="${SUT_RW}"

    # Stub mount — no-op.  The real mount is privileged; the script
    # only uses it to remount /boot rw, which we don't need.
    cat > "${BIN}/mount" <<'STUB'
#!/bin/sh
exit 0
STUB
    chmod +x "${BIN}/mount"

    # Stub cp — no-op.  We don't have a real /boot/ with kernel_2712.img.
    cat > "${BIN}/cp" <<'STUB'
#!/bin/sh
exit 0
STUB
    chmod +x "${BIN}/cp"

    # Stub ln — write the symlink target into a file the test can read.
    # The real ln would create /dev/swupdate-inactive, which we can't
    # do as a normal user; instead we record what the script *would*
    # have symlinked to.
    cat > "${BIN}/ln" <<'STUB'
#!/bin/sh
target=""
link=""
while [ $# -gt 0 ]; do
    case "$1" in
        -*) shift ;;
        *)
            if [ -z "${target}" ]; then target="$1"; else link="$1"; fi
            shift ;;
    esac
done
echo "${target}" > "${SWUPDATE_INACTIVE_SYMLINK}"
STUB
    chmod +x "${BIN}/ln"
}

teardown() {
    rm -rf "${BIN}" "${TMP}"
}

# Stub findmnt — return the path the test wants ACTIVE_DEV to be.
make_findmnt_stub() {
    local active_path="$1"
    cat > "${BIN}/findmnt" <<STUB
#!/bin/sh
echo "${active_path}"
STUB
    chmod +x "${BIN}/findmnt"
}

# Stub lsblk to map PATH/label pairs the script will query.
#   $1 = active path, $2 = active label, $3 = inactive path, $4 = inactive label
make_lsblk_stub() {
    local active_path="$1"  active_label="$2"
    local inactive_path="$3" inactive_label="$4"
    cat > "${BIN}/lsblk" <<STUB
#!/bin/sh
# The script calls us three ways:
#   lsblk -n -o LABEL <dev>      — return the LABEL of <dev>
#   lsblk -n -o PATH,LABEL       — return all devices as "PATH LABEL" rows
# We match the device argument by scanning for it in \$@.
target=""
for arg in "\$@"; do
    case "\${arg}" in
        "${active_path}")  target="single:${active_label}";  break ;;
        "${inactive_path}") target="single:${inactive_label}"; break ;;
    esac
done

if [ -n "\${target}" ] && echo "\${target}" | grep -q "^single:"; then
    echo "\${target#single:}"
    exit 0
fi

# No specific device requested — emit all rows.
echo "${active_path}  ${active_label}"
echo "${inactive_path} ${inactive_label}"
STUB
    chmod +x "${BIN}/lsblk"
}

@test "pre-install.sh: mmcblk0p2 (RPi 5 SD) — inactive is mmcblk0p3 (slot b)" {
    make_findmnt_stub "/dev/mmcblk0p2"
    make_lsblk_stub "/dev/mmcblk0p2" "rootfs-a" "/dev/mmcblk0p3" "rootfs-b"

    # Run the script in a subshell so 'set -e' exit doesn't kill
    # the test runner.  We replace /dev with a stub via the
    # test-time symlink trick.
    run bash "${SUT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"target slot: b"* ]]
    [ "$(cat "${SWUPDATE_INACTIVE_SYMLINK}")" = "/dev/mmcblk0p3" ]
    [ "$(cat "${SWUPDATE_SLOT_FILE}")" = "b" ]
    [ "$(cat "${SWUPDATE_DEV_FILE}")"  = "/dev/mmcblk0p3" ]
}

@test "pre-install.sh: mmcblk0p3 (active slot b) — inactive is mmcblk0p2 (slot a)" {
    make_findmnt_stub "/dev/mmcblk0p3"
    make_lsblk_stub "/dev/mmcblk0p2" "rootfs-a" "/dev/mmcblk0p3" "rootfs-b"

    run bash "${SUT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"target slot: a"* ]]
    [ "$(cat "${SWUPDATE_INACTIVE_SYMLINK}")" = "/dev/mmcblk0p2" ]
    [ "$(cat "${SWUPDATE_SLOT_FILE}")" = "a" ]
}

@test "pre-install.sh: NVMe boot (nvme0n1p2) — inactive is nvme0n1p3 (slot b)" {
    # Issue #54: this is the regression test.  Old script would
    # print 'unexpected active device' and exit 1.
    make_findmnt_stub "/dev/nvme0n1p2"
    make_lsblk_stub "/dev/nvme0n1p2" "rootfs-a" "/dev/nvme0n1p3" "rootfs-b"

    run bash "${SUT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"target slot: b"* ]]
    [ "$(cat "${SWUPDATE_INACTIVE_SYMLINK}")" = "/dev/nvme0n1p3" ]
}

@test "pre-install.sh: USB boot (sda2) — inactive is sda3 (slot b)" {
    make_findmnt_stub "/dev/sda2"
    make_lsblk_stub "/dev/sda2" "rootfs-a" "/dev/sda3" "rootfs-b"

    run bash "${SUT}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"target slot: b"* ]]
    [ "$(cat "${SWUPDATE_INACTIVE_SYMLINK}")" = "/dev/sda3" ]
}

@test "pre-install.sh: active label not rootfs-a/b — exits 1 with clear error" {
    make_findmnt_stub "/dev/sda2"
    make_lsblk_stub "/dev/sda2" "home" "/dev/sda3" "rootfs-b"

    run bash "${SUT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"not rootfs-a/b"* ]]
}

@test "pre-install.sh: no device with the inactive label — exits 1 with clear error" {
    # Edge case: A/B labels exist but the inactive one is missing
    # (e.g. one slot was wiped).  Don't silently default; abort.
    make_findmnt_stub "/dev/mmcblk0p2"
    # lsblk stub: active is rootfs-a, but no row exists for
    # rootfs-b (the inactive label).
    cat > "${BIN}/lsblk" <<'STUB'
#!/bin/sh
for arg in "$@"; do
    case "${arg}" in
        /dev/mmcblk0p2) echo "rootfs-a"; exit 0 ;;
    esac
done
# All-rows listing has only the active device.
echo "/dev/mmcblk0p2 rootfs-a"
STUB
    chmod +x "${BIN}/lsblk"

    run bash "${SUT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"no device with label 'rootfs-b'"* ]]
}

@test "pre-install.sh: NO hardcoded /dev/mmcblk0 in slot-detection logic" {
    # Defensive: a regression that re-adds the hardcoded mmcblk
    # path alongside the label lookup is a real risk.  Anchor on
    # the case arm specifically (not on the comment, which
    # intentionally references the old behaviour for context).
    # Grep the ORIGINAL file, not the sed-rewritten copy (SUT has
    # been redirected to TMP).
    ORIG="${BATS_TEST_DIRNAME}/../files/pre-install.sh"
    # Match only assignment-style / case-arm lines: the path
    # appears as a literal in a code statement, not in a comment.
    ! grep -qE '^[[:space:]]*(\(/dev/mmcblk0p[23]\)|INACTIVE_DEV=/dev/mmcblk0p[23])' "${ORIG}"
}
