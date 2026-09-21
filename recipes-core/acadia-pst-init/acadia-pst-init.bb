SUMMARY = "Provision the persistent /pst store partition (p4, label pst)"
DESCRIPTION = "Mount unit for the LABEL=pst partition plus a one-shot service \
that sets ownership (instr-istate:instr, setgid 2770) and per-spoke store \
directories on the freshly mounted /pst before istate starts.  Devices \
without the partition (old 4-partition layout) skip everything silently. \
Task 003."
LICENSE     = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://pst.mount \
    file://acadia-pst-init.service \
    file://acadia-pst-init.sh \
    file://instr-istate.service.d-pst-order.conf \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN}     = "pst.mount acadia-pst-init.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "bash util-linux"

do_install() {
    install -d ${D}${libdir}/acadia-pst-init
    install -m 0755 ${WORKDIR}/acadia-pst-init.sh \
                    ${D}${libdir}/acadia-pst-init/acadia-pst-init.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/pst.mount \
                    ${D}${systemd_system_unitdir}/pst.mount
    install -m 0644 ${WORKDIR}/acadia-pst-init.service \
                    ${D}${systemd_system_unitdir}/acadia-pst-init.service

    # Ordering drop-in for the /pst owner.  instr-istate.service ships from
    # the instrumentation recipe; a drop-in keeps this decoupled from
    # upstream unit files.
    install -d ${D}${systemd_system_unitdir}/instr-istate.service.d
    install -m 0644 ${WORKDIR}/instr-istate.service.d-pst-order.conf \
                    ${D}${systemd_system_unitdir}/instr-istate.service.d/pst-order.conf

    # Rootfs mountpoint skeleton (hidden by the mounted partition on
    # devices with the new layout; istate's fallback target otherwise).
    install -d ${D}/pst
}

FILES:${PN} += " \
    ${libdir}/acadia-pst-init/ \
    ${systemd_system_unitdir}/pst.mount \
    ${systemd_system_unitdir}/acadia-pst-init.service \
    ${systemd_system_unitdir}/instr-istate.service.d/ \
    /pst \
"