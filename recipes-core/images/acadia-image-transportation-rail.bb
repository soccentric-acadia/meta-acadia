SUMMARY = "Acadia Transportation & Rail image"
DESCRIPTION = "Acadia production image for transportation and rail edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
