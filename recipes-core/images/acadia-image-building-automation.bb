SUMMARY = "Acadia Building Automation / Smart Home image"
DESCRIPTION = "Acadia production image for building automation and smart-home edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
