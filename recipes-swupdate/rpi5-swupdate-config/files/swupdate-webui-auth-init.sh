#!/bin/bash
# swupdate-webui-auth-init.sh — I7: generate web UI credentials on first boot.
# Writes /etc/swupdate/webui.passwd in Mongoose MD5-digest htpasswd format.
# Skips if the file already exists (idempotent).

set -euo pipefail

PASSWD_FILE=/etc/swupdate/webui.passwd
REALM=acadia
USER=admin

if [[ -f "${PASSWD_FILE}" ]]; then
    exit 0
fi

# Generate a random 12-char base64 password
PASSWORD=$(openssl rand -base64 12 | tr -d '=+/' | head -c 12)

# Mongoose htpasswd uses MD5(user:realm:password)
HASH=$(printf '%s:%s:%s' "${USER}" "${REALM}" "${PASSWORD}" | md5sum | awk '{print $1}')

install -d "$(dirname "${PASSWD_FILE}")"
printf '%s:%s:%s\n' "${USER}" "${REALM}" "${HASH}" > "${PASSWD_FILE}"
chmod 0600 "${PASSWD_FILE}"

# ── Announce credentials ────────────────────────────────────────────────────
# Security policy (issue #31): the plaintext password is NEVER written to
# the systemd journal — only the fact that a credential was generated is
# logged, and the password itself is written to /dev/console ONCE.
#
# Why a one-shot reveal: the password is auto-generated and there is no
# other channel to deliver it to the operator.  The previous code echoed
# it both to /dev/console and to the journal, which means anyone with
# `journalctl` access (which on this system is anyone with read access to
# /var/log/journal — i.e. the systemd-journal group) could read the
# admin password for the SWUpdate web UI.  The new code writes the
# password only to the kernel console device, where the operator is
# expected to read it on first boot, and never persists it.
#
# The operator is expected to:
#   1. Read /dev/console (HDMI by default; serial if console=ttyAMA0,...
#      in cmdline.txt — whichever console= picks).
#   2. Log in via SSH as 'rpi'.
#   3. Change the password through the web UI on first login.
#
# /dev/console is the kernel's active console device.  We redirect via
# `cat` so the redirect itself can't fail the unit on a vanished console.

{
    printf '\n--- swupdate web UI first-boot credentials ---\n'
    printf '  user:     %s\n' "${USER}"
    printf '  password: %s\n' "${PASSWORD}"
    printf '  realm:    %s\n' "${REALM}"
    printf '  htpasswd: %s\n' "${PASSWD_FILE}"
    printf '  >>> CHANGE THE PASSWORD AFTER FIRST LOGIN <<<\n'
    printf '---------------------------------------------------\n'
} > /dev/console 2>/dev/null || true

# Log the fact (not the password) to the journal so an operator
# investigating "I can't log in" can find the credential location.
logger -t swupdate-webui-auth -p auth.info \
    "Credentials generated for user=${USER} realm=${REALM}; see ${PASSWD_FILE} (password not logged)" || true
