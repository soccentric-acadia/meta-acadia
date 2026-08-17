SUMMARY = "Acadia Industrial Automation image"
DESCRIPTION = "Acadia production image for industrial automation with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
