SUMMARY = "Acadia Security & Surveillance image"
DESCRIPTION = "Acadia production image for security and surveillance edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
