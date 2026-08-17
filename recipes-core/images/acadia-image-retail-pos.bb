SUMMARY = "Acadia Retail / Point-of-Sale image"
DESCRIPTION = "Acadia production image for retail and point-of-sale edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
