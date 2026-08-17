SUMMARY = "Acadia Consumer Electronics image"
DESCRIPTION = "Acadia production image for consumer electronics with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
