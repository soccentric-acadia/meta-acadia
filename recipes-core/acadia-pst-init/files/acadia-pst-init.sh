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

MNT=/pst

if ! findmnt -n "${MNT}" >/dev/null; then
    # Old 4-partition layout: pst.mount skipped, /pst is a plain rootfs
    # directory.  Leave it to istate exactly as before this task.
    logger -t acadia-pst-init "no /pst mount (old layout) — skipping."
    exit 0
fi

logger -t acadia-pst-init "preparing ${MNT} ownership and layout."

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