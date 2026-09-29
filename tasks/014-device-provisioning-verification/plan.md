# Task 014 — Device provisioning verification (VB-3) — meta-acadia scope

Parent task: [`Acadia/tasks/014-device-provisioning-verification/plan.md`](https://github.com/soccentric-acadia/Acadia/blob/develop/tasks/014-device-provisioning-verification/plan.md)

## Scope in this repository

New recipe `recipes-connectivity/acadia-module-registry/acadia-module-registry.bb`
(+ `files/modules.yaml`, vendored from `Acadia-HAL@f6fb89e`): installs the
HAL module registry at `/etc/acadia/modules.yaml`, matching
`Acadia-Client`'s compiled-in default `modules_yaml_path`. Added to
`recipes-core/images/acadia-image.bb`'s `IMAGE_INSTALL:append`.

## Local tests

No Yocto build toolchain available in this session — validated by
confirming the installed path matches the Client's default exactly, and
that the Client already handles a missing/degraded registry gracefully (so
this addition is purely additive, no behavior-change risk).

## Role in cross-repository validation

Closes the on-device half of VB-3. The `client.conf` provisioning half was
verified already complete in `Acadia-Configuration` (no code change needed
there).
