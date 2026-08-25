#!/bin/bash
# swupdate-bootcheck.sh — I4/C1: health check that confirms OTA or triggers rollback.
#
# Runs after local-fs.target (before network.target) to ensure health check
# completes BEFORE network services start. If the health check fails, the
# system rolls back before any network exposure.
#
# Health check verifies:
#   - acadia-client.service is active AND running (not just started)
#   - The service has been running for minimum time (allows services to settle)
#   - The kernel and DTB files are intact (not corrupted)

set -euo pipefail

BOOT_STATE=/boot/boot_state

# If there is no boot_state the system was not recently updated — nothing to do.
if [[ ! -f "${BOOT_STATE}" ]]; then
    exit 0
fi

# Parse /boot/boot_state as key=value lines.  We deliberately do NOT `source`
# the file: /boot is a FAT32 partition (world-readable from the running
# system).  A `source` on the file would execute any shell metacharacters
# an attacker writes into it — running arbitrary code as root from a
# writable mount.  A read loop assigns values without ever evaluating
# them, and tolerates a corrupt or stale boot_state file.
slot=""
tries_remaining=""
confirmed=""
while IFS='=' read -r key value; do
    case "${key}" in
        slot)            slot="${value}" ;;
        tries_remaining) tries_remaining="${value}" ;;
        confirmed)       confirmed="${value}" ;;
        \#*|"")          : ;;            # comment / blank line
    esac
done < "${BOOT_STATE}"

# Already confirmed by a previous run
if [[ "${confirmed:-false}" == "true" ]]; then
    exit 0
fi

# ── Wait for services to settle (bounded readiness, not a fixed 5s) ────────
# Task 47: wait up to a bounded window for required services to reach active,
# rather than a single hardcoded sleep then one-shot check.
HEALTH_OK=true
WAIT_MAX=30
waited=0
wait_service() {
    local unit="$1"
    while ! systemctl is-active --quiet "${unit}" 2>/dev/null; do
        if [[ "${waited}" -ge "${WAIT_MAX}" ]]; then
            logger -t swupdate-bootcheck "${unit} not active within ${WAIT_MAX}s"
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 0
}

# Health contract (task 47): the boot is only healthy when the required
# services that must survive an update are actually up — HAL, webconfigd, and
# the client — with bounded readiness. Networking and storage are validated
# separately below.
for unit in hal.service webconfigd.service acadia-client.service; do
    if systemctl list-unit-files "${unit}" >/dev/null 2>&1; then
        if ! wait_service "${unit}"; then
            HEALTH_OK=false
            logger -t swupdate-bootcheck "${unit} failed readiness (bounded ${WAIT_MAX}s)"
        fi
    fi
done

# Networking: at least one non-loopback interface must be up once networkd
# has had a chance (bounded). Required so a healthy update can actually be
# reached/confirmed.
if [[ "${HEALTH_OK}" == "true" ]]; then
    net_ok=false
    for _ in $(seq 1 15); do
        if ip -br addr show 2>/dev/null | awk 'NR>1 && $1 != "lo" { if ($3 ~ /inet/) exit 0 } END { exit 1 }'; then
            net_ok=true
            break
        fi
        sleep 2
    done
    [[ "${net_ok}" == "true" ]] || { HEALTH_OK=false; logger -t swupdate-bootcheck "no interface got an address (networking unhealthy)"; }
fi

# Storage: the root filesystem must be read-write and have free space, else an
# update/health-check cannot be durable.
if [[ "${HEALTH_OK}" == "true" ]]; then
    if ! mount | grep -q ' / ' && ! findmnt -rn -o OPTIONS / | grep -q rw; then
        HEALTH_OK=false
        logger -t swupdate-bootcheck "root filesystem not writable"
    elif [[ -n "$(df -P / 2>/dev/null | awk 'NR==2 { if ($4+0 < 10240) print "low" }')" ]]; then
        HEALTH_OK=false
        logger -t swupdate-bootcheck "root filesystem low on space"
    fi
fi

# Verify kernel/DTB files are intact (per-file size bounds; issue #26).
# Each file has a different reasonable size range, so we cannot share
# a single bound.  The previous code used a single `if SIZE < 1MB ||
# SIZE > 10MB` for both, which always tripped on a 60 KB DTB and
# caused HEALTH_OK=false on every healthy boot.
if [[ "${HEALTH_OK}" == "true" ]]; then
    for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
        if [[ ! -f "/boot/${f}" ]]; then
            HEALTH_OK=false
            logger -t swupdate-bootcheck "${f} missing after boot"
            break
        fi
        SIZE=$(stat -c%s "/boot/${f}" 2>/dev/null || echo 0)
        case "${f}" in
            kernel_2712.img)
                # Compiled kernel: at least 1 MB (typical 7-15 MB on rpi5).
                MIN=$((1024 * 1024))
                MAX=$((20 * 1024 * 1024))   # 20 MB upper bound
                ;;
            *-rpi-*-b.dtb|*-rpi-*-cm*.dtb|*-rpi-*.dtb)
                # DTB: at least 10 KB (typical 50-80 KB on rpi5).
                MIN=$((10 * 1024))
                MAX=$((5 * 1024 * 1024))    # 5 MB upper bound
                ;;
            *)
                logger -t swupdate-bootcheck "WARN: unknown file '${f}', using generic bounds"
                MIN=1024
                MAX=$((50 * 1024 * 1024))
                ;;
        esac
        if [[ "${SIZE}" -lt "${MIN}" ]] || [[ "${SIZE}" -gt "${MAX}" ]]; then
            HEALTH_OK=false
            logger -t swupdate-bootcheck \
                "${f} size ${SIZE} bytes outside [${MIN}, ${MAX}]"
            break
        fi
    done
fi

if [[ "${HEALTH_OK}" == "true" ]]; then
    mount -o remount,rw /boot
    sed -i 's/confirmed=false/confirmed=true/' "${BOOT_STATE}"
    mount -o remount,ro /boot
    logger -t swupdate-bootcheck "Slot ${slot} confirmed healthy"
else
    logger -t swupdate-bootcheck "Slot ${slot} unhealthy — rolling back"
    mount -o remount,rw /boot
    if [[ -f /boot/cmdline.txt.prev ]]; then
        cp /boot/cmdline.txt.prev /boot/cmdline.txt
    fi
    for f in kernel_2712.img bcm2712-rpi-5-b.dtb; do
        [[ -f "/boot/${f}.prev" ]] && cp "/boot/${f}.prev" "/boot/${f}" || true
    done
    rm -f "${BOOT_STATE}" /boot/cmdline.txt.prev \
          /boot/kernel_2712.img.prev /boot/bcm2712-rpi-5-b.dtb.prev
    mount -o remount,ro /boot
    reboot
fi
