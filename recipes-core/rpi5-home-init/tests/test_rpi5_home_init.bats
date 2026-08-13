#!/usr/bin/env bats
# test_rpi5_home_init.bats — regression test for the rpi5-home-init.sh
# homedir creation.
#
# Issue #44: the previous \`install -d -m 0750 -o USER -g USER DIR\`
# silently drops the -o/-g flags on busybox install.  The result
# is root:root ownership and the user cannot log in.  The fix
# replaces install with mkdir + chown, which is portable and
# deterministic.
#
# This test verifies:
#   1. The script no longer uses \`install -d -o/-g\` (the bug).
#   2. The script uses \`mkdir -m 0750\` + \`chown USER:USER DIR\`
#      (the fix).
#   3. The passwd parsing logic still filters out nologin/false
#      users and system accounts.

setup() {
    SUT="${BATS_TEST_DIRNAME}/../files/rpi5-home-init.sh"
    [ -f "${SUT}" ] || skip "rpi5-home-init.sh not found at ${SUT}"
}

@test "rpi5-home-init.sh: NO install -d -o/-g (issue #44)" {
    # The bug pattern: \`install -d ... -o USER ... -g USER ...\`
    # busybox install drops the -o/-g flags.
    ! grep -qE '^[[:space:]]*install[[:space:]]+.*-o[[:space:]]' "${SUT}"
    ! grep -qE '^[[:space:]]*install[[:space:]]+.*-g[[:space:]]' "${SUT}"
}

@test "rpi5-home-init.sh: uses mkdir -m 0750 for homedir" {
    # The fix: \`mkdir -m 0750 -p "${homedir}"\`
    grep -qE '^[[:space:]]*mkdir[[:space:]]+.*-m[[:space:]]+0750' "${SUT}"
}

@test "rpi5-home-init.sh: chown USER:USER homedir" {
    # The fix: \`chown "${username}:${username}" "${homedir}"\`
    # applied *before* cp -a (so /etc/skel content is owned by user
    # from creation, not after).
    grep -qE '^[[:space:]]*chown[[:space:]]+"\${username}:\${username}"[[:space:]]+"\${homedir}"' "${SUT}"
}

@test "rpi5-home-init.sh: skips nologin shell users" {
    # Defensive: \`[[ "${shell}" == */nologin ]] || [[ "${shell}" == */false ]]\`
    # This was the original behavior; verify it's still there.
    grep -qE 'shell.*nologin' "${SUT}"
    grep -qE 'shell.*false' "${SUT}"
}

@test "rpi5-home-init.sh: skips UID < 1000 (system accounts)" {
    grep -qE 'uid.*-lt[[:space:]]+1000' "${SUT}"
}

@test "rpi5-home-init.sh: skips users with homedir outside /home" {
    # Defensive: \`[[ "${homedir}" != /home/* ]] && continue\`
    # The \`!= /home/*\` pattern means "homedir is NOT under /home".
    grep -qF 'homedir}" != /home/' "${SUT}"
}

@test "rpi5-home-init.sh: /home/.home-initialised FLAG prevents re-run" {
    # First-boot idempotency: a FLAG file is touched on success.
    grep -qE '^FLAG=/home/\.home-initialised' "${SUT}"
    grep -qE 'touch[[:space:]]+"\${FLAG}"' "${SUT}"
}

@test "rpi5-home-init.sh: set -euo pipefail at the top" {
    # Defensive: any regression that introduces an unhandled error
    # will abort the script loudly.  Note: this is *not* a replacement
    # for input validation; the script is run as root and touches
    # /home, so silent partial-failure is the worst outcome.
    grep -qE '^set -euo pipefail' "${SUT}"
}
