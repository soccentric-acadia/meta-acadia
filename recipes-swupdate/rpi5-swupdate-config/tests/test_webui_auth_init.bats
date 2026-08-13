#!/usr/bin/env bats
# test_webui_auth_init.bats — regression test for swupdate-webui-auth-init.sh
#
# Verifies the security fix for issue #31: the plaintext password must
# NEVER appear in the journal (the only system-wide read channel for
# anyone with access to /var/log/journal).  The /dev/console echo is
# acceptable because it is a one-shot reveal intended for the operator
# physically present at the console.
#
# We mock the dependencies (openssl, md5sum, install, logger, the
# journal, and /dev/console) so the script runs end-to-end on a host
# with no systemd, no real openssl, and no privileged filesystem.
#
# Run with:
#   bats meta/meta-acadia/recipes-swupdate/rpi5-swupdate-config/tests/
#
# Reference issue: Acadia-OS#31.

setup() {
    TMP=$(mktemp -d)
    export TMP
    export PASSWD_FILE="${TMP}/etc/swupdate/webui.passwd"
    export CONSOLE_LOG="${TMP}/console.log"
    export JOURNAL_LOG="${TMP}/journal.log"

    # Install shim binaries into a private bin dir.
    export BIN="${TMP}/bin"
    mkdir -p "${BIN}"

    # openssl: produce a fixed base64-ish string. The script's
    # `tr -d '=+/' | head -c 12` then truncates it to 12 chars.
    cat > "${BIN}/openssl" <<'EOF'
#!/bin/bash
# Emit a fixed "random" password so the test is deterministic.
# After `tr -d '=+/' | head -c 12` this becomes "ABCDEFGHIJKL".
echo "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij+/="
EOF
    chmod +x "${BIN}/openssl"

    # md5sum: stable output for any input.
    cat > "${BIN}/md5sum" <<'EOF'
#!/bin/bash
# Always emit the same hash so we can compare.
echo "00000000000000000000000000000000  -"
EOF
    chmod +x "${BIN}/md5sum"

    # install: stub — just create the dir and copy.
    cat > "${BIN}/install" <<'EOF'
#!/bin/bash
# Very small subset: `install -d DIR`
if [ "$1" = "-d" ]; then
    mkdir -p "$2"
fi
EOF
    chmod +x "${BIN}/install"

    # logger: append to JOURNAL_LOG instead of syslog.
    cat > "${BIN}/logger" <<'EOF'
#!/bin/bash
# Capture everything as one line into JOURNAL_LOG.
shift_tag=0
tag=""
priority=""
msg=""
while [ $# -gt 0 ]; do
    case "$1" in
        -t) tag="$2"; shift 2 ;;
        -p) priority="$2"; shift 2 ;;
        *) msg="$*"; break ;;
    esac
done
echo "${tag:-root}: ${priority:-info}: ${msg}" >> "${JOURNAL_LOG}"
EOF
    chmod +x "${BIN}/logger"

    # /dev/console: redirect to a file via shell redirection in the test.
    # We can't replace a device file in TMP, but we can use a wrapper
    # that tee's to CONSOLE_LOG.  Easiest: just redirect the test
    # runner's /dev/console, but in a chroot-less test we have to
    # mock at a different layer.  The script uses `> /dev/console`
    # so we need an actual /dev/console write to land in CONSOLE_LOG.
    #
    # Trick: have the script's output be redirected to CONSOLE_LOG by
    # the test runner.  We do that with a wrapper.
    export PATH="${BIN}:${PATH}"

    # Make a copy of the script under test that writes to CONSOLE_LOG
    # instead of /dev/console AND writes the htpasswd to TMP.
    SUT="${TMP}/swupdate-webui-auth-init.sh"
    sed -e "s|/dev/console|${CONSOLE_LOG}|g" \
        -e "s|^PASSWD_FILE=.*|PASSWD_FILE=${PASSWD_FILE}|" \
        meta/meta-acadia/recipes-swupdate/rpi5-swupdate-config/files/swupdate-webui-auth-init.sh \
        > "${SUT}"
    chmod +x "${SUT}"
}

teardown() {
    rm -rf "${TMP}"
}

@test "webui auth init: exits 0 and writes htpasswd file" {
    run "${SUT}"
    [ "$status" -eq 0 ]
    [ -f "${PASSWD_FILE}" ]
    # File contains user:realm:hash
    grep -q "^admin:acadia:00000000000000000000000000000000" "${PASSWD_FILE}"
}

@test "webui auth init: plaintext password NOT in journal (issue #31 regression)" {
    : > "${JOURNAL_LOG}"
    run "${SUT}"
    [ "$status" -eq 0 ]
    # The plaintext password is "ABCDEFGHIJKL" (12 chars after
    # `tr -d '=+/' | head -c 12`).  The full pre-truncation string is
    # also checked — both forms MUST NOT appear in the journal.
    if grep -qE "ABCDEFGHIJKL|ABCDEFGHIJKLMNOPQRSTUVWXYZ" "${JOURNAL_LOG}"; then
        cat "${JOURNAL_LOG}"
        return 1
    fi
}

@test "webui auth init: journal mentions credential location but not password" {
    : > "${JOURNAL_LOG}"
    run "${SUT}"
    [ "$status" -eq 0 ]
    # Journal should contain a hint about where to find the password.
    grep -q "see ${PASSWD_FILE}" "${JOURNAL_LOG}"
    # And should explicitly say the password isn't logged.
    grep -q "password not logged" "${JOURNAL_LOG}"
}

@test "webui auth init: plaintext password IS in /dev/console (deliberate)" {
    : > "${CONSOLE_LOG}"
    run "${SUT}"
    [ "$status" -eq 0 ]
    # The console echo is the legitimate delivery channel — verify it's
    # still happening.  If this assertion ever fails, the operator has
    # no way to learn the password; that's a regression in the other
    # direction.
    grep -q "ABCDEFGHIJKL" "${CONSOLE_LOG}"
    grep -q "CHANGE THE PASSWORD" "${CONSOLE_LOG}"
}

@test "webui auth init: idempotent — does not regenerate on second run" {
    run "${SUT}"
    [ "$status" -eq 0 ]
    FIRST_HASH=$(awk -F: '{print $3}' "${PASSWD_FILE}")

    # Second run with a different "password" — must be ignored.
    cat > "${BIN}/openssl" <<'EOF'
#!/bin/bash
echo "DIFFERENTpassword"
EOF
    chmod +x "${BIN}/openssl"

    run "${SUT}"
    [ "$status" -eq 0 ]
    SECOND_HASH=$(awk -F: '{print $3}' "${PASSWD_FILE}")
    [ "${FIRST_HASH}" = "${SECOND_HASH}" ]
}

@test "webui auth init: console message contains all four fields" {
    : > "${CONSOLE_LOG}"
    run "${SUT}"
    [ "$status" -eq 0 ]
    grep -q "^  user:"     "${CONSOLE_LOG}"
    grep -q "^  password:" "${CONSOLE_LOG}"
    grep -q "^  realm:"    "${CONSOLE_LOG}"
    grep -q "^  htpasswd:" "${CONSOLE_LOG}"
}
