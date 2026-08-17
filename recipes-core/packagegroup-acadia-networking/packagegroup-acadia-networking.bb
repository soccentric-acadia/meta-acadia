SUMMARY = "Acadia networking and edge connectivity package group"
DESCRIPTION = "Networking, wireless, Bluetooth, diagnostics, time synchronisation, and cloud transport for Acadia edge deployments."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-OS"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

PACKAGES = "${PN}"
ALLOW_EMPTY:${PN} = "1"

RDEPENDS:${PN} = " \
    rpi5-connectivity \
    packagegroup-acadia-cloud \
    iw \
    rfkill \
    bluez5 \
    bluez5-dev \
    ethtool \
    usbutils \
    curl \
    wget \
    openssh \
"
