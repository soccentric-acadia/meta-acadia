# Task 010 — Client hardware access privileges (VB-1) — meta-acadia scope

Parent task: [`Acadia/tasks/010-hal-hardware-access-privileges/plan.md`](https://github.com/soccentric-acadia/Acadia/blob/develop/tasks/010-hal-hardware-access-privileges/plan.md)

## Scope in this repository

`meta-acadia` owns the shipped `acadia-client.service` unit and the image
recipe set. It currently creates no `i2c`/`spi`/`gpio` groups and ships no
udev rules for those device classes, so those three groups are unusable even
if listed in a unit's `SupplementaryGroups=`.

## Affected interfaces / files

- New recipe `recipes-connectivity/acadia-udev-rules/acadia-udev-rules.bb`
  (+ `files/61-acadia-hw-groups.rules`): creates groups `i2c`, `spi`, `gpio`
  via `useradd.bbclass` `GROUPADD_PARAM`; installs udev rules assigning
  `SUBSYSTEM=="i2c-dev"`, `SUBSYSTEM=="spidev"`, and
  `KERNEL=="gpiochip[0-9]*"` to those groups, mode `0660`.
- `recipes-core/images/acadia-image.bb`: add `acadia-udev-rules` to
  `IMAGE_INSTALL:append`.
- `recipes-connectivity/acadia-client/files/acadia-client.service`: add
  `SupplementaryGroups=i2c spi gpio dialout video audio disk`,
  `AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_SYSLOG`,
  `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_SYSLOG`.

## Local tests

No Yocto build toolchain is available in this session. Validation here is a
static syntax/semantics review of the `.bb` recipe and the udev rules file
against upstream `useradd.bbclass`/`systemd-udev` conventions (see the
parent `validation.md` for the specifics and known gap: no HIL/on-image run).

## Role in cross-repository validation

This is the provider-side fix: `Acadia-Client`'s dev-reference unit file is
brought in line with this one, and `Acadia-HAL`'s existing device-touching
tests are the functional oracle that (on real hardware, out of scope for
this session) would confirm the fix.
