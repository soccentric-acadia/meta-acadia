#!/usr/bin/env bats
# test_health_contract.bats — OTA health-check contract (task 47).
#
# The boot health check must cover HAL, webconfigd, networking, storage, and
# required dependencies with BOUNDED readiness (not a single fixed sleep/one
# service). These are static checks against the script source (the real run is
# target-required on a booted image).

setup() {
    SUT="$(dirname "${BATS_TEST_DIRNAME}")/files/swupdate-bootcheck.sh"
    [ -f "${SUT}" ] || skip "swupdate-bootcheck.sh not found"
}

@test "health check is bounded, not a fixed sleep" {
    # Must use a bounded wait loop (wait_service + WAIT_MAX), not a lone sleep 5.
    grep -qE 'WAIT_MAX=' "${SUT}"
    grep -qE 'wait_service\(\)' "${SUT}"
}

@test "health check covers the HAL service" {
    grep -qE 'hal\.service' "${SUT}"
}

@test "health check covers webconfigd" {
    grep -qE 'webconfigd\.service' "${SUT}"
}

@test "health check covers networking" {
    grep -qE 'ip -br addr' "${SUT}"
}

@test "health check covers storage" {
    grep -qE 'df -P /' "${SUT}"
}

@test "health check covers acadia-client" {
    grep -qE 'acadia-client\.service' "${SUT}"
}
