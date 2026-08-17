SUMMARY = "Acadia robotics and hardware integration package group"
DESCRIPTION = "Hardware abstraction, middleware, camera and video pipelines, buses, sensors, audio, and diagnostics for Acadia robotics deployments."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-OS"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

PACKAGES = "${PN}"
ALLOW_EMPTY:${PN} = "1"

RDEPENDS:${PN} = " \
    acadia-hal \
    acadia-services \
    acadia-camera \
    packagegroup-acadia-middleware \
    libcamera \
    libcamera-apps \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav \
    ffmpeg \
    i2c-tools \
    python3-smbus \
    python3-smbus2 \
    python3-spidev \
    libgpiod-tools \
    python3-gpiod \
    can-utils \
    gpsd \
    gps-utils \
    python3-gpsd-py3 \
    v4l-utils \
    alsa-utils \
    evtest \
    python3-pyserial \
    python3-periphery \
    openocd \
"
