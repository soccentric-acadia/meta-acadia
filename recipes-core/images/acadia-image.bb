SUMMARY = "Acadia OS — production image for Raspberry Pi 5"
DESCRIPTION = "Full image with A/B OTA, gRPC/Protobuf, Acadia-HAL, \
               Acadia-Client daemon, and hardware interface tooling."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-OS"
LICENSE = "MIT"

# Base on core-image-full-cmdline (provides bash, sshd-openssh,
# package-management, base IMAGE_INSTALL framework).  The previous
# version inherited bare core-image, which gave a smaller image but
# one that did not match the operator-visible feature set documented
# in CLAUDE.md / README.md.  Issues #25 and #45: the two image recipes
# (acadia-image.bb and core-image-full-cmdline.bbappend) had
# divergent bases.  This is the canonical fix — both recipes now
# share the same Yocto base; the bbappend-style deltas go into
# this single recipe.
#
# NOTE: core-image-full-cmdline is an *image recipe*, not a bbclass,
# so it must be pulled in with `require` (not `inherit`).
require recipes-extended/images/core-image-full-cmdline.bb
IMAGE_FEATURES += "ssh-server-openssh"

# OTA / swupdate
# rpi5-swupdate-config implements the inactive-slot, boot-selection, and
# rollback flow for sdimage-rpi5.wks. Do not install it on single-rootfs
# machines, where its /dev/swupdate-inactive contract cannot be satisfied.
IMAGE_INSTALL:append:raspberrypi5 = " swupdate swupdate-www rpi5-swupdate-config"
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " swupdate swupdate-www rpi5-swupdate-config"

# Home partition init
IMAGE_INSTALL:append = " rpi5-home-init"

# Root filesystem expansion (feature.txt §3: "Optional root filesystem
# expansion service for single-partition deployments"). rpi5/cm5 use the
# fixed-size A/B WKS layout (sdimage-rpi5.wks) where the two rootfs slots
# are deliberately NOT grown to fill the disk, so expand-rootfs is
# excluded there; every other (single-partition) board needs it to use
# the full SD card / eMMC / NVMe capacity on first boot.
IMAGE_INSTALL:append = " expand-rootfs"
IMAGE_INSTALL:remove:raspberrypi5 = "expand-rootfs"
IMAGE_INSTALL:remove:raspberrypi-cm5-io-board = "expand-rootfs"

# Connectivity
# rpi5-connectivity already pulls wpa-supplicant + bluez5 via RDEPENDS
# (issue #53); list only the tools the user might use directly.
IMAGE_INSTALL:append = " \
    rpi5-connectivity iw rfkill bluez5-dev \
"

# WebConfig on-device configuration UI (meta-webconfig layer, task 26)
IMAGE_INSTALL:append = " webconfigd webconfig-static webconfig-schemas webconfig-manifest"

# gRPC + Protobuf (NO compiler on device — M5)
# Provided via packagegroup-acadia-middleware (feature.txt §6: "Middleware
# package group support") instead of an individual package list.
IMAGE_INSTALL:append = " packagegroup-acadia-middleware sudo"

# Cloud/telemetry (feature.txt §6: "Cloud and telemetry package group
# support"). packagegroup-acadia-cloud (mosquitto, chrony, curl) exists
# but is NOT installed by default here — acadia-client (the cloud-facing
# daemon) is likewise excluded pending an upstream repo. Deployments that
# need cloud/telemetry connectivity should add
# 'packagegroup-acadia-cloud' to IMAGE_INSTALL in their own image recipe.

# Hardware interface tools
IMAGE_INSTALL:append = " \
    i2c-tools python3-smbus python3-smbus2 \
    spitools python3-spidev \
    libgpiod libgpiod-tools python3-gpiod \
    picocom minicom python3-pyserial \
    usbutils pciutils nvme-cli sg3-utils hdparm mtd-utils \
    can-utils \
    lshw ethtool devmem2 cpupower watchdog sysstat iotop strace \
    v4l-utils evtest python3-periphery vim \
"

# ── Camera / Video (feature.txt §7 / task.md Camera-Video) ─────────────────
# libcamera + libcamera-apps come from meta-raspberrypi's dynamic
# multimedia-layer (already a bblayer).  libcamera-apps provides the
# rpicam-* CLI tools (rpicam-hello, rpicam-still, rpicam-vid) for
# Unicam/ISP bring-up diagnostics.  GStreamer + ffmpeg provide the
# V4L2/VA stateless-decode pipeline for H.265/HEVC (see
# LICENSE_FLAGS_ACCEPTED in kas/common.yaml for the HEVC flag).
#
# acadia-camera provides the disabled-by-default GStreamer capture/
# streaming service (task.md Camera-Video: "v4l2-relayd or equivalent
# V4L2↔RTSP/GStreamer bridging"). It is safe to ship preinstalled but
# inert: it only runs when ENABLED=1 is set in
# /etc/acadia/camera-capture.conf (see recipes-multimedia/acadia-camera).
IMAGE_INSTALL:append = " \
    libcamera libcamera-apps acadia-camera \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-libav \
    ffmpeg \
"

# ── Display / DRM-KMS (task.md Display) ─────────────────────────────────────
# kmscube exercises the KMS/DRM pipeline; libdrm-tests provides modetest
# for display bring-up diagnostics.  vc4-kms-v3d is pinned per-board
# (see kas/boards/*.yaml).
IMAGE_INSTALL:append = " kmscube libdrm-tests"

# ── Audio (task.md Audio) ───────────────────────────────────────────────────
# alsa-utils provides aplay/arecord/speaker-test for audio-path bring-up.
IMAGE_INSTALL:append = " alsa-utils"

# ── Sensors / GPS / 1-Wire (task.md GPIO-Sensors-IndustrialIO) ─────────────
# gpsd + python bindings for location-tagged telemetry; owfs for 1-Wire
# temperature probes (dtoverlay=w1-gpio is set in kas/common.yaml).
IMAGE_INSTALL:append = " \
    gpsd gpsd-conf gps-utils python3-pygps python3-gpsd-py3 \
    owfs owserver owshell \
"

# ── Power / Thermal (task.md Power-Thermal) ─────────────────────────────────
# lm-sensors for sensor inspection. Fan control is provided by the
# platform-native fan-control service in acadia-services, avoiding a
# machine-specific fancontrol package split that is not available in the
# pinned OpenEmbedded layer set.
IMAGE_INSTALL:append = " lmsensors"

# ── Storage / Boot (task.md Storage-Boot) ───────────────────────────────────
# rpi-eeprom provides rpi-eeprom-update/config/digest so PCIe NVMe can be
# a first-class boot device (EEPROM boot-order management).
IMAGE_INSTALL:append = " rpi-eeprom"

# ── Debug / Diagnostics (task.md Debug-Diagnostics) ─────────────────────────
# Task 53: debug tooling is gated behind ACADIA_ENABLE_DEBUG (default 0 for
# production). A production build must not ship these unconditionally.
# Enable with: ACADIA_ENABLE_DEBUG=1 make image <board>
ACADIA_ENABLE_DEBUG ?= "0"
ACADIA_DEBUG_PACKAGES = ""
ACADIA_DEBUG_PACKAGES:append = "${@' openocd gdbserver perf trace-cmd valgrind' if '${ACADIA_ENABLE_DEBUG}' == '1' else ''}"

# Acadia stack
# NOTE: acadia-client is excluded until the upstream repo exists and SRCREV is
# pinned. Add it back once available: acadia-client acadia-data-init
IMAGE_INSTALL:append = " acadia-hal acadia-services acadia-device-identity acadia-boot-integrity"
IMAGE_INSTALL:append = "${ACADIA_DEBUG_PACKAGES}"

# Target debugging and profiling (feature.txt §6). tools-debug pulls in
# gdb/gdbserver/strace. Gated behind ACADIA_ENABLE_DEBUG for production.
IMAGE_FEATURES:append = "${@' tools-debug' if '${ACADIA_ENABLE_DEBUG}' == '1' else ''}"

# Ptest package and runner support (feature.txt §6 / §12). DISTRO_FEATURES
# already has "ptest" appended (kas/common.yaml); this installs the
# -ptest packages that are built as a result.
IMAGE_FEATURES += "ptest-pkgs"

# Operator account — locked, SSH-key access only
# Issue #102: use -M (--no-create-home) because p4 (/home) is
# recreated by rpi5-home-init.sh on first boot.  useradd -m would
# create /home/rpi on the volatile rootfs, which is then hidden
# by the persistent mount at /home.
#
# acaida login account — password login enabled (password: acaida,
# SHA-512-crypt, fixed salt for reproducible builds).  Same -M
# reasoning as above: /home/acaida is recorded in /etc/passwd and
# created on the persistent p4 (/home) partition by rpi5-home-init
# on first boot.
inherit extrausers
EXTRA_USERS_PARAMS = "\
    useradd -M -s /bin/bash -G sudo rpi; \
    usermod -L rpi; \
    useradd -M -s /bin/bash -d /home/acaida acaida; \
    usermod -p '\$6\$acadiaos\$7g./Wtafy6arBlbXkZ2qbgnpz2ZrxsFT8La8OUE3cc0/t0/wIka0teWFWiqZ4d4w1hv9mre1YudRi783PtD8x.' acaida; \
"

