#!/usr/bin/env bats
# test_sshd_include.bats — regression test for the openssh bbappend's
# Include-directive insertion logic.
#
# Issue #59: the previous grep `'Include.*sshd_config\.d'` matched
# commented-out Include directives too.  When upstream sshd_config
# shipped a `# Include /etc/ssh/sshd_config.d/*.conf` comment on the
# first line, the recipe saw the comment, skipped the prepend, and
# acadia-hardening.conf was silently ignored at boot.  Password auth
# would have been re-enabled on every Acadia device in the field.
#
# The fix:
#   1. Anchor the grep with `^[[:space:]]*Include[[:space:]]+` so
#      it only matches an *active* (uncommented) Include directive.
#   2. After the sed prepend, re-grep and `bbfatal` if the Include
#      line is still missing — fail loudly at build time.
#
# This test inlines the shell logic from the bbappend's do_install
# (without the BitBake variables) and verifies both halves on
# realistic upstream sshd_config inputs.

setup() {
    TMP=$(mktemp -d)
}

teardown() {
    rm -rf "${TMP}"
}

# Inline copy of the do_install logic.  Returns 0 if the Include
# directive is present after the run; non-zero otherwise (which the
# bbappend turns into bbfatal).  The bbappend uses $D${sysconfdir}/ssh
# — we use $TMP here.
ensure_include() {
    local cfg="$1"
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' \
            "${cfg}" 2>/dev/null; then
        sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n|' "${cfg}" || true
    fi
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' \
            "${cfg}"; then
        return 1
    fi
    return 0
}

@test "sshd_config with no Include at all: prepend works" {
    cat > "${TMP}/sshd_config" <<'CFG'
# Default OpenSSH server config
Port 22
PermitRootLogin yes
PasswordAuthentication yes
CFG
    ensure_include "${TMP}/sshd_config"
    head -1 "${TMP}/sshd_config" | grep -qE '^[[:space:]]*Include[[:space:]]'
}

@test "sshd_config with COMMENTED-OUT Include: prepend works (issue #59)" {
    # This is the bug case.  Upstream sshd_config in some distros
    # ships a commented Include; the OLD grep matched the comment
    # and skipped the prepend.
    cat > "${TMP}/sshd_config" <<'CFG'
# Include /etc/ssh/sshd_config.d/*.conf
Port 22
PermitRootLogin yes
PasswordAuthentication yes
CFG
    ensure_include "${TMP}/sshd_config"
    # The Include line must now be present AND not commented out.
    head -1 "${TMP}/sshd_config" | grep -qE '^[[:space:]]*Include[[:space:]]'
}

@test "sshd_config with ACTIVE Include on first line: prepend is skipped" {
    # No-op case: the Include is already there and active.  The
    # bbappend must not insert a second Include (sed prepends a
    # line that gets added to the top, but the active grep guard
    # would prevent this — verify the guard works).
    cat > "${TMP}/sshd_config" <<'CFG'
Include /etc/ssh/sshd_config.d/*.conf
Port 22
PermitRootLogin yes
CFG
    ensure_include "${TMP}/sshd_config"
    # The Include should still be on the first line (not duplicated).
    head -1 "${TMP}/sshd_config" | grep -qE '^Include[[:space:]]'
    # And no second Include.
    [ "$(grep -cE '^[[:space:]]*Include[[:space:]]' "${TMP}/sshd_config")" = "1" ]
}

@test "sshd_config with ACTIVE Include on a non-first line: prepend is skipped" {
    cat > "${TMP}/sshd_config" <<'CFG'
# Default OpenSSH server config
Port 22
PermitRootLogin yes
Include /etc/ssh/sshd_config.d/*.conf
CFG
    ensure_include "${TMP}/sshd_config"
    [ "$(grep -cE '^[[:space:]]*Include[[:space:]]' "${TMP}/sshd_config")" = "1" ]
}

@test "sshd_config with Indented Include (leading whitespace): prepend is skipped" {
    # `case "${f}"` of grep regex matches `^[[:space:]]*` so
    # indented Include directives count as active.
    cat > "${TMP}/sshd_config" <<'CFG'
# Default
	Include /etc/ssh/sshd_config.d/*.conf
Port 22
CFG
    ensure_include "${TMP}/sshd_config"
    # No new first-line Include prepended (the existing one counts).
    head -1 "${TMP}/sshd_config" | grep -qE '^#'
}

@test "sshd_config with whitespace-only lines: prepend works" {
    # Edge case: sshd_config has only blank lines.  `sed -i '1s|^|...'`
    # substitutes the first blank line.  The Include directive is on
    # line 1 and the rest of the file is preserved.
    printf '\n\n\n' > "${TMP}/sshd_config"
    ensure_include "${TMP}/sshd_config"
    head -1 "${TMP}/sshd_config" | grep -qE '^Include[[:space:]]'
}

@test "sshd_config with Include mentioning sshd_config.d in a string: prepend works" {
    # Edge case: sshd_config has a comment with the substring
    # "Include ... sshd_config.d" but it's not an active directive.
    # The OLD unanchored grep would have matched and skipped; the
    # NEW anchored grep must not.
    cat > "${TMP}/sshd_config" <<'CFG'
# Setting "Include" in a comment about sshd_config.d is harmless
Port 22
PasswordAuthentication yes
CFG
    ensure_include "${TMP}/sshd_config"
    head -1 "${TMP}/sshd_config" | grep -qE '^[[:space:]]*Include[[:space:]]'
}
