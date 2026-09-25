SUMMARY = "Acadia HAL module registry, installed on-device"
DESCRIPTION = "Installs a vendored snapshot of Acadia-HAL's \
               protos/registry/modules.yaml to /etc/acadia/modules.yaml so \
               acadia-client.service does not run in degraded \
               empty-registry mode (integration-ivv.md VB-3, V-A04, \
               improvements.md OS-061)."
HOMEPAGE = "https://github.com/soccentric-acadia/meta-acadia"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://modules.yaml"

inherit allarch

do_install() {
    install -d ${D}${sysconfdir}/acadia
    install -m 0644 ${WORKDIR}/modules.yaml ${D}${sysconfdir}/acadia/modules.yaml
}

FILES:${PN} += "${sysconfdir}/acadia/modules.yaml"
