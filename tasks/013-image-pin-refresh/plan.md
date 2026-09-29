# Task 013 — Image pin refresh (VB-2) — meta-acadia scope

Parent task: [`Acadia/tasks/013-image-pin-refresh/plan.md`](https://github.com/soccentric-acadia/Acadia/blob/develop/tasks/013-image-pin-refresh/plan.md)

## Scope in this repository

`recipes-connectivity/acadia-client/acadia-client_git.bb`: `SRCREV_client`
bumped from `6bf0411` to `79433fe` (current `Acadia-Client` develop HEAD — a
`CHANGELOG.md`-only commit over the previous pin, no functional diff).
`SRCREV_hal` in this recipe and in `recipes-bsp/acadia-hal/acadia-hal_git.bb`
were already at `Acadia-HAL`'s current develop HEAD (`f6fb89e`) — verified,
not changed.

## Local tests

Source-controlled config value; no build toolchain available in this
session. Verified against real git history (`git ls-remote`, a fully
unshallowed clone) rather than by inspection of the tracker's own numbers —
see the parent task's plan.md for the exact commands.

## Role in cross-repository validation

None — this is a self-contained pin bump.
