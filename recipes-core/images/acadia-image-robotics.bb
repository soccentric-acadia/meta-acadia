SUMMARY = "Acadia Robotics and Hardware Integration image"
DESCRIPTION = "Acadia production image with the complete platform base and robotics, camera, video, sensor, audio, and hardware integration tooling."
LICENSE = "MIT"

require ${THISDIR}/acadia-image.bb

IMAGE_INSTALL:append = " packagegroup-acadia-robotics"
