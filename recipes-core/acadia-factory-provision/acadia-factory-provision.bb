SUMMARY = "Factory provisioning of the per-device identity record (T-P09)"
DESCRIPTION = "One-shot service + line-station tool that writes \
/pst/factory/identity/{identity.yaml,.secret} (serial, class secret, claim \
code) once per device and prints the device label. Instrumentation refuses \
to seal/enroll without the record (INS-005); the first-boot admin claim \
(T-P10) consumes the mirrored claim code. Machines without the /pst \
partition skip silently."
LICENSE     = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-provision-identity.sh \
    file://acadia-factory-provision.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN}     = "acadia-factory-provision.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# The tool writes /pst/factory/identity (root:instr) and mirrors the claim
# code into the WebConfig store; it shells out to coreutils only.
RDEPENDS:${PN} = "bash coreutils util-linux"

do_install() {
    install -d ${D}${libdir}/acadia-factory-provision
    install -m 0755 ${WORKDIR}/acadia-provision-identity.sh \
                    ${D}${libdir}/acadia-factory-provision/acadia-provision-identity.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-factory-provision.service \
                    ${D}${systemd_system_unitdir}/acadia-factory-provision.service
}

FILES:${PN} += " \
    ${libdir}/acadia-factory-provision/ \
    ${systemd_system_unitdir}/acadia-factory-provision.service \
"