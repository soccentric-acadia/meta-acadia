# acadia-hal Security Policy (issue #47)

## Trust boundary

The HAL's C++ test binaries under `${bindir}` (e.g. `acadia-i2c-probe`,
`acadia-spi-flash`, `acadia-gpio-toggle`) talk to **hardware peripherals**
via `/dev/i2c-*`, `/dev/spidev*`, `/dev/gpiochip*`, `/dev/mem`, and
`/dev/watchdog`. These are privileged operations; misuse can:

- Brick the SoC (bad I2C clock on a power controller, watchdog bite).
- Destroy attached sensors (SPI flash write with wrong command).
- Leak secrets (reading EEPROM contents from secure elements).

`acadia-image` runs these as the unprivileged `rpi` user (member of
`sudo` group, not `root`). The `rpi` user is **not** in the `i2c`,
`spi`, or `gpio` groups, so the HAL's group-aware udev rules (if any)
are bypassed — the binaries must use `setuid`, `setgid`, or
`CAP_SYS_RAWIO` to access the hardware. **None of those are set in
the current recipe**.

## Operational rules

1. **Do not `chmod u+s` the HAL binaries from a recipe.** A future
   contributor who adds `chmod u+s` for convenience is shipping a
   setuid root binary that talks to raw hardware. The IV&V trust
   model requires explicit review before that change.
2. **Do not enable the setcap helpers in the systemd unit** (e.g.
   `AmbientCapabilities=CAP_SYS_RAWIO`). The systemd `acadia-hal`
   service runs as `rpi`; adding raw I/O capabilities turns the
   service into a hardware-rootkit target.
3. **Run the HAL binaries via sudo, not setuid.** The `rpi` user is
   in the `sudo` group. `sudo /usr/bin/acadia-i2c-probe` is auditable
   in the auth log; setuid is not.
4. **Drop `acadia-hal` from production images if possible.** The
   `acadia-image` recipe is a development + IV&V image. For field
   deployment, build a stripped image (e.g. `acadia-image-prod`) that
   omits `acadia-hal` entirely — only the `acadia-client` daemon is
   needed at the edge.

## CVE surface

Even though `acadia-hal` is `LICENSE = "MIT"`, the runtime
libraries it links against (`libgrpc++`, `abseil-cpp`, `libprotobuf`)
have published CVEs. The recipe inherits `cve-check.bbclass`
implicitly via `cmake`; the `cve-check` pass scans each dependency
and emits a warning when a published CVE affects a linked library.
The output lands in `tmp/deploy/cve/*` after every `do_build` and is
uploaded to the dashboard by the CI workflow.

## File-capability review

The recipe runs `setcap` nowhere. If a future patch adds it, the
following lines will land in the recipe:

```bitbake
# DO NOT MERGE without security review
do_install:append() {
    setcap cap_sys_rawio+ep ${D}${bindir}/acadia-*
}
```

A reviewer should reject that change. The `acadia-hal` package ships
to `/usr/bin` for the **operator's convenience** in the lab, not as
a privileged service binary. Production HAL access is mediated by
`acadia-client.service`, which itself is unprivileged and uses
gRPC over the network loopback.

## Update procedure

When updating the HAL (issue #22, #23, #24 — reproducibility of
upstream SRCREVs):

1. Run `devtool modify acadia-hal` to get a local checkout.
2. Verify the upstream commit's CVE status with `cve-check`.
3. Re-validate that no `setcap` or `setuid` call was added by
   `git diff` against the previous SRCREV.
4. Update the SRCREV; do not switch to `${AUTOREV}`.
5. Run the IV&V regression suite on a lab board before pushing
   the new image.
