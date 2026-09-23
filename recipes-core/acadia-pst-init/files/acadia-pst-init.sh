#!/bin/bash
# acadia-pst-init — prepare the freshly mounted /pst partition (task 003).
#
# /pst (p4, label "pst") is created empty by the WIC image, so mounting it
# hides the rootfs-side skeleton — exactly like /home before
# rpi5-home-init.  istate is the /pst owner (R4) and creates its own
# layout, but the /pst consumers run as five distinct users sharing group
# `instr`, and their unit files pin ReadWritePaths=/pst/<subdir> under
# ProtectSystem=strict (a missing path is a start failure).  This script
# therefore provisions ownership and per-spoke store directories BEFORE
# istate starts:
#
#   /pst                 instr-istate:instr      2770 (setgid → group inherited)
#   /pst/state           instr-istate:instr      2770
#   /pst/state/alarms    instr-alarms:instr      2770
#   /pst/state/logs      instr-logmanager:instr  2770
#   /pst/state/ota       instr-ota:instr         2770
#   /pst/backup          instr-backup:instr      2770
#
# T-P01: /pst/webconfig          webconfig:webconfig    2770 — the WebConfig
# daemon's data_dir (config store, web-UI users, HQ pairing credential, TLS
# identity). Prepared INDEPENDENTLY of the instr-istate early-exit: webconfigd
# ships on every machine (cm5 included, which has no Instrumentation). The
# one-time migration below also adopts pre-T-P01 state from the A/B-rootfs
# legacy directories (/var/lib/webconfig, /data/webconfig) into /pst/webconfig
# on the first boot after the upgrade, so users, pairing and TLS survive the
# slot switch that carries this change.
#
# /pst/system and /pst/state/spool are deliberately NOT created here: they
# belong to istate, which creates them itself (0755, group read-only) —
# the protected system config tree must stay istate-only writable.
#
# Idempotent: existing directories are only chowned/chmod'ed to match the
# contract; content is never touched.  Safe to re-run on every boot.
#
# Issue #44 precedent (rpi5-home-init): busybox `install` silently drops
# -o/-g, so ownership is always applied with mkdir + chown + chmod.

set -euo pipefail

# Overridable for the sandboxed functional test (scripts/test-acadia-pst-init
# style harnesses); production always uses the /pst default.
MNT="${ACADIA_PST_MNT:-/pst}"

if ! findmnt -n "${MNT}" >/dev/null; then
    # Old 4-partition layout: pst.mount skipped, /pst is a plain rootfs
    # directory.  Leave it to istate exactly as before this task.
    logger -t acadia-pst-init "no ${MNT} mount (old layout) — skipping."
    exit 0
fi

logger -t acadia-pst-init "preparing ${MNT} ownership and layout."

# --- T-P01: WebConfig persistent state --------------------------------------
# Runs before the instr-istate early-exit: webconfigd is installed on every
# Acadia machine, Instrumentation is not.
prepare_webconfig() {
    getent passwd webconfig >/dev/null || return 0
    local path="${MNT}/webconfig"
    if [[ ! -d "${path}" ]]; then
        mkdir -m 2770 "${path}"
    fi
    chown webconfig:webconfig "${path}"
    chmod 2770 "${path}"
    logger -t acadia-pst-init "${path} prepared for webconfig."
}

# One-time migration of pre-T-P01 WebConfig state.  The old daemon resolved
# its store to /data/webconfig (never writable under the sandbox) while the
# recipes provisioned /var/lib/webconfig — whichever a deployment actually
# used is adopted into the persistent store, but only when /pst/webconfig is
# still empty (never overwrite real persistent data).
migrate_webconfig() {
    getent passwd webconfig >/dev/null || return 0
    local dst="${MNT}/webconfig" src
    [[ -d "${dst}" ]] || return 0
    [[ -z "$(ls -A "${dst}" 2>/dev/null)" ]] || return 0
    for src in /var/lib/webconfig /data/webconfig; do
        if [[ -d "${src}" && -n "$(ls -A "${src}" 2>/dev/null)" ]]; then
            cp -a "${src}/." "${dst}/"
            chown -R webconfig:webconfig "${dst}"
            logger -t acadia-pst-init "migrated ${src} → ${dst}"
            return 0
        fi
    done
}

prepare_webconfig
migrate_webconfig

if ! getent passwd instr-istate >/dev/null; then
    # Instrumentation not installed (e.g. cm5 today): keep a root-owned,
    # root-writable store; the daemons that would use it are absent anyway.
    chmod 0755 "${MNT}"
    logger -t acadia-pst-init "instr-istate not present — ${MNT} left root-owned."
    exit 0
fi

chown instr-istate:instr "${MNT}"
chmod 2770 "${MNT}"

mkdir -m 2770 -p "${MNT}/state"
chown instr-istate:instr "${MNT}/state"
chmod 2770 "${MNT}/state"

# prepare USER RELDIR — provision one per-spoke store directory (only when
# that daemon's user exists).  An existing directory (e.g. created by istate
# on an earlier boot) is adopted: chown + chmod, never content changes.
prepare() {
    local user="$1" rel="$2" path="${MNT}/$2"
    getent passwd "${user}" >/dev/null || return 0
    if [[ ! -d "${path}" ]]; then
        mkdir -m 2770 "${path}"
    fi
    chown "${user}:instr" "${path}"
    chmod 2770 "${path}"
    logger -t acadia-pst-init "${path} prepared for ${user}."
}

prepare instr-alarms     state/alarms
prepare instr-logmanager state/logs
prepare instr-ota        state/ota
prepare instr-backup     backup

logger -t acadia-pst-init "${MNT} persistent store ready."