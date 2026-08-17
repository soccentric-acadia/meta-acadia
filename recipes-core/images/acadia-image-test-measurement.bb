SUMMARY = "Acadia Test & Measurement image"
DESCRIPTION = "Acadia production image for test and measurement systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
