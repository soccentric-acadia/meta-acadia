# Factory reset contract (T-P33, C06/C07)

One contract for every "factory reset" on an Acadia device. Before T-P33,
three different operations used the name: the WebConfig settings reset,
istate's `/pst` reset, and nothing at all on the OS side.

## Levels

| Level | Who can request it | Removed | Kept |
|---|---|---|---|
| `settings` (C06) | WebConfig admin (`mode: settings`, typed `RESET`), or HQ `FactoryReset` command | WebConfig config store, audit, alert history, TLS identity, cert store; Instrumentation config tree `/pst/system` and state `/pst/state` (istate reseeds image defaults) | WebConfig accounts, HQ pairing, `/pst/backup`, homes, factory identity |
| `settings+users` | WebConfig admin only (`mode: settings+users`, typed `RESET`) | everything in `settings`, plus every WebConfig account; first-boot reopens | same as `settings`, minus the accounts |
| `full` (C07 / RMA) | WebConfig admin only (`mode: full`, typed `WIPE`) | all of `/pst` except `/pst/factory`, i.e. WebConfig store, accounts, HQ pairing, Instrumentation config, state and backups; every home directory (operator SSH keys, `/home/acadia` = Acadia-Client data and HQ credentials); `/var/lib/webconfig-ota`; the persistent journal | factory identity `/pst/factory` (serial, claim code, class secret), the A/B root filesystems |

Remote (HQ) resets are limited to `settings`. Wiping accounts or
credentials needs someone on the device's local UI.

Re-provisioning the factory identity is a separate manufacturing operation
and not part of this contract. It is done with istate's `factory-reset`
console op or `acadia-provision-identity --force`.

## Mechanism

1. WebConfig first does its own in-process reset (settings modes only).
2. It writes `/pst/webconfig/factory-wipe.request` (JSON, `level` of
   `settings` or `full`) and reboots.
3. `acadia-factory-wipe.service` runs at early boot and performs the wipe
   for that level:
   - it runs after `/pst` and `/home` are mounted;
   - it runs before every consumer (webconfigd, applyd, istate, acadia-client,
     sshd.socket, journal flush);
   - it also runs before the units that recreate the layout
     (acadia-pst-init, rpi5-home-init, acadia-data-init), so the same boot
     re-provisions the wiped trees.
4. The request is removed only after a successful wipe. If power is cut
   mid-wipe, the wipe runs again on the next boot. Two cases are refused and
   nothing is wiped:
   - an unknown level (the request is kept for inspection);
   - a symlinked request (the request is removed).
5. A full wipe records its time in `/pst/factory/last-wipe` for RMA
   traceability.
6. `acadia-factory-provision` puts the claim-code mirror
   (`/pst/webconfig/claim-code`) back from the factory record. The device
   therefore comes back unclaimed and can only be claimed with the code on
   its label. WebConfig no longer deletes the mirror on first-boot, and it
   checks the code only while no account exists.

## Not covered

- SSH host keys live on the read-only root filesystem and survive a full
  wipe. Regenerating them per device needs host keys moved to `/pst`
  (follow-up).
- Secure erase: files are unlinked, not overwritten. On eMMC/SD, TRIM leaves
  recovery down to the flash controller.

## Tests

- `recipes-core/acadia-factory-wipe/tests/test_factory_wipe.bats`: each
  level, refusals, symlink containment and unit ordering.
- `recipes-core/acadia-factory-provision/tests/test_claim_code_mirror.bats`:
  the claim-code mirror is restored.
- Acadia-Configuration `full_factory_wipe_requires_wipe_confirmation_and_requests_boot_wipe`,
  `factory_reset_wipes_certs_and_alert_history`,
  `first_boot_requires_claim_code_when_provisioned`.
