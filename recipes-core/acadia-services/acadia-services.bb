SUMMARY = "Acadia system health services (dmesg capture, disk usage, thermal, watchdog)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://dmesg-capture.service \
    file://disk-usage-check.sh \
    file://disk-usage-check.service \
    file://disk-usage-check.timer \
    file://thermal-check.sh \
    file://thermal-check.service \
    file://thermal-check.timer \
    file://fan-control.sh \
    file://fan-control.service \
    file://fan-control.timer \
    file://rtc-sync.sh \
    file://rtc-sync.service \
    file://rtc-sync-shutdown.service \
    file://watchdog.conf \
    file://80-acadia-watchdog.preset \
"

inherit allarch systemd

# systemd-cat is in the systemd package; dmesg is in util-linux.
# Both are pulled in by core-image-full-cmdline, but be explicit
# so this recipe is portable to images that might not include them
# (issue #56 regression — dmesg-capture.service now pipes to
# systemd-cat instead of writing to volatile /var/log/).
# watchdog provides the hardware watchdog daemon (watchdog.service).
RDEPENDS:${PN} = "systemd util-linux watchdog"

SYSTEMD_SERVICE:${PN} = " \
    dmesg-capture.service \
    disk-usage-check.service \
    disk-usage-check.timer \
    thermal-check.service \
    thermal-check.timer \
    fan-control.service \
    fan-control.timer \
    rtc-sync.service \
    rtc-sync-shutdown.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/disk-usage-check.sh \
                    ${D}${sbindir}/disk-usage-check.sh
    install -m 0755 ${WORKDIR}/thermal-check.sh \
                    ${D}${sbindir}/thermal-check.sh
    install -m 0755 ${WORKDIR}/fan-control.sh \
                    ${D}${sbindir}/fan-control.sh
    install -m 0755 ${WORKDIR}/rtc-sync.sh \
                    ${D}${sbindir}/rtc-sync.sh

    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/watchdog.conf \
                    ${D}${sysconfdir}/watchdog.conf

    # Enable the upstream `watchdog` daemon (watchdog.service) via a
    # systemd preset so the BCM2712 hardware watchdog is active.
    install -d ${D}${systemd_unitdir}/system-preset
    install -m 0644 ${WORKDIR}/80-acadia-watchdog.preset \
                    ${D}${systemd_unitdir}/system-preset/80-acadia-watchdog.preset

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/dmesg-capture.service \
                    ${D}${systemd_system_unitdir}/dmesg-capture.service
    install -m 0644 ${WORKDIR}/disk-usage-check.service \
                    ${D}${systemd_system_unitdir}/disk-usage-check.service
    install -m 0644 ${WORKDIR}/disk-usage-check.timer \
                    ${D}${systemd_system_unitdir}/disk-usage-check.timer
    install -m 0644 ${WORKDIR}/thermal-check.service \
                    ${D}${systemd_system_unitdir}/thermal-check.service
    install -m 0644 ${WORKDIR}/thermal-check.timer \
                    ${D}${systemd_system_unitdir}/thermal-check.timer
    install -m 0644 ${WORKDIR}/fan-control.service \
                    ${D}${systemd_system_unitdir}/fan-control.service
    install -m 0644 ${WORKDIR}/fan-control.timer \
                    ${D}${systemd_system_unitdir}/fan-control.timer
    install -m 0644 ${WORKDIR}/rtc-sync.service \
                    ${D}${systemd_system_unitdir}/rtc-sync.service
    install -m 0644 ${WORKDIR}/rtc-sync-shutdown.service \
                    ${D}${systemd_system_unitdir}/rtc-sync-shutdown.service
}

FILES:${PN} = " \
    ${sbindir}/disk-usage-check.sh \
    ${sbindir}/thermal-check.sh \
    ${sbindir}/fan-control.sh \
    ${sbindir}/rtc-sync.sh \
    ${sysconfdir}/watchdog.conf \
    ${systemd_unitdir}/system-preset/ \
    ${systemd_system_unitdir}/dmesg-capture.service \
    ${systemd_system_unitdir}/disk-usage-check.service \
    ${systemd_system_unitdir}/disk-usage-check.timer \
    ${systemd_system_unitdir}/thermal-check.service \
    ${systemd_system_unitdir}/thermal-check.timer \
    ${systemd_system_unitdir}/fan-control.service \
    ${systemd_system_unitdir}/fan-control.timer \
    ${systemd_system_unitdir}/rtc-sync.service \
    ${systemd_system_unitdir}/rtc-sync-shutdown.service \
"
