#!/usr/bin/env bats
# test_claim_code_mirror.bats — T-P33: after a factory reset reopens
# first-boot, the claim-code mirror is restored from the write-once record
# so first-boot stays gated by the label's code.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/acadia-provision-identity.sh"
    SB="$(mktemp -d)"
    mkdir -p "${SB}/pst/factory/identity" "${SB}/pst/webconfig"
    printf 'serial: AC0001\nclaim_code: ZX81QL7T\n' > "${SB}/pst/factory/identity/identity.yaml"
    echo s > "${SB}/pst/factory/identity/.secret"
}

teardown() { rm -rf "${SB}"; }

@test "existing record + missing mirror: mirror restored, record untouched" {
    before="$(sha256sum "${SB}/pst/factory/identity/identity.yaml")"
    run bash "${SUT}" --root "${SB}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SB}/pst/webconfig/claim-code")" = "ZX81QL7T" ]
    [ "$(stat -c %a "${SB}/pst/webconfig/claim-code")" = "600" ]
    [ "$(sha256sum "${SB}/pst/factory/identity/identity.yaml")" = "${before}" ]
}

@test "existing mirror is left alone" {
    printf 'OLDCODE1' > "${SB}/pst/webconfig/claim-code"
    run bash "${SUT}" --root "${SB}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SB}/pst/webconfig/claim-code")" = "OLDCODE1" ]
}

@test "no webconfig dir: nothing mirrored, still succeeds" {
    rmdir "${SB}/pst/webconfig"
    run bash "${SUT}" --root "${SB}"
    [ "$status" -eq 0 ]
    [ ! -e "${SB}/pst/webconfig" ]
}
