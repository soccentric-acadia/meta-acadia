#!/bin/sh
set -eu

ROOT=${ACADIA_ROOT:-}
IDENTITY_DIR=${ROOT}/pst/acadia
IDENTITY_FILE=${IDENTITY_DIR}/device-id
# Backward-compatible runtime view consumed by Acadia-Client. The canonical
# record above is persistent; this mirror is recreated on each boot so an A/B
# rootfs switch cannot change the identity.
COMPAT_IDENTITY_DIR=${ROOT}/var/lib/acadia
COMPAT_IDENTITY_FILE=${COMPAT_IDENTITY_DIR}/device-id
FACTORY_IDENTITY=${ROOT}/pst/factory/identity/identity.yaml
SERIAL_FILE=${ROOT}/sys/firmware/devicetree/base/serial-number

# The factory record is write-once and survives both OTA slots. It is the
# canonical source for every component; device-tree serial is only a
# pre-provisioning fallback.
serial=""
if [ -r "${FACTORY_IDENTITY}" ]; then
    serial=$(sed -n 's/^serial:[[:space:]]*//p' "${FACTORY_IDENTITY}" | head -n1 | tr -d '[:space:]')
elif [ -r "${SERIAL_FILE}" ]; then
    serial=$(tr -d '\000[:space:]' < "${SERIAL_FILE}")
fi
if [ -z "${serial}" ]; then
    logger -t acadia-device-identity "factory and device-tree serial are unavailable" || true
    exit 0
fi

mkdir -p "${IDENTITY_DIR}"
chmod 0750 "${IDENTITY_DIR}"

if [ ! -s "${IDENTITY_FILE}" ]; then
    temporary="${IDENTITY_FILE}.new"
    printf '%s\n' "acadia-${serial}" > "${temporary}"
    chmod 0640 "${temporary}"
    mv -f "${temporary}" "${IDENTITY_FILE}"
fi

mkdir -p "${COMPAT_IDENTITY_DIR}"
chmod 0750 "${COMPAT_IDENTITY_DIR}"
temporary="${COMPAT_IDENTITY_FILE}.new"
cat "${IDENTITY_FILE}" > "${temporary}"
chmod 0640 "${temporary}"
mv -f "${temporary}" "${COMPAT_IDENTITY_FILE}"

logger -t acadia-device-identity "device identity initialized" || true
