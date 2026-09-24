#!/bin/bash
# acadia-factory-wipe — the device-wide factory reset contract (T-P33, C06/C07).
#
# Every reset that touches more than one owner's state is carried out HERE,
# once, at early boot — before any consumer (webconfigd, istate and its
# spokes, acadia-client, sshd) has opened a file. A running service only
# REQUESTS a reset by writing a request file and rebooting:
#
#   /pst/webconfig/factory-wipe.request   (written by webconfigd)
#
# The request is a small JSON object; only its "level" field is acted on:
#
#   "settings"  C06 — configuration back to image defaults, accounts and
#               identity kept. WebConfig has already reset its own store
#               in-process; this removes the Instrumentation config tree
#               (/pst/system) and runtime state (/pst/state) so istate
#               reseeds image defaults on start.
#   "full"      C07 / RMA — everything customer- or site-specific is wiped:
#               all of /pst except the write-once factory identity
#               (/pst/factory) — i.e. WebConfig store + accounts + TLS +
#               HQ pairing, Instrumentation config/state/backups — plus
#               every home directory (operator SSH keys, Acadia-Client data
#               and HQ credentials under /home/acadia), OTA staging and the
#               persistent journal. The device comes back in first-boot
#               state, claimable with the code on its factory label
#               (acadia-factory-provision re-mirrors it).
#
# Anything else in "level" is refused (logged, request kept for inspection,
# nothing wiped). Factory identity is never touched — re-provisioning is the
# separate manufacturing operation (istate `factory-reset`,
# acadia-provision-identity --force).
#
# The request file is removed only after a successful wipe, so a power cut
# mid-wipe repeats the wipe on the next boot. A record of the last wipe is
# kept in /pst/factory/last-wipe for RMA traceability.

set -euo pipefail

PST="${ACADIA_PST_MNT:-/pst}"
HOME_DIR="${ACADIA_HOME_MNT:-/home}"
VAR_ROOT="${ACADIA_VAR_ROOT:-}"
REQUEST="${PST}/webconfig/factory-wipe.request"

log() { logger -t acadia-factory-wipe "$*" 2>/dev/null || true; echo "acadia-factory-wipe: $*" >&2; }

[[ -e "${REQUEST}" ]] || exit 0
if [[ -L "${REQUEST}" || ! -f "${REQUEST}" ]]; then
    log "request ${REQUEST} is not a regular file — refusing, removing it"
    rm -f "${REQUEST}"
    exit 0
fi

# Plain-shell JSON field read: the file is tiny and written by webconfigd.
LEVEL="$(tr -d '\n' < "${REQUEST}" | sed -n 's/.*"level"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')"

# Remove every entry of a directory (dotfiles included) except the names
# given, without following symlinks out of it.
empty_dir_except() {
    local dir="$1"; shift
    [[ -d "${dir}" ]] || return 0
    local entry name keep k
    shopt -s nullglob dotglob
    for entry in "${dir}"/*; do
        name="${entry##*/}"
        keep=0
        for k in "$@"; do [[ "${name}" == "${k}" ]] && keep=1; done
        [[ "${keep}" == 1 ]] && continue
        rm -rf -- "${entry}"
    done
    shopt -u nullglob dotglob
}

case "${LEVEL}" in
    settings)
        log "settings reset: removing Instrumentation config and state"
        rm -rf -- "${PST}/system" "${PST}/state"
        ;;
    full)
        log "FULL WIPE (RMA): clearing /pst (except factory identity), /home, OTA staging, journal"
        empty_dir_except "${PST}" factory lost+found
        empty_dir_except "${HOME_DIR}" lost+found
        empty_dir_except "${VAR_ROOT}/var/lib/webconfig-ota"
        empty_dir_except "${VAR_ROOT}/var/log/journal"
        if [[ -d "${PST}/factory" ]]; then
            date -u +%Y-%m-%dT%H:%M:%SZ > "${PST}/factory/last-wipe"
        fi
        ;;
    *)
        log "unknown reset level '${LEVEL}' in ${REQUEST} — nothing wiped"
        exit 0
        ;;
esac

# The full wipe already removed the request with /pst/webconfig.
rm -f "${REQUEST}"
sync
log "${LEVEL} reset complete"
