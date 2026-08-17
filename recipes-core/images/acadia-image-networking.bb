SUMMARY = "Acadia Networking & Edge image"
DESCRIPTION = "Acadia production image with the complete platform base and networking, wireless, Bluetooth, cloud, and edge diagnostics."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-networking"
