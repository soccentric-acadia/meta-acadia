#!/usr/bin/env bats
# test_pst_init.bats — regression tests for acadia-pst-init.sh (task 003).
#
# The /pst consumers (istate owner; alarms, logmanager, ota, backup spokes)
# run as five distinct users sharing group `instr` and pin
# ReadWritePaths=/pst/<subdir> under ProtectSystem=strict — a missing or
# unwritable path is a start failure.  The init script must therefore
# provision ownership (instr-istate:instr, setgid 2770) and per-spoke
# directories BEFORE istate starts, and must skip cleanly on devices with
# the old 4-partition layout (no /pst mount) or without instrumentation
# users.
#
# Ownership is applied with mkdir + chown + chmod, never `install -o/-g`
# (issue #44: busybox install silently drops those flags).

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/acadia-pst-init.sh"
    [ -f "${SUT}" ] || skip "acadia-pst-init.sh not found at ${SUT}"
}

@test "acadia-pst-init.sh: skips when /pst is not a mountpoint (old layout)" {
    grep -qE 'findmnt[[:space:]]+-n[[:space:]]+"\$\{MNT\}"' "${SUT}"
    grep -qE 'old layout.*skipping|skipping\.' "${SUT}"
}

@test "acadia-pst-init.sh: falls back to root-owned store without instr-istate" {
    grep -qE 'getent[[:space:]]+passwd[[:space:]]+instr-istate' "${SUT}"
    grep -qE 'chmod[[:space:]]+0755[[:space:]]+"\$\{MNT\}"' "${SUT}"
}

@test "acadia-pst-init.sh: chowns /pst to instr-istate:instr" {
    grep -qE 'chown[[:space:]]+instr-istate:instr[[:space:]]+"\$\{MNT\}"' "${SUT}"
}

@test "acadia-pst-init.sh: setgid group-write mode 2770 on /pst and /pst/state" {
    # setgid + group rwx so directories istate creates inherit group `instr`.
    grep -qE 'chmod[[:space:]]+2770[[:space:]]+"\$\{MNT\}"$' "${SUT}"
    grep -qE 'chmod[[:space:]]+2770[[:space:]]+"\$\{MNT\}/state"' "${SUT}"
}

@test "acadia-pst-init.sh: NO install -d -o/-g (issue #44)" {
    ! grep -qE '^[[:space:]]*install[[:space:]]+.*-o[[:space:]]' "${SUT}"
    ! grep -qE '^[[:space:]]*install[[:space:]]+.*-g[[:space:]]' "${SUT}"
}

@test "acadia-pst-init.sh: adopts existing directories (chown+chmod, no content changes)" {
    # The helper must chown + chmod unconditionally (adopting dirs istate or
    # a previous boot created), and must not rm/mv anything.
    grep -qE 'chown[[:space:]]+"\$\{user\}:instr"[[:space:]]+"\$\{path\}"' "${SUT}"
    grep -qE 'chmod[[:space:]]+2770[[:space:]]+"\$\{path\}"' "${SUT}"
    ! grep -qE '(rm|mv)[[:space:]]' "${SUT}"
}

@test "acadia-pst-init.sh: provisions all four spoke store dirs" {
    grep -qF 'prepare instr-alarms     state/alarms' "${SUT}"
    grep -qF 'prepare instr-logmanager state/logs' "${SUT}"
    grep -qF 'prepare instr-ota        state/ota' "${SUT}"
    grep -qF 'prepare instr-backup     backup' "${SUT}"
}

@test "acadia-pst-init.sh: does not pre-create istate-owned trees" {
    # /pst/system and /pst/state/spool belong to istate (protected config
    # tree must stay istate-only writable).  Only comments may mention them.
    ! grep -vE '^[[:space:]]*#' "${SUT}" | grep -qE 'system|spool'
}