SUMMARY = "Acadia industrial and embedded product platform package group"
DESCRIPTION = "Common networking, edge, robotics, hardware integration, diagnostics, and middleware capabilities for Acadia industry images."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-OS"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

PACKAGES = "${PN}"
ALLOW_EMPTY:${PN} = "1"

RDEPENDS:${PN} = " \
    packagegroup-acadia-networking \
    packagegroup-acadia-robotics \
"
