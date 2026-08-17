SUMMARY = "Acadia Energy & Power (Smart Grid) image"
DESCRIPTION = "Acadia production image for energy and smart-grid edge systems with networking, hardware integration, diagnostics, and middleware."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-industry"
