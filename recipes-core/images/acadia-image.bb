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
# T-P14 (F12): the SWUpdate Mongoose web UI is removed from production —
# plain-HTTP :8080 with a per-boot printed password is a duplicate OTA path
# and an exposure (OS-006..008). Local OTA goes through WebConfig (K06);
# remote OTA through HQ (K09). swupdate itself stays (install daemon), plus
# swupdate-client, which WebConfig uses to hand bundles to it (T-P26).
IMAGE_INSTALL:append:raspberrypi5 = " swupdate swupdate-client rpi5-swupdate-config"
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " swupdate swupdate-client rpi5-swupdate-config"

# Home partition init
IMAGE_INSTALL:append = " rpi5-home-init"

# Persistent /pst store (task 003): partition p4 is declared in
# sdimage-rpi5.wks; acadia-pst-init ships pst.mount (LABEL=pst, skipped
# silently on devices without the partition) plus the ownership bootstrap
# the instrumentation units' ReadWritePaths contract requires.  Scoped to
# the A/B WKS boards; single-partition boards have no LABEL=pst partition.
IMAGE_INSTALL:append:raspberrypi5 = " acadia-pst-init"
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " acadia-pst-init"

# Factory provisioning (T-P09, A02): one-shot identity writer for /pst +
# line-station tool. Skipped silently on machines without the /pst
# partition; a pre-existing record is never overwritten (write-once).
IMAGE_INSTALL:append:raspberrypi5 = " acadia-factory-provision"
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " acadia-factory-provision"
# T-P33 (C06/C07): boot-time factory reset executor — needs the /pst + /home
# layout, so it ships wherever acadia-pst-init does.
IMAGE_INSTALL:append:raspberrypi5 = " acadia-factory-wipe"
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " acadia-factory-wipe"

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

# WebConfig application: the recipe fetches and builds Acadia-Configuration,
# then installs its daemon, UI, schemas, and board manifest.
IMAGE_INSTALL:append = " webconfigd webconfig-static webconfig-schemas webconfig-manifest"
# P-A10/OS-071: optional fleet HQ CA + config-signing key (empty package
# unless ACADIA_HQ_CA_FILE / ACADIA_HQ_CONFIG_PUBKEY_FILE are set).
IMAGE_INSTALL:append = " acadia-hq-trust"

# Instrumentation: the recipe fetches and builds Acadia-Instrumentation, then
# installs the istate hub and its nine spokes. Its INSTR_BOARD mapping (and
# the descriptor set it ships) only covers raspberrypi4-64 and raspberrypi5
# — every other Acadia MACHINE has no mapping, so this is scoped per-machine
# rather than added unconditionally (which would fail those boards' builds
# with "nothing provides instrumentation" via COMPATIBLE_MACHINE).
IMAGE_INSTALL:append:raspberrypi4-64 = " instrumentation"
IMAGE_INSTALL:append:raspberrypi5 = " instrumentation"
# T-P06 (A07): CM5 ships Instrumentation too — the recipe's
# COMPATIBLE_MACHINE now covers raspberrypi-cm5-io-board with the cm5
# descriptor set (INSTR_BOARD=cm5), same BCM2712 peripheral set as the Pi 5.
IMAGE_INSTALL:append:raspberrypi-cm5-io-board = " instrumentation"

# gRPC + Protobuf (NO compiler on device — M5)
# Provided via packagegroup-acadia-middleware (feature.txt §6: "Middleware
# package group support") instead of an individual package list.
IMAGE_INSTALL:append = " packagegroup-acadia-middleware sudo"
# T-P29 (J03): remote syslog transport for WebConfig (forward-only config,
# recipes-extended/rsyslog bbappend).
IMAGE_INSTALL:append = " rsyslog"

# polkit (SB-2, T-P02): the zbus service-control path (webconfigd's Services
# page start/stop/restart) is authorized by the shipped
# 50-webconfigd.polkit.rules; every other privileged applier op routes
# through the webconfig-applyd root helper (no polkit involved). Without the
# package the D-Bus path denies everything for the non-root daemon.
IMAGE_INSTALL:append = " polkit"

# Required runtime binaries for shipped features (SB-3, T-P03; gate in the
# Acadia-OS scripts/check-image-packages.sh REQUIRED_IMAGE_PACKAGES — keep
# both in sync). Deferred per T-P00e, features hidden in v1: hostapd/dnsmasq
# (AP mode), linuxptp (PTP), wireguard-tools (WireGuard) — package one and
# add it to the gate in the same change.
#   nftables           — firewall applier drives nft (P-F01)
#   chrony             — GNSS time chain gpsd+chrony (P-D05)
#   mosquitto-clients  — alert delivery via mosquitto_pub (P-I07)
#   curl               — OTA/backup/HQ downloads (webconfigd shells out)
#   ca-certificates    — TLS verification for those curl/HQ paths
IMAGE_INSTALL:append = " nftables chrony mosquitto-clients curl ca-certificates"

# Cloud/telemetry (feature.txt §6: "Cloud and telemetry package group
# support"). packagegroup-acadia-cloud remains NOT installed as a group —
# acadia-client (the cloud-facing daemon) is excluded pending an upstream
# repo — but T-P03 now installs the runtime pieces shipped features need
# directly (mosquitto-clients, chrony, curl, above), so the group only adds
# the broker itself. Deployments needing the broker can still add
# 'packagegroup-acadia-cloud' to IMAGE_INSTALL in their own image recipe.

# Production hardening baseline (T-P14): default-deny nftables (F01),
# sudo policy drop-in (OS-013), console policy documentation (F04).
IMAGE_INSTALL:append = " acadia-hardening"

# Real-time diagnostics (task 002): rt-tests ships cyclictest / hackbench /
# hwlatdetect for scheduling-latency measurement on the PREEMPT_RT kernel.
IMAGE_INSTALL:append = " rt-tests"

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
# lm-sensors for sensor inspection. Fan control is kernel-owned (T-P30,
# OS-052/053): the bcm2712 cooling-fan thermal trips are set with fan_temp*
# dtparams in kas/common.yaml — no userspace loop fighting the governor.
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
# OS-028: acadia-client (the IV&V device agent) is now installed in the image
# together with acadia-data-init (first-boot data provisioning) and a pinned
# HAL sibling SRCREV so the client's develop adapters build reproducibly.
# OS-1x (VB-1): i2c/spi/gpio groups + udev rules so acadia-client.service
# can reach those device classes via SupplementaryGroups=.
# OS-061 (VB-3): install the HAL module registry on-device so the Client
# does not run in degraded empty-registry mode.
IMAGE_INSTALL:append = " acadia-hal acadia-services acadia-device-identity acadia-boot-integrity acadia-client acadia-data-init acadia-udev-rules acadia-module-registry"
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
# operator login account (T-P11/B03, renames the mis-spelled `acaida`,
# OS-004) — LOCKED until first use. SSH access for it is key-only
# (acadia-hardening.conf: AllowUsers rpi operator, PasswordAuthentication
# no); keys are provisioned by the T-P11 HQ command / WebConfig SSH page
# into /home/operator/.ssh/authorized_keys (webconfig-applyd chowns them
# operator:operator). Per-device credentials are provisioned at first use
# (T-P11); until then the account stays disabled like the rpi account.
# Same -M reasoning as above: /home/operator is recorded in /etc/passwd and
# created on the persistent p5 (/home) partition by rpi5-home-init
# on first boot.
inherit extrausers
# OS-072: base-passwd already ships an `operator` GROUP (gid 37), so the
# operator user must join it (-g) — a plain useradd refuses to create a
# same-named user group and do_rootfs fails.
EXTRA_USERS_PARAMS = "\
    useradd -M -s /bin/bash -G sudo rpi; \
    usermod -L rpi; \
    useradd -M -s /bin/bash -d /home/operator -g operator operator; \
    usermod -L operator; \
"

