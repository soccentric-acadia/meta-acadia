#!/bin/bash
# acadia-provision-identity — factory provisioning tool (T-P09, A01/A02/C02).
#
# Writes the per-device factory record the whole stack consumes:
#
#   /pst/factory/identity/identity.yaml   root:instr 0640 — serial,
#       hw_revision, board_variant, mfg_date, hostname_base, claim_code
#   /pst/factory/identity/.secret         root:instr 0640 — 32 random bytes
#       (hex); the class secret Instrumentation derives backup keys and
#       provisioning HMACs from (INS native.cpp::read_factory_identity).
#
# The claim code rides in identity.yaml AND is mirrored to the WebConfig
# store (/pst/webconfig/claim-code, webconfig:webconfig 0600) so the
# first-boot admin claim (T-P10) can verify it without group instr. The
# claim code's security is possession (printed on the device label), not
# filesystem secrecy from the webconfig user itself.
#
# Modes:
#   (default)            on-device first-boot provisioning — writes under
#                        /pst; intended for the one-shot systemd unit.
#   --root <dir>         line-station mode: provision a target /pst mounted
#                        (or bind-mounted) at <dir>.
#   --print              print the existing record's label, write nothing.
#   --serial <s>         explicit serial (default: DT serial-number if
#                        present, else a generated one).
#   --force              refuse nothing: overwrite an existing record.
#
# Refuses to touch anything when a valid record already exists (idempotent,
# fail-closed — factory identity is write-once). Exit 0 only when a record
# exists after the run (pre-existing or freshly written).

set -euo pipefail

ROOT=""
SERIAL_ARG=""
FORCE=0
PRINT_ONLY=0

usage() { echo "usage: acadia-provision-identity [--root DIR] [--serial S] [--force] [--print]"; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)   ROOT="$2"; shift 2;;
        --serial) SERIAL_ARG="$2"; shift 2;;
        --force)  FORCE=1; shift;;
        --print)  PRINT_ONLY=1; shift;;
        *)        usage;;
    esac
done

BASE="${ROOT:-}/pst/factory/identity"

log() { logger -t acadia-provision-identity "$*"; }

WC_DIR="${ROOT:-}/pst/webconfig"

# T-P33: the claim-code mirror must exist whenever the record does. A
# settings+users or full (RMA) factory reset reopens first-boot; without the
# mirror first-boot would be claimable by anyone on the network instead of
# by whoever holds the label. Re-mirrored from the write-once record.
remirror_claim_code() {
    [[ -d "${WC_DIR}" && ! -f "${WC_DIR}/claim-code" ]] || return 0
    local code
    code="$(sed -n 's/^claim_code:[[:space:]]*//p' "${BASE}/identity.yaml" | head -n1)"
    [[ -n "${code}" ]] || return 0
    printf '%s' "${code}" > "${WC_DIR}/claim-code"
    chmod 0600 "${WC_DIR}/claim-code"
    chown webconfig:webconfig "${WC_DIR}/claim-code" 2>/dev/null || true
    log "claim-code mirror restored in ${WC_DIR}"
}

# ── existing record? ────────────────────────────────────────────────────────
if [[ -f "${BASE}/identity.yaml" && -f "${BASE}/.secret" && "$PRINT_ONLY" == 0 && "$FORCE" == 0 ]]; then
    remirror_claim_code
    log "identity already present at ${BASE} — write-once, nothing to do"
    exit 0
fi

if [[ "$PRINT_ONLY" == 1 ]]; then
    [[ -f "${BASE}/identity.yaml" ]] || { echo "no identity at ${BASE}" >&2; exit 1; }
    cat "${BASE}/identity.yaml"
    exit 0
fi

# ── inputs ──────────────────────────────────────────────────────────────────
if [[ -n "${SERIAL_ARG:-}" ]]; then
    SERIAL="$SERIAL_ARG"
elif [[ -r /proc/device-tree/serial-number ]]; then
    SERIAL="$(tr -d '\0' < /proc/device-tree/serial-number)"
elif [[ -r /sys/firmware/devicetree/base/serial-number ]]; then
    SERIAL="$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number)"
else
    # Fallback: 12 hex digits from the kernel RNG (line stations pass
    # --serial for barcode-tracked units; this path is for bring-up).
    SERIAL="AC$(head -c 5 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
if [[ ! "$SERIAL" =~ ^[A-Za-z0-9_-]{4,32}$ ]]; then
    echo "refusing to provision: serial '$SERIAL' outside [A-Za-z0-9_-]{4,32}" >&2
    exit 1
fi

MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
case "$MODEL" in
    *Raspberry\ Pi\ 5*|*BCM2712*) VARIANT="rpi-5";;
    *Compute\ Module\ 5*|*CM5*)   VARIANT="cm5";;
    *)                            VARIANT="generic";;
esac

HW_REV="1.0"
MFG_DATE="$(date -u +%Y-%m-%d)"
# hostname_base drives the default hostname (hostname = base + "-" + last 4
# of serial) — deterministic and label-printable.
HOSTNAME_BASE="acadia"
CLAIM="$(head -c 8 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 8)"
SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# ── write ───────────────────────────────────────────────────────────────────
# Issue #44 precedent (rpi5-home-init): busybox `install` drops -o/-g; use
# mkdir + chown + chmod explicitly. The tool runs as root (unit or station).
mkdir -p "$BASE"
chmod 0750 "$BASE"
chown root:instr "$BASE" 2>/dev/null || true

cat > "${BASE}/identity.yaml" <<EOF
serial: $SERIAL
hw_revision: $HW_REV
board_variant: $VARIANT
mfg_date: $MFG_DATE
hostname_base: $HOSTNAME_BASE
claim_code: $CLAIM
EOF
chmod 0640 "${BASE}/identity.yaml"
chown root:instr "${BASE}/identity.yaml" 2>/dev/null || true

printf '%s' "$SECRET" > "${BASE}/.secret"
chmod 0640 "${BASE}/.secret"
chown root:instr "${BASE}/.secret" 2>/dev/null || true

# Claim-code mirror for the first-boot admin claim (T-P10).
if [[ -d "$WC_DIR" ]]; then
    printf '%s' "$CLAIM" > "${WC_DIR}/claim-code"
    chmod 0600 "${WC_DIR}/claim-code"
    chown webconfig:webconfig "${WC_DIR}/claim-code" 2>/dev/null || true
fi

log "provisioned serial=$SERIAL variant=$VARIANT at ${BASE}"

# ── label ───────────────────────────────────────────────────────────────────
cat <<EOF
==== Acadia device label ====
serial:        $SERIAL
board:         $VARIANT
hw revision:   $HW_REV
mfg date:      $MFG_DATE
hostname:      ${HOSTNAME_BASE}-${SERIAL: -4}
claim code:    $CLAIM
secret:        (provisioned to ${BASE}/.secret — do not print on the label)
EOF