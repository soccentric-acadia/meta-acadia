SUMMARY = "Acadia hardware-group udev rules"
DESCRIPTION = "Creates the i2c/spi/gpio groups and the udev rules that \
               assign /dev/i2c-*, /dev/spidev*, and /dev/gpiochip* to \
               them, so acadia-client.service can reach them via \
               SupplementaryGroups= instead of setuid/setcap \
               (integration-ivv.md VB-1, T-V00a)."
HOMEPAGE = "https://github.com/soccentric-acadia/meta-acadia"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://61-acadia-hw-groups.rules"

inherit allarch useradd

# -r: system group, no login shell implications (there is no matching user).
# dialout/video/audio/disk are NOT created here — they are standard groups
# already provided by base-passwd and already own the relevant device
# nodes via systemd-udevd's own default rules.
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r i2c; -r spi; -r gpio"

do_install() {
    install -d ${D}${nonarch_base_libdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/61-acadia-hw-groups.rules \
                    ${D}${nonarch_base_libdir}/udev/rules.d/61-acadia-hw-groups.rules
}

FILES:${PN} += "${nonarch_base_libdir}/udev/rules.d/61-acadia-hw-groups.rules"
