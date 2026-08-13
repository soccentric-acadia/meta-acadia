# Harden the OpenSSH server: key-based auth only, no passwords, no root login.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://acadia-hardening.conf"

do_install:append() {
    install -d ${D}${sysconfdir}/ssh/sshd_config.d
    install -m 0644 ${WORKDIR}/acadia-hardening.conf \
                    ${D}${sysconfdir}/ssh/sshd_config.d/acadia-hardening.conf

    # Prepend Include directive to sshd_config if not already present.
    # Issue #59: the previous grep matched commented-out Include
    # directives too (`# Include /etc/ssh/sshd_config.d/*.conf`),
    # so a commented-out upstream Include caused our hardening
    # drop-in to be silently skipped.  The anchored grep below
    # only matches an *active* Include directive.
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' \
            ${D}${sysconfdir}/ssh/sshd_config 2>/dev/null; then
        sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n|' \
            ${D}${sysconfdir}/ssh/sshd_config || true
    fi

    # Post-install sanity check (issue #59): assert the Include line
    # is actually reachable in the parsed config.  We can't run
    # `sshd -T` at build time (no host key in the sysroot), but if
    # the directive is missing now, sshd at boot will silently
    # ignore the hardening drop-in.  Fail loudly.
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' \
            ${D}${sysconfdir}/ssh/sshd_config; then
        bbfatal "openssh bbappend: failed to insert Include directive — acadia-hardening.conf will not be loaded."
    fi
}

FILES:${PN} += "${sysconfdir}/ssh/sshd_config.d/"
