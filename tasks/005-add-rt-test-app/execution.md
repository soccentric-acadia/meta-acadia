# Task 005 execution — Add `rt-test` standalone RT feature test application (parent)

- **Approval date:** 2026-09-21
- **Approved scope:** standalone test application `rt-test` in
  Acadia-Instrumentation (`tools/rt-test/`, installed as
  `/usr/bin/instr-rt-test`); one recipe install line in Acadia-OS; no
  systemd, no proto/gRPC/istate involvement. Runs on RT and non-RT kernels;
  prints a comparison table; stores a JSON result file per run.
- **Status:** implemented, validated (host), audited (85/100) — awaiting
  commit/push approval; on-target validation pending hardware

## Implementation checklist

- [x] Allocate task ID 005 (004 taken by the audit workflow); create task
      folders (parent + 2 affected leaves)
- [x] Write parent + leaf plans; obtain approval (2026-09-21, "go for it";
      scope revised pre-approval from daemon to standalone test app)
- [x] Acadia-Instrumentation: `tools/rt-test/` (rttest.h/rttest.cpp/main.cpp,
      unit tests, CMake wiring in tools/CMakeLists.txt + test/CMakeLists.txt)
- [x] Acadia-Instrumentation host gate: make build / test (343/343) /
      check-format / tidy — all green
- [x] Acadia-OS: instrumentation.bb install line for instr-rt-test (the
      recipe lives in the nested meta-acadia clone, gitignored from the
      Acadia-OS repo itself)
- [ ] Acadia-OS: make build rpi5 green — pending SRCREV bump at commit time
      (provider-first order; see Acadia-OS leaf execution.md)
- [ ] Validation: on-target RT + non-RT paired runs (owner: platform team,
      rpi5 hardware)
- [x] validation.md records host-side evidence in parent + leaves
- [ ] changelog entries (at commit time)

## Files changed (recorded as implemented)

- Acadia-Instrumentation: `tools/rt-test/{rttest.h,rttest.cpp,main.cpp}`,
  `tools/rt-test/test/test_rttest.cpp`, `tools/CMakeLists.txt`,
  `test/CMakeLists.txt`
- Acadia-OS: `meta/meta-acadia/recipes-instrumentation/instrumentation/instrumentation.bb`

## Interface / schema / dependency changes

- None. No proto, no contract, no schema, no systemd, no boot-path change.
  New binary only: `instr-rt-test`.

## Deviations from the approved plan

- None so far.

## Commands run and decisions

- Naming follows `instr-istate-watchdog` (standalone tool, only `instr_common`
  dependency); core/main split so statistics, identity parsing, JSON writing
  and verdict logic are unit-testable without real timing (CI-safe).
## Release-time steps executed (2026-09-21)

- [x] `INSTR_SRCREV` bumped to the pushed provider revision
      `3e885c2c72a0aa0746d1a913b02cf901bc736ed9` (Acadia-Instrumentation
      "rt-test: add standalone PREEMPT_RT demonstration app").
- [ ] `make build rpi5` + image inspection for `/usr/bin/instr-rt-test`
      (pending — long build; owner: platform team).
