SUMMARY = "Acadia Agriculture (AgTech) image"
DESCRIPTION = "Acadia production image for agriculture and AgTech edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
