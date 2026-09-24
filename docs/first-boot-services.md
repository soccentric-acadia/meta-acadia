# Acadia-OS boot notes

## First-Boot Services

Three one-shot systemd units prepare a freshly flashed Acadia card. They are
part of the image (not OTA-updated state), so they also run on the first boot
of each newly written slot where their conditions hold.

| Unit | Recipe | What it does | Ordering |
|---|---|---|---|
| `expand-rootfs.service` | `recipes-support/expand-rootfs` | Grows the last partition (`/home`) to fill the card; guarded by `ConditionPathExists=!/var/lib/expand-rootfs-done` so it runs once. | `DefaultDependencies=no`, `After=local-fs.target`, `Before=sysinit.target` |
| `rpi5-home-init.service` | `recipes-core/rpi5-home-init` | Initialises the persistent `/home` partition (issue #109: `RequiresMountsFor=/home`, so it waits for the mount itself, not just `local-fs.target`). | `After=local-fs.target`, `Before=getty.target sshd.service` |
| `acadia-data-init.service` | `recipes-core/acadia-data-init` | Creates `/home/acadia` (owner `acadia`, mode 0750) on the persistent partition. `var-lib-acadia.mount` then bind-mounts `/home/acadia` onto `/var/lib/acadia`, so the Client's identity, spool and results survive OTA slot switches (issue #114). | `After=local-fs.target rpi5-home-init.service`, `Before=var-lib-acadia.mount acadia-client.service` |

## Why `/var/lib/acadia` is a separate mount

`/var/lib/acadia` lives on the A/B rootfs, which is replaced on every
update. The bind mount from `/home/acadia` (persistent partition) makes it
survive; on target it shows up as its own mount in `findmnt`. WebConfig and
Instrumentation state live on `/pst` instead (task 003, T-P01).
