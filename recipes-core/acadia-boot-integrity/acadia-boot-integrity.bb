SUMMARY = "Acadia boot integrity status"
DESCRIPTION = "Reports Raspberry Pi secure-boot state, dm-verity mappings, and EEPROM update status without mutating boot media."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-boot-integrity.service \
    file://acadia-boot-integrity.sh \
"

inherit allarch systemd

RDEPENDS:${PN} = "util-linux systemd"

SYSTEMD_SERVICE:${PN} = "acadia-boot-integrity.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/acadia-boot-integrity.sh \
        ${D}${sbindir}/acadia-boot-integrity

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-boot-integrity.service \
        ${D}${systemd_system_unitdir}/acadia-boot-integrity.service
}

FILES:${PN} = " \
    ${sbindir}/acadia-boot-integrity \
    ${systemd_system_unitdir}/acadia-boot-integrity.service \
"
