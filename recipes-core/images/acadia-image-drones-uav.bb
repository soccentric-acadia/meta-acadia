SUMMARY = "Acadia Drones / UAV image"
DESCRIPTION = "Acadia production image for drone and UAV edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
