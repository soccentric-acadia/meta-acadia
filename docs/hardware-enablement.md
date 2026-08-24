# Acadia-OS — Raspberry Pi 5 / CM5 Hardware Enablement

This document records the hardware-enablement decisions and operational
guidance for the Raspberry Pi 5 / CM5 (BCM2712 + RP1) platform.  It
complements the implementation in `meta/meta-acadia` and the board YAMLs
in `kas/boards/`.  Items that are inherently documentation (secure boot,
JTAG access, serial pinout, USB gadget, NVMe boot order) live here so the
recipes stay focused on what they install and configure.

---

## 1. Connectivity

### 1.1 WiFi / BT firmware (Pi5)
The Pi5 machine conf (`meta-raspberrypi/conf/machine/raspberrypi5.conf`)
pulls the CYW43439-class firmware via `MACHINE_EXTRA_RRECOMMENDS`:
`linux-firmware-rpidistro-bcm43455`, `bluez-firmware-rpidistro-bcm4345c0-hcd`,
`linux-firmware-rpidistro-bcm43456`, `bluez-firmware-rpidistro-bcm4345c5-hcd`.
These are installed as runtime recommends, so they are present in the
image without being listed in `acadia-image.bb`.  `rpi5-connectivity`
enables `wpa_supplicant` + BlueZ via a systemd preset.

### 1.2 CM5 wireless distinction
CM5 Lite / no-wireless SKUs have no on-module radio.  The firmware blobs
above are inert (no radio present) but harmless.  For a strict
no-wireless profile, remove them in `kas/boards/cm5.yaml`:

```
MACHINE_EXTRA_RRECOMMENDS:remove = "linux-firmware-rpidistro-bcm43455 bluez-firmware-rpidistro-bcm4345c0-hcd linux-firmware-rpidistro-bcm43456 bluez-firmware-rpidistro-bcm4345c5-hcd"
```

and add an external USB/M.2 WiFi+BT module instead.

### 1.3 BLE peripheral-mode tooling
`bluez5-dev` (installed) provides `bluetoothctl`, `bluetoothd`, and the
GATT tools.  For IV&V device-pairing workflows, use:

```
bluetoothctl
  power on
  agent on
  default-agent
  advertise on
```

### 1.4 Gigabit Ethernet diagnostics
`ethtool` is installed.  For SFP / PoE-negotiation checks on a PoE HAT:

```
ethtool eth0
ethtool -m eth0        # SFP module EEPROM (if a SFP cage is used)
ethtool -S eth0        # per-queue stats
```

### 1.5 USB gadget mode
The RP1 south-bridge USB can run in device/gadget mode via the `dwc2`
overlay.  To enable a USB-Ethernet / CDC-ACM gadget for IV&V test-fixture
connections, add to `RPI_EXTRA_CONFIG`:

```
dtoverlay=dwc2,dr_mode=peripheral
```

and configure a gadget (e.g. `g_ether` / `g_serial`) at runtime.  The
`usbutils` / `pciutils` tooling is already installed.

### 1.6 PCIe
`pciutils` is installed.  The board YAMLs opt in to PCIe Gen3 via
`dtparam=pciex1_gen=3` (see `kas/boards/rpi5.yaml` / `cm5.yaml`).
Verify the link with `lspci -vv`.

---

## 2. Camera / Video

- `libcamera` + `libcamera-apps` are installed (from meta-raspberrypi's
  dynamic `multimedia-layer`).  `libcamera-apps` provides the `rpicam-*`
  CLI tools (`rpicam-hello`, `rpicam-still`, `rpicam-vid`) for Unicam/ISP
  bring-up diagnostics.
- GStreamer (`gstreamer1.0-plugins-base/good/bad`, `gstreamer1.0-libav`)
  and `ffmpeg` provide the V4L2/VA stateless-decode pipeline for
  H.265/HEVC.  The `commercial` license flag is accepted in
  `kas/common.yaml` (`LICENSE_FLAGS_ACCEPTED ?= "commercial"`).
- `GPU_MEM` is raised to `${GPU_MEM_CAMERA}` (256 MB) on the rpi5/cm5
  boards for the camera ISP/Unicam pipeline and hardware decode.
- `v4l2-ctl` (from `v4l-utils`) is installed for camera bring-up.
- `acadia-camera` ships a disabled-by-default GStreamer capture/streaming
  service (`acadia-camera-capture.service`) — the task.md
  “v4l2-relayd-or-equivalent V4L2↔GStreamer bridging” piece. It only
  runs when `ENABLED=1` is set in `/etc/acadia/camera-capture.conf`;
  set `GST_SINK` to a TCP/RTSP sink to stream the feed off-device.

Camera bring-up:

```
rpicam-hello --list-cameras
rpicam-still -o test.jpg
v4l2-ctl --list-devices
```

### 2.1 V4L2 -> network streaming bridge
`acadia-camera` (in `packagegroup-acadia-robotics`) ships a disabled-by-
default systemd service (`acadia-camera-capture.service`) that bridges the
V4L2 device to a network feed.  Set `MODE=udp` in
`/etc/acadia/camera-capture.conf` (plus `ENABLED=1`, `STREAM_HOST`,
`STREAM_PORT`) to send the feed as RTP/JPEG over UDP, and consume it on a
remote IV&V viewer:

```
# target: start the streaming bridge
systemctl enable --now acadia-camera-capture

# remote viewer
GST_DEV=rtpjpeg
gst-launch-1.0 udpsrc port=5000 \
    caps="application/x-rtp,encoding-name=JPEG,payload=26" ! \
    rtpjpegdepay ! jpegdec ! autovideosink
```

`MODE=local` keeps the original behaviour of rendering to a local sink
(`GST_SINK`, e.g. `fakesink`/`autovideosink`).  The pipeline uses only
`gstreamer1.0-plugins-good` elements (`udpsink`, `jpegenc`, `rtpjpegpay`),
so no extra license flag or layer is required.  For an RTSP-negotiated
feed, point a `gst-rtsp-server` host at the same device instead.

---

## 3. Storage / Boot

### 3.1 NVMe boot-order / EEPROM
`rpi-eeprom` is installed, providing `rpi-eeprom-update`,
`rpi-eeprom-config`, and `rpi-eeprom-digest`.  To make PCIe NVMe a
first-class boot device:

```
rpi-eeprom-config --edit     # set BOOT_ORDER to try NVMe before SD
rpi-eeprom-update -a         # apply the latest bootloader
```

The `dtparam=pciex1_gen=3` opt-in (board YAMLs) enables Gen3 for NVMe
throughput.

### 3.2 CM5 eMMC
CM5 modules with on-module eMMC boot from `mmcblk0` (the eMMC), while
CM5 Lite + external SD/NVMe boot from the SD/NVMe.  The A/B WKS layout
(`sdimage-rpi5.wks`) labels the rootfs partitions `rootfs-a`/`rootfs-b`
regardless of the underlying device, and the SWUpdate pre-install script
resolves the inactive slot by GPT label — so the same layout works for
eMMC, SD, and NVMe.  No CM5-eMMC-specific WKS is required.

### 3.3 SPI-NOR / mtd-utils
`mtd-utils` is installed.  CM5 carrier boards that use SPI-NOR flash for
boot config can use `flashcp`/`mtdinfo`; the RPi EEPROM itself is managed
via `rpi-eeprom-update` (not raw MTD).

### 3.4 A/B rollback watchdog
The OTA `boot-watchdog.sh` handles slot-confirmation/rollback.  The
hardware watchdog (`/dev/watchdog` via `bcm2835-wdt`, enabled in
`acadia-base.cfg` and driven by the `watchdog` daemon via
`acadia-services`) provides the true "boot-confirm-or-hardware-reset"
story.  `watchdog.service` is enabled via the
`80-acadia-watchdog.preset` systemd preset.

---

## 4. GPIO / Sensors / Industrial IO

- **1-Wire**: `dtoverlay=w1-gpio` (kas/common.yaml) + `CONFIG_W1_*`
  (acadia-base.cfg) + `owfs`/`owserver`/`owshell` installed.
- **PWM**: `dtoverlay=pwm` (kas/common.yaml) + `CONFIG_PWM_BCM2835`
  (acadia-base.cfg).
- **CAN**: `dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25`
  (kas/common.yaml) + `CONFIG_CAN_MCP251X` (acadia-base.cfg) +
  `can-utils` installed.
- **GPIO expander**: `CONFIG_GPIO_PCF857X`/`CONFIG_GPIO_PCA953X`
  (acadia-base.cfg) for MCP23017/PCF8574-class I2C expanders.
- **Environmental sensors**: `CONFIG_BME280*` (acadia-base.cfg) for
  BME280-class I2C temp/humidity/pressure sensors.
- **GPS/NMEA**: `gpsd` + `gpsd-conf` + `gps-utils` + `python3-pygps` +
  `python3-gpsd-py3` installed.  Configure `gpsd` to the UART the GPS is
  on (e.g. `/dev/ttyAMA0`) via `/etc/default/gpsd`.
- **libgpiod v2**: `libgpiod`/`libgpiod-tools`/`python3-gpiod` are
  installed; the character-device GPIO ABI (`gpiodetect`, `gpioget`,
  `gpioset`) is used rather than legacy sysfs.

---

## 5. Audio

- `alsa-utils` is installed, providing `aplay`, `arecord`, and
  `speaker-test` for audio-path bring-up.
- I2S/PWM audio HATs (Hifiberry-class) are enabled by adding the
  appropriate `dtoverlay=hifiberry-*` to `RPI_EXTRA_CONFIG`.  The
  overlays are shipped by meta-raspberrypi's `RPI_KERNEL_DEVICETREE_OVERLAYS`.

Audio self-test:

```
speaker-test -t wav -c 2
arecord -d 5 test.wav
aplay test.wav
```

---

## 6. Display

- `vc4-kms-v3d` (full KMS) is pinned per-board (`VC4DTBO = "vc4-kms-v3d"`)
  and `MACHINE_FEATURES:append = " vc4graphics"` enables the KMS stack.
- `kmscube` and `libdrm-tests` (provides `modetest`) are installed for
  display bring-up.
- Touchscreen/DSI panels: add the panel overlay (e.g.
  `dtoverlay=vc4-kms-dsi-7inch`) to `RPI_EXTRA_CONFIG`; `libinput`/
  `xinput` are available if a graphical profile is added.

Display bring-up:

```
modetest -M vc4 -c
kmscube
```

---

## 7. Power / Thermal

- **Fan/thermal control**: `lmsensors` is installed for sensor inspection.
  `acadia-services` provides a
  `fan-control.service`/`fan-control.timer` that reads the SoC thermal
  zone and sets the PWM fan duty cycle (Pi5 Active Cooler / PoE fan).
- **PoE HAT**: `dtoverlay=rpi-poe` (kas/common.yaml) enables the PoE+
  fan/power-negotiation.
- **Power/reset button**: `dtoverlay=gpio-shutdown` (kas/common.yaml)
  enables soft-shutdown via a GPIO button.
- **Thermal telemetry**: `thermal-check.service`/`thermal-check.timer`
  (acadia-services) logs SoC temperature and undervoltage/throttling
  warnings, mirroring the `disk-usage-check` pattern.
- **RTC battery header**: `dtoverlay=i2c-rtc,pcf8523` (kas/common.yaml) +
  `CONFIG_RTC_DRV_PCF8523` (acadia-base.cfg).  `acadia-services` provides
  `rtc-sync.service` (read RTC on boot) and `rtc-sync-shutdown.service`
  (write system time to RTC on shutdown) for accurate offline timestamps.

---

## 8. Security

### 8.1 Secure / verified boot
BCM2712/RPi5 supports OTP-based secure boot.  This is a provisioning
activity (burn OTP fuses, sign the bootloader/kernel) that must be scoped
against the existing A/B U-Boot flow (`UBOOT_ENV_SUFFIX=scr`), because
verified boot changes the trust chain the boot scripts rely on.  The
recipes here do not enable secure boot by default; a hardened deployment
should:
1. Provision the OTP secure-boot keys (Raspberry Pi secure-boot docs).
2. Sign the bootloader and kernel.
3. Keep the A/B slot selection but verify the boot chain.

### 8.2 dm-verity
dm-verity (or equivalent rootfs integrity checking) complements the
existing SWUpdate RSA-4096/SHA-256 signed-metadata verification with
runtime tamper detection.  It is not enabled by default because it
requires a verity hash tree per A/B slot and a verity-enabled initramfs;
a hardened deployment should add it on top of the A/B layout.

### 8.3 Hardware crypto / OTP
BCM2712 exposes OTP rows for unique IDs/key storage.  Reading/provisioning
these is a device-identity activity (relevant for IV&V device
attestation).  No recipe reads OTP by default; a deployment that needs
device attestation should add a service that reads the serial/OTP and
reports it to the attestation backend.

### 8.4 LICENSE_FLAGS_ACCEPTED policy
`kas/common.yaml` accepts the `commercial` flag for the HEVC/H.265 decode
path.  Each deployment profile should decide which flags it accepts
(e.g. HEVC, any closed firmware) and document that decision here.

### 8.5 SSH hardening
The `openssh` bbappend installs `acadia-hardening.conf` (key-only auth,
no root login, `AllowUsers rpi`) and the operator account is locked with
SSH-key-only access (`extrausers`).  Host keys are generated on first
boot by OpenSSH's default behaviour; baked-in keys are not shipped.

---

## 9. Debug / Diagnostics

- **JTAG/SWD**: `openocd` is installed.  BCM2712/RP1 JTAG access is
  typically host-side (the target exposes SWD/JTAG pads on the carrier);
  use `openocd -f interface/... -f target/...` from the host.  The
  RP2040 co-processor (Pico W) exposes SWD on its own pads.
- **Serial console**: `ENABLE_UART=1` is set.  The 40-pin header debug
  UART on the Pi5 is `ttyAMA10` at 115200 baud (see
  `SERIAL_CONSOLES` in the rpi5 machine conf).  On the CM5 IO Board the
  UART is on the 40-pin header via `dtoverlay=uart0`.
- **Combined bring-up checklist** (new-board validation):

```
# Display
modetest -M vc4 -c
kmscube

# Camera
rpicam-hello --list-cameras
v4l2-ctl --list-devices

# GPIO
gpiodetect

# I2C / SPI / CAN
i2cdetect -y 1
spidev_test -D /dev/spidev0.0
candump can0

# Thermal / power
cat /sys/class/thermal/thermal_zone0/temp
journalctl -t thermal-check -b
```

- **Boot-time diagnostics**: `dmesg-capture.service` (acadia-services)
  captures the kernel ring buffer to the journal.  `thermal-check.sh`
  additionally surfaces undervoltage/throttling messages (the Yocto
  equivalent of `vcgencmd get_throttled`, which is Raspbian-specific).

---

## 10. OTA / Update

- **Kernel/DTB/bootloader payloads**: the `.swu` package already includes
  the kernel and DTB (`@@KERNEL@@`/`@@DTB@@` in `sw-description`).  RPi
  EEPROM updates are handled out-of-band via `rpi-eeprom-update` (see
  §3.1); a SWUpdate handler for the EEPROM can be added when the platform
  defines one.
- **Rollback testing**: the bootcount + `boot-watchdog.sh` flow is
  covered by bats tests.  With the hardware watchdog now active
  (`/dev/watchdog`), a true boot-confirm-or-hardware-reset harness can be
  validated end-to-end.
- **CM5 OTA validation**: `cm5.yaml` reuses the rpi5 WKS/OTA flow.  The
  SWUpdate pre-install script resolves the inactive slot by GPT label
  (`rootfs-a`/`rootfs-b`), so it works on CM5 eMMC, SD, and NVMe boot
  paths without assuming `mmcblk0`.
