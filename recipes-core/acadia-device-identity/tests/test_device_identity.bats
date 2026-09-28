#!/usr/bin/env bats

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/acadia-device-identity.sh"
    SB="$(mktemp -d)"
    export ACADIA_ROOT="${SB}"
    mkdir -p "${SB}/pst/factory/identity" "${SB}/sys/firmware/devicetree/base"
}

teardown() { rm -rf "${SB}"; }

@test "factory serial is canonical and survives repeated initialization" {
    printf 'serial: FACTORY123\n' > "${SB}/pst/factory/identity/identity.yaml"
    printf 'tree-serial' > "${SB}/sys/firmware/devicetree/base/serial-number"

    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SB}/pst/acadia/device-id")" = "acadia-FACTORY123" ]
    [ "$(cat "${SB}/var/lib/acadia/device-id")" = "acadia-FACTORY123" ]

    printf 'serial: DIFFERENT\n' > "${SB}/pst/factory/identity/identity.yaml"
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SB}/pst/acadia/device-id")" = "acadia-FACTORY123" ]
    [ "$(stat -c %a "${SB}/pst/acadia/device-id")" = 640 ]
}

@test "device tree is only used before factory provisioning" {
    printf 'tree-serial' > "${SB}/sys/firmware/devicetree/base/serial-number"
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SB}/pst/acadia/device-id")" = "acadia-tree-serial" ]
    [ "$(cat "${SB}/var/lib/acadia/device-id")" = "acadia-tree-serial" ]
}
