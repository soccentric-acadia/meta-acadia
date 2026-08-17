SUMMARY = "Acadia Automotive image"
DESCRIPTION = "Acadia production image for automotive edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
