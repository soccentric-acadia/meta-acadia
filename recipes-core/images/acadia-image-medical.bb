SUMMARY = "Acadia Medical Devices image"
DESCRIPTION = "Acadia production image for medical-device edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
