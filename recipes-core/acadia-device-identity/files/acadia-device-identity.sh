#!/bin/sh
set -eu

IDENTITY_DIR=/var/lib/acadia
IDENTITY_FILE=${IDENTITY_DIR}/device-id
SERIAL_FILE=/sys/firmware/devicetree/base/serial-number

if [ ! -r "${SERIAL_FILE}" ]; then
    logger -t acadia-device-identity "device-tree serial is unavailable" || true
    exit 0
fi

serial=$(od -An -tx1 -v "${SERIAL_FILE}" | tr -d ' \n')
if [ -z "${serial}" ]; then
    logger -t acadia-device-identity "device-tree serial is empty" || true
    exit 0
fi

mkdir -p "${IDENTITY_DIR}"
chmod 0750 "${IDENTITY_DIR}"

if [ ! -s "${IDENTITY_FILE}" ]; then
    printf '%s\n' "acadia-${serial}" > "${IDENTITY_FILE}"
    chmod 0640 "${IDENTITY_FILE}"
fi

logger -t acadia-device-identity "device identity initialized" || true
