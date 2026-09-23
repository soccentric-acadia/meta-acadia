SUMMARY = "Acadia production hardening baseline (T-P14)"
DESCRIPTION = "Default-deny nftables baseline (F01/OS-014), the sudo policy \
drop-in (OS-013) and the production console policy documentation (F04). \
The WebConfig firewall applier manages its own separate table."
LICENSE     = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-default.nft \
    file://acadia-firewall.service \
    file://acadia-sudoers \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN}     = "acadia-firewall.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "nftables sudo"

do_install() {
    install -d ${D}${libdir}/acadia-hardening
    install -m 0644 ${WORKDIR}/acadia-default.nft \
                    ${D}${libdir}/acadia-hardening/acadia-default.nft

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-firewall.service \
                    ${D}${systemd_system_unitdir}/acadia-firewall.service

    # sudoers drop-in (validated-syntax file; sudo reads /etc/sudoers.d/*).
    install -d ${D}${sysconfdir}/sudoers.d
    install -m 0440 ${WORKDIR}/acadia-sudoers \
                    ${D}${sysconfdir}/sudoers.d/acadia
}

FILES:${PN} += " \
    ${libdir}/acadia-hardening/ \
    ${systemd_system_unitdir}/acadia-firewall.service \
    ${sysconfdir}/sudoers.d/acadia \
"
