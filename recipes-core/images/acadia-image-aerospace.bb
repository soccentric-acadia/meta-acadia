SUMMARY = "Acadia Aerospace image"
DESCRIPTION = "Acadia production image for aerospace edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
