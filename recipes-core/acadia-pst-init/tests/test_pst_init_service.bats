#!/usr/bin/env bats
# test_pst_init_service.bats — regression tests for the pst.mount unit and
# acadia-pst-init.service ordering (task 003).
#
# Contract:
#   - pst.mount mounts LABEL=pst at /pst and joins the local-fs chain.
#   - ConditionPathExists=/dev/disk/by-label/pst makes the unit skip
#     silently on devices with the old 4-partition layout (migration
#     safety) instead of failing local-fs.target.
#   - acadia-pst-init.service waits for the mount (RequiresMountsFor — the
#     issue #109 precedent) and for sysusers (instr-* users), and carries
#     the same skip condition.
#   - The instr-istate.service drop-in adds the ownership-bootstrap
#     ordering; mount-unit ordering itself is already declared by the
#     instrumentation daemon units (RequiresMountsFor=/pst).

MOUNT_SUT="${BATS_TEST_DIRNAME}/../files/pst.mount"
SERVICE_SUT="${BATS_TEST_DIRNAME}/../files/acadia-pst-init.service"
DROPIN_SUT="${BATS_TEST_DIRNAME}/../files/instr-istate.service.d-pst-order.conf"

@test "pst.mount: mounts LABEL=pst at /pst as ext4" {
    [ -f "${MOUNT_SUT}" ] || skip "pst.mount not found"
    grep -qE '^What=LABEL=pst' "${MOUNT_SUT}"
    grep -qE '^Where=/pst$' "${MOUNT_SUT}"
    grep -qE '^Type=ext4' "${MOUNT_SUT}"
}

@test "pst.mount: ConditionPathExists guards the old layout" {
    [ -f "${MOUNT_SUT}" ] || skip "pst.mount not found"
    grep -qE '^ConditionPathExists=/dev/disk/by-label/pst' "${MOUNT_SUT}"
}

@test "pst.mount: wanted by local-fs.target" {
    [ -f "${MOUNT_SUT}" ] || skip "pst.mount not found"
    grep -qE '^WantedBy=local-fs\.target' "${MOUNT_SUT}"
}

@test "pst.mount: no wic fstab dependency (mount unit, not fstab)" {
    # The wks must not give the pst partition a mountpoint; the OTA-packaged
    # .rootfs.ext4 carries no wic fstab entries.
    WKS="${BATS_TEST_DIRNAME}/../../../wic/sdimage-rpi5.wks"
    [ -f "${WKS}" ] || skip "wks not found"
    ! grep -qE '^part /pst' "${WKS}"
}

@test "acadia-pst-init.service: RequiresMountsFor=/pst (issue #109 precedent)" {
    [ -f "${SERVICE_SUT}" ] || skip "acadia-pst-init.service not found"
    grep -qE '^RequiresMountsFor=/pst' "${SERVICE_SUT}"
    grep -qE '^After=local-fs\.target' "${SERVICE_SUT}"
}

@test "acadia-pst-init.service: After=systemd-sysusers.service (instr users exist)" {
    [ -f "${SERVICE_SUT}" ] || skip "acadia-pst-init.service not found"
    grep -qE '^After=local-fs\.target systemd-sysusers\.service' "${SERVICE_SUT}"
}

@test "acadia-pst-init.service: skip condition for old layout" {
    [ -f "${SERVICE_SUT}" ] || skip "acadia-pst-init.service not found"
    grep -qE '^ConditionPathExists=/dev/disk/by-label/pst' "${SERVICE_SUT}"
}

@test "acadia-pst-init.service: oneshot with RemainAfterExit" {
    [ -f "${SERVICE_SUT}" ] || skip "acadia-pst-init.service not found"
    grep -qE '^Type=oneshot' "${SERVICE_SUT}"
    grep -qE '^RemainAfterExit=yes' "${SERVICE_SUT}"
    grep -qE '^ExecStart=/usr/lib/acadia-pst-init/acadia-pst-init\.sh' "${SERVICE_SUT}"
}

@test "istate drop-in: orders istate after the ownership bootstrap" {
    [ -f "${DROPIN_SUT}" ] || skip "drop-in not found"
    grep -qE '^After=acadia-pst-init\.service' "${DROPIN_SUT}"
    # Mount ordering is owned by the daemon unit (RequiresMountsFor=/pst in
    # Acadia-Instrumentation's instr-istate.service) — do not duplicate it.
    ! grep -vE '^[[:space:]]*#' "${DROPIN_SUT}" | grep -qF 'RequiresMountsFor'
}