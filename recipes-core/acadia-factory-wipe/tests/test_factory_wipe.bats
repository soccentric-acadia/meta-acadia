#!/usr/bin/env bats
# test_factory_wipe.bats — functional tests for acadia-factory-wipe.sh
# (T-P33). The script runs against a sandbox tree through its
# ACADIA_PST_MNT / ACADIA_HOME_MNT / ACADIA_VAR_ROOT overrides.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/acadia-factory-wipe.sh"
    UNIT="${BATS_TEST_DIRNAME}/../files/acadia-factory-wipe.service"
    SB="$(mktemp -d)"
    export ACADIA_PST_MNT="${SB}/pst" ACADIA_HOME_MNT="${SB}/home" ACADIA_VAR_ROOT="${SB}"
    mkdir -p "${SB}/pst/factory/identity" "${SB}/pst/webconfig/certs" "${SB}/pst/system/alarms" \
             "${SB}/pst/state/ota" "${SB}/pst/backup" "${SB}/pst/lost+found" \
             "${SB}/home/operator/.ssh" "${SB}/home/acadia" "${SB}/home/lost+found" \
             "${SB}/var/lib/webconfig-ota" "${SB}/var/log/journal/abc"
    echo "claim_code: ABCD1234" > "${SB}/pst/factory/identity/identity.yaml"
    echo secret > "${SB}/pst/factory/identity/.secret"
    echo db > "${SB}/pst/webconfig/config.db"
    echo key > "${SB}/home/operator/.ssh/authorized_keys"
    echo conf > "${SB}/home/acadia/client.conf"
    touch "${SB}/home/.home-initialised"
    echo bundle > "${SB}/var/lib/webconfig-ota/stage.swu"
    echo j > "${SB}/var/log/journal/abc/system.journal"
    echo cfg > "${SB}/pst/system/alarms/config.yaml"
}

teardown() { rm -rf "${SB}"; }

request() { printf '{"level":"%s","requested_by":"admin"}\n' "$1" > "${SB}/pst/webconfig/factory-wipe.request"; }

@test "no request: nothing is touched" {
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ -f "${SB}/pst/webconfig/config.db" ]
    [ -f "${SB}/pst/system/alarms/config.yaml" ]
}

@test "settings: removes Instrumentation config/state only, consumes the request" {
    request settings
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ ! -e "${SB}/pst/system" ]
    [ ! -e "${SB}/pst/state" ]
    [ -f "${SB}/pst/webconfig/config.db" ]
    [ -d "${SB}/pst/backup" ]
    [ -f "${SB}/home/operator/.ssh/authorized_keys" ]
    [ -f "${SB}/pst/factory/identity/identity.yaml" ]
    [ ! -e "${SB}/pst/webconfig/factory-wipe.request" ]
}

@test "full: wipes /pst except factory identity, /home, OTA staging, journal" {
    request full
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ -f "${SB}/pst/factory/identity/identity.yaml" ]
    [ -f "${SB}/pst/factory/identity/.secret" ]
    [ -f "${SB}/pst/factory/last-wipe" ]
    [ -d "${SB}/pst/lost+found" ]
    [ ! -e "${SB}/pst/webconfig" ]
    [ ! -e "${SB}/pst/system" ]
    [ ! -e "${SB}/pst/backup" ]
    [ ! -e "${SB}/home/operator" ]
    [ ! -e "${SB}/home/acadia" ]
    [ ! -e "${SB}/home/.home-initialised" ]
    [ -d "${SB}/home/lost+found" ]
    [ -z "$(ls -A "${SB}/var/lib/webconfig-ota")" ]
    [ -z "$(ls -A "${SB}/var/log/journal")" ]
}

@test "unknown level: nothing wiped, request kept for inspection" {
    request everything
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ -f "${SB}/pst/webconfig/config.db" ]
    [ -d "${SB}/pst/system" ]
    [ -f "${SB}/pst/webconfig/factory-wipe.request" ]
}

@test "symlinked request is refused and removed" {
    ln -s /etc/passwd "${SB}/pst/webconfig/factory-wipe.request"
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ ! -e "${SB}/pst/webconfig/factory-wipe.request" ]
    [ -d "${SB}/pst/system" ]
}

@test "full: a symlink inside /home is removed, its target is not followed" {
    mkdir -p "${SB}/outside"; echo keep > "${SB}/outside/file"
    ln -s "${SB}/outside" "${SB}/home/link"
    request full
    run bash "${SUT}"
    [ "$status" -eq 0 ]
    [ ! -e "${SB}/home/link" ]
    [ -f "${SB}/outside/file" ]
}

@test "unit: runs before every consumer and the layout re-creators" {
    grep -q '^DefaultDependencies=no' "${UNIT}"
    grep -q '^RequiresMountsFor=/pst /home' "${UNIT}"
    for u in acadia-pst-init.service rpi5-home-init.service acadia-data-init.service \
             var-lib-acadia.mount acadia-factory-provision.service webconfigd.service \
             instr-istate.service acadia-client.service sshd.socket systemd-journal-flush.service; do
        grep -qE "^Before=.*\b${u}\b" "${UNIT}" || { echo "missing Before=${u}"; false; }
    done
    grep -q '^ConditionPathExists=/pst/webconfig/factory-wipe.request' "${UNIT}"
}
