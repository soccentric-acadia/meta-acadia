# Task 005 validation — `rt-test` standalone RT test application (Acadia-OS)

- **Date:** 2026-09-21
- **Status:** pending — image build blocked on the Acadia-Instrumentation commit + SRCREV bump

## Evidence so far

- Recipe change reviewed: one explicit install line
  (`install -m 0755 ${B}/tools/instr-rt-test ${D}${bindir}/instr-rt-test`)
  following the same pattern as the daemon install loop directly above.
- No `SYSTEMD_SERVICE` change needed (plain one-shot binary, no unit by design).

## Pending

- `make build rpi5` after: Acadia-Instrumentation commit → `INSTR_SRCREV`
  bump → verify `/usr/bin/instr-rt-test` present in the built image.
- On-target run as root on the RT image + paired non-RT run (owner:
  platform team) — see parent validation.md for the full checklist.

## Skipped checks (with reason)

- Image build in this session — the recipe pins a SRCREV; building now would
  produce an image without the tool and prove nothing about the change.