SUMMARY = "Acadia optional camera capture service"
DESCRIPTION = "A disabled-by-default GStreamer camera capture service for Pi CSI/V4L2 validation and network streaming."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://acadia-camera-capture.service \
    file://acadia-camera-capture.conf \
    file://acadia-camera-capture.sh \
"

inherit allarch systemd

RDEPENDS:${PN} = "gstreamer1.0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good"

SYSTEMD_SERVICE:${PN} = "acadia-camera-capture.service"
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/acadia-camera-capture.sh \
        ${D}${sbindir}/acadia-camera-capture

    install -d ${D}${sysconfdir}/acadia
    install -m 0644 ${WORKDIR}/acadia-camera-capture.conf \
        ${D}${sysconfdir}/acadia/camera-capture.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-camera-capture.service \
        ${D}${systemd_system_unitdir}/acadia-camera-capture.service
}

FILES:${PN} = " \
    ${sbindir}/acadia-camera-capture \
    ${sysconfdir}/acadia/camera-capture.conf \
    ${systemd_system_unitdir}/acadia-camera-capture.service \
"
