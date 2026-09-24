#!/usr/bin/env bats
# test_readme_doc_first_boot_services.bats — regression test for
# README §12 documenting all first-boot services.
#
# Issue #114: README §12 said "Two one-shot systemd services" but
# a third service (acadia-data-init.service + var-lib-acadia.mount)
# exists and is on the boot path.  The fix updates §12 to "Three"
# and adds a short subsection describing acadia-data-init's
# bind-mount from /home/acadia → /var/lib/acadia.
#
# This test verifies:
#   - README §12 says "Three" (not "Two").
#   - The section names all three services.
#   - The bind mount from /home/acadia to /var/lib/acadia is
#     explained (without this, the on-target operator sees a
#     separate /var/lib/acadia mount but has no idea why).

setup() {
    # The Acadia-OS README was cleared (fc26467); the first-boot services
    # documentation now lives in the layer: docs/first-boot-services.md.
    SUT="${BATS_TEST_DIRNAME}/../../../docs/first-boot-services.md"
    [ -f "${SUT}" ] || { echo "missing ${SUT}" >&2; return 1; }
}

# --- Header: "Three" not "Two" ------------------------------------------

@test "README §12: heading says 'Three' first-boot services (issue #114)" {
    # The old README explicitly said "Two one-shot systemd services".
    # After the fix the heading must say "Three" — and not "Two".
    ! grep -qF "Two one-shot systemd services" "${SUT}"
    grep -qF "Three one-shot systemd units" "${SUT}"
}

# --- All three services are named ---------------------------------------

@test "README §12: lists rpi5-home-init.service" {
    grep -qF "rpi5-home-init.service" "${SUT}"
}

@test "README §12: lists expand-rootfs.service" {
    grep -qF "expand-rootfs.service" "${SUT}"
}

@test "README §12: lists acadia-data-init.service (issue #114)" {
    grep -qF "acadia-data-init.service" "${SUT}"
}

# --- Bind mount explained -----------------------------------------------

@test "README §12: documents the /home/acadia → /var/lib/acadia bind mount" {
    # The third service exists *because* of this bind mount; if the
    # README doesn't explain it, the reader has no idea why there
    # are two units (acadia-data-init.service + var-lib-acadia.mount)
    # for what looks like a single directory.
    grep -qE "bind.mount|bind-mount" "${SUT}"
    grep -qE "/home/acadia" "${SUT}"
    grep -qE "/var/lib/acadia" "${SUT}"
}

# --- Ordering note -----------------------------------------------------

@test "README §12: documents acadia-data-init.service ordering" {
    # The unit file specifies After=rpi5-home-init.service and
    # Before=acadia-client.service — the README must mention at
    # least one of these so a reader debugging "service didn't
    # run" can locate the right service.
    grep -qE "After=.*rpi5-home-init" "${SUT}"
}

# --- Section heading itself --------------------------------------------

@test "README §12: has a 'First-Boot Services' section" {
    grep -qE "^## First-Boot Services" "${SUT}"
}
