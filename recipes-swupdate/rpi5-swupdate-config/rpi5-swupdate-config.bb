SUMMARY     = "SWUpdate runtime configuration and A/B OTA helper scripts for RPi5"
DESCRIPTION = "Installs swupdate.cfg, slot-detection / boot-slot scripts, a \
               systemd drop-in that starts the signed-install daemon through \
               swupdate-start.sh (no web UI since T-P14), boot-watchdog for \
               the rollback counter and the health-check service."
LICENSE     = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://swupdate.cfg \
    file://pre-install.sh \
    file://post-install.sh \
    file://reboot-tryboot.sh \
    file://swupdate-bootcheck.sh \
    file://swupdate-bootcheck.service \
    file://boot-watchdog.sh \
    file://boot-watchdog.service \
    file://swupdate-start.sh \
    file://swupdate-webui.conf \
    file://bootcount-reset.sh \
    file://bootcount-reset.service \
    file://fw_env.config \
    file://swupdate-public.pem \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = " \
    swupdate-bootcheck.service \
    boot-watchdog.service \
    bootcount-reset.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# swupdate and bash are required at runtime; util-linux provides findmnt/blkid;
# libubootenv provides fw_setenv/fw_printenv for U-Boot env OTA confirmation.
RDEPENDS:${PN} = "swupdate bash util-linux libubootenv"

do_install() {
    # swupdate main config
    install -d ${D}${sysconfdir}/swupdate
    install -m 0644 ${WORKDIR}/swupdate.cfg \
                    ${D}${sysconfdir}/swupdate/swupdate.cfg
    # OS-010 (T-P06): the identify block is board data — give each supported
    # machine its own name instead of shipping "rpi5" on every machine.
    if [ "${MACHINE}" = "raspberrypi-cm5-io-board" ]; then
        sed -i 's|name              = "rpi5"|name              = "cm5"|' \
            ${D}${sysconfdir}/swupdate/swupdate.cfg
    fi

    # A/B slot helper scripts (also shipped in .swu packages)
    install -d ${D}${libdir}/swupdate
    install -m 0755 ${WORKDIR}/pre-install.sh \
                    ${D}${libdir}/swupdate/pre-install.sh
    install -m 0755 ${WORKDIR}/post-install.sh \
                    ${D}${libdir}/swupdate/post-install.sh
    install -m 0755 ${WORKDIR}/reboot-tryboot.sh \
                    ${D}${libdir}/swupdate/reboot-tryboot.sh
    install -m 0755 ${WORKDIR}/swupdate-bootcheck.sh \
                    ${D}${libdir}/swupdate/swupdate-bootcheck.sh

    # Boot watchdog (C1 — runs before basic.target)
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/boot-watchdog.sh \
                    ${D}${sbindir}/boot-watchdog.sh

    # T051: U-Boot env bootcount-reset script and config
    install -m 0755 ${WORKDIR}/bootcount-reset.sh \
                    ${D}${libdir}/swupdate/bootcount-reset.sh
    install -m 0644 ${WORKDIR}/fw_env.config \
                    ${D}${sysconfdir}/fw_env.config

    # swupdate startup wrapper (C2 signing + I7 web UI auth)
    install -m 0755 ${WORKDIR}/swupdate-start.sh \
                    ${D}${sbindir}/swupdate-start.sh

    # systemd units
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/swupdate-bootcheck.service \
                    ${D}${systemd_system_unitdir}/swupdate-bootcheck.service
    install -m 0644 ${WORKDIR}/boot-watchdog.service \
                    ${D}${systemd_system_unitdir}/boot-watchdog.service
    install -m 0644 ${WORKDIR}/bootcount-reset.service \
                    ${D}${systemd_system_unitdir}/bootcount-reset.service

    # Drop-in: replace ExecStart with swupdate-start.sh wrapper (F12: the
    # web UI is gone; the wrapper keeps the signed-install contract)
    install -d ${D}${systemd_system_unitdir}/swupdate.service.d
    install -m 0644 ${WORKDIR}/swupdate-webui.conf \
                    ${D}${systemd_system_unitdir}/swupdate.service.d/webui.conf

    # Issue #21: install the SWUpdate RSA public key to /etc/swupdate/.
    # The key enables signature verification of incoming .swu packages.
    # The private counterpart lives in the build/CI vault only.
    install -m 0644 ${WORKDIR}/swupdate-public.pem \
                    ${D}${sysconfdir}/swupdate/swupdate-public.pem
}

FILES:${PN} += " \
    ${sysconfdir}/swupdate/ \
    ${sysconfdir}/fw_env.config \
    ${libdir}/swupdate/ \
    ${sbindir}/boot-watchdog.sh \
    ${sbindir}/swupdate-start.sh \
    ${systemd_system_unitdir}/swupdate-bootcheck.service \
    ${systemd_system_unitdir}/boot-watchdog.service \
    ${systemd_system_unitdir}/bootcount-reset.service \
    ${systemd_system_unitdir}/swupdate.service.d/ \
    ${sysconfdir}/swupdate/swupdate-public.pem \
"
