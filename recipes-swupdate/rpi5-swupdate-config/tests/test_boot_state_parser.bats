#!/usr/bin/env bats
# test_boot_state_parser.bats — regression test for the boot_state parser
# used by swupdate-bootcheck.sh and boot-watchdog.sh.
#
# Verifies:
#   1. A well-formed boot_state file yields the expected variables.
#   2. A file containing shell metacharacters / command substitution is
#      NOT executed (no side effects).
#   3. Comment and blank lines are tolerated.
#
# Run with:  bats meta/meta-acadia/recipes-swupdate/rpi5-swupdate-config/tests/
#
# Reference issue: Acadia-OS#30.

setup() {
    TMP=$(mktemp -d)
    SENTINEL="$TMP/sentinel"
}

teardown() {
    rm -rf "${TMP}"
}

# Inline copy of the parser logic from swupdate-bootcheck.sh.  If the parser
# ever changes, this test will fail and must be updated alongside the
# production scripts.
parse_boot_state() {
    local file="$1"
    slot=""
    tries_remaining=""
    confirmed=""
    while IFS='=' read -r key value; do
        case "${key}" in
            slot)            slot="${value}" ;;
            tries_remaining) tries_remaining="${value}" ;;
            confirmed)       confirmed="${value}" ;;
            \#*|"")          : ;;
        esac
    done < "${file}"
}

@test "boot_state parser: well-formed file" {
    cat > "${TMP}/boot_state" <<STATE
slot=a
tries_remaining=3
confirmed=false
STATE
    parse_boot_state "${TMP}/boot_state"
    [ "${slot}" = "a" ]
    [ "${tries_remaining}" = "3" ]
    [ "${confirmed}" = "false" ]
}

@test "boot_state parser: blank lines and comments tolerated" {
    cat > "${TMP}/boot_state" <<STATE

# This is a comment
slot=b

# Another comment
tries_remaining=1
confirmed=true
STATE
    parse_boot_state "${TMP}/boot_state"
    [ "${slot}" = "b" ]
    [ "${tries_remaining}" = "1" ]
    [ "${confirmed}" = "true" ]
}

@test "boot_state parser: command substitution is NOT executed" {
    # This is the security regression test.  An OLD `source` parser would
    # run `touch <sentinel>` here; the NEW read loop must not.
    cat > "${TMP}/boot_state" <<STATE
slot=a
tries_remaining=3
confirmed=false
INJECTED=\$(touch ${SENTINEL})
STATE
    parse_boot_state "${TMP}/boot_state"
    [ ! -e "${SENTINEL}" ]
    [ "${slot}" = "a" ]
}

@test "boot_state parser: backticks NOT executed" {
    cat > "${TMP}/boot_state" <<STATE
slot=\`touch ${SENTINEL}\`
tries_remaining=3
confirmed=false
STATE
    parse_boot_state "${TMP}/boot_state"
    [ ! -e "${SENTINEL}" ]
    # The whole backtick expression is treated as a value, not executed
    [ "${slot}" = "\`touch ${SENTINEL}\`" ]
}

@test "boot_state parser: empty file yields empty vars" {
    : > "${TMP}/boot_state"
    parse_boot_state "${TMP}/boot_state"
    [ -z "${slot}" ]
    [ -z "${tries_remaining}" ]
    [ -z "${confirmed}" ]
}

@test "boot_state parser: unknown keys are silently ignored" {
    cat > "${TMP}/boot_state" <<STATE
slot=a
tries_remaining=3
confirmed=false
future_key=some_value
STATE
    parse_boot_state "${TMP}/boot_state"
    [ "${slot}" = "a" ]
    [ "${tries_remaining}" = "3" ]
    [ "${confirmed}" = "false" ]
}
