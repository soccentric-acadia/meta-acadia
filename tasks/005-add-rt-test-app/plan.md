# Task 005 (leaf) — Add `rt-test` test application — Acadia-OS

Parent task: `Acadia/tasks/005-add-rt-test-app/plan.md`
- **Task ID:** 005
- **Date:** 2026-09-21
- **Status:** planned — awaiting approval
- **Class:** affected (packaging only)

## Scope in this repository

Package the new Instrumentation standalone test application into the OS
image. **No kernel, image-recipe, or BSP change; no systemd change.**

### Exact change — `meta-acadia/recipes-instrumentation/instrumentation/instrumentation.bb`

One install line in `do_install`:

```bitbake
install -m 0755 ${B}/tools/instr-rt-test ${D}${bindir}/instr-rt-test
```

- The tools (`_ctrl`) install loop is **not** extended (no ctrl tool by
  design); the app is installed by its own explicit line — same pattern as
  any standalone tool (note `instr-istate-watchdog` is currently *not*
  packaged; rt-test is packaged because it must be on the target image).
- No `SYSTEMD_SERVICE` change: rt-test is a plain one-shot application run
  manually (typically as root over SSH on target). It has no unit, no
  service user, no sandboxing requirements.

### No other change

- `acadia-image.bb` untouched: `rt-tests` (task 002, decision D2) is already
  in the image and is reused only as an independent cross-check of rt-test's
  latency numbers.

## Affected interfaces

- Image content only: adds `/usr/bin/instr-rt-test`. No existing interface,
  schema, boot path, or service-set change.

## Expected validation role

1. `make build rpi5` succeeds; the image contains `/usr/bin/instr-rt-test`.
2. On the booted RT image (rpi5, 6.6.78-rt51): run `instr-rt-test` as root;
   the JSON result file is written and the stdout table prints.
3. Paired non-RT comparison run (stock pre-task-002 image or a fragment-less
   build) recorded in the parent's `validation.md` — the client-facing
   RT-advantage evidence.
4. Cross-check rt-test wakeup-latency against the shipped `cyclictest`.

## Risk to verify

- The install path/name must match the CMake target exactly
  (`${B}/tools/instr-rt-test` → `${bindir}/instr-rt-test`); a mismatch
  silently drops the app from the image (known recipe asymmetry).