SUMMARY = "Acadia persistent device identity"
DESCRIPTION = "Creates a stable device identity from the Raspberry Pi device-tree serial and machine-id for telemetry and attestation workflows."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-device-identity.service \
    file://acadia-device-identity.sh \
"

inherit allarch systemd

RDEPENDS:${PN} = "coreutils openssl systemd"

SYSTEMD_SERVICE:${PN} = "acadia-device-identity.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/acadia-device-identity.sh \
        ${D}${sbindir}/acadia-device-identity

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-device-identity.service \
        ${D}${systemd_system_unitdir}/acadia-device-identity.service
}

FILES:${PN} = " \
    ${sbindir}/acadia-device-identity \
    ${systemd_system_unitdir}/acadia-device-identity.service \
"
