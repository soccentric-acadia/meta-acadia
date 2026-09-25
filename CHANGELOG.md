# Changelog

## 2026-09-25 — Task 010: Client hardware-access privileges (VB-1)

- **Parent task:** `soccentric-acadia/Acadia` `tasks/010-hal-hardware-access-privileges/`.
- **User-visible behaviour:** `acadia-client.service` can now reach
  `/dev/i2c-*`, `/dev/spidev*`, `/dev/gpiochip*`, `/dev/tty*` (UART/RS-485),
  `/dev/video*`, raw CAN sockets, and the kernel log buffer — previously
  every HAL test touching real hardware failed with `EACCES`/`EPERM`.
- **Key files:**
  - `recipes-connectivity/acadia-udev-rules/acadia-udev-rules.bb` (new) +
    `files/61-acadia-hw-groups.rules` (new): creates the `i2c`/`spi`/`gpio`
    groups and assigns the matching device nodes to them.
  - `recipes-core/images/acadia-image.bb`: installs the new recipe.
  - `recipes-connectivity/acadia-client/files/acadia-client.service`: adds
    `SupplementaryGroups=` and `AmbientCapabilities=`/`CapabilityBoundingSet=`.
- **Compatibility / rollout notes:** groups and udev rules are created at
  image build / first boot, not retroactively via OTA; no already-deployed
  device is known to exist. No existing hardening directive was weakened.
- **Validation:** static review only (`systemd-analyze verify`, manual
  recipe review); no Yocto build and no HIL hardware run were possible in
  this session — see the parent task's `validation.md` for the full record
  and known gaps.
