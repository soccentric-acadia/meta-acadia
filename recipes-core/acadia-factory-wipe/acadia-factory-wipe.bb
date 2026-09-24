SUMMARY = "Boot-time factory reset executor (T-P33, C06/C07)"
DESCRIPTION = "Carries out a factory reset requested by WebConfig \
(/pst/webconfig/factory-wipe.request) at early boot, before any service \
opens its state: level 'settings' resets the Instrumentation config/state \
trees, level 'full' (RMA) wipes /pst except the factory identity, /home, \
OTA staging and the persistent journal. See docs/factory-reset.md."
LICENSE     = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-factory-wipe.sh \
    file://acadia-factory-wipe.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN}     = "acadia-factory-wipe.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "bash coreutils sed util-linux"

do_install() {
    install -d ${D}${libdir}/acadia-factory-wipe
    install -m 0755 ${WORKDIR}/acadia-factory-wipe.sh \
                    ${D}${libdir}/acadia-factory-wipe/acadia-factory-wipe.sh
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-factory-wipe.service \
                    ${D}${systemd_system_unitdir}/acadia-factory-wipe.service
}

FILES:${PN} += "${libdir}/acadia-factory-wipe/"
