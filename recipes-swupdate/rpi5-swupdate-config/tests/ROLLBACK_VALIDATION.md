# OTA Rollback Validation (Task 45)

This records the target-required validation of the OTA rollback chain. The
tests in
`recipes-swupdate/rpi5-swupdate-config/tests/test_rollback_target.bats` run on
a booted A/B image and are **hardware-required** (they inspect u-boot env and
slot state).

## Mechanism under test

- A/B slots via `sdimage-rpi5.wks` (rootfs-a / rootfs-b).
- `pre-install.sh` identifies the inactive slot and backs up kernel/DTB.
- `post-install.sh` switches `root=`, writes `boot_state` with
  `tries_remaining=3 confirmed=false`, and sets U-Boot env for firmware-level
  rollback (tryboot).
- `swupdate-bootcheck.sh` + `boot-watchdog` confirm the update; if unhealthy it
  rolls back before network exposure.

## Required evidence (hardware)

To close task 45, run on a real target and record:

- Target: (rpi5-a / rpi5-b / cm5-1 / cm4-1)
- Firmware/image identifiers: OS image SHA-256 (`deploy/images/*/SHA256SUMS`),
  SWU bundle (`build/<board>-<ts>.swu`, verified via `make verify-swu`).
- Cases exercised:
  1. **Successful OTA** → new slot boots, `confirmed=true`, no rollback.
  2. **Interrupted OTA** (power loss mid-install) → previous slot still boots.
  3. **Unhealthy boot** (health check fails N times) → auto-rollback to the
     good slot within `tries_remaining` boots.
- Observed result recorded for each case.

The `test_rollback_target.bats` suite automates the checks once a booted image
is available; until hardware is attached it SKIPs (target-required, not a pass).
