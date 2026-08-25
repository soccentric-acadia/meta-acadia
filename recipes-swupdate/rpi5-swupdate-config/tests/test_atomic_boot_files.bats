#!/usr/bin/env bats
# test_atomic_boot_files.bats — atomic OTA boot-file updates (task 46).
#
# Pre-install/post-install must update boot files (cmdline.txt, boot_state,
# kernel/DTB .prev backups) atomically — write temp → fsync → rename — so a
# power loss mid-update can never leave a truncated or mismatched boot file
# that bricks the device.

setup() {
    POST="$(dirname "${BATS_TEST_DIRNAME}")/files/post-install.sh"
    PRE="$(dirname "${BATS_TEST_DIRNAME}")/files/pre-install.sh"
}

@test "post-install: cmdline.txt update is atomic (temp + fsync + rename)" {
    grep -qE 'cmdline\.txt\.tmp' "${POST}"
    grep -qE 'mv -f.*cmdline\.txt\.tmp.*cmdline\.txt' "${POST}"
}

@test "post-install: boot_state write is atomic" {
    grep -qE 'boot_state\.tmp' "${POST}"
    grep -qE 'mv -f.*boot_state\.tmp.*boot_state' "${POST}"
}

@test "post-install: no direct in-place sed -i on cmdline.txt" {
    # The previous version used sed -i which is NOT atomic on FAT/overlayfs.
    ! grep -qE 'sed -i.*cmdline\.txt' "${POST}"
}

@test "pre-install: kernel/DTB backup is atomic" {
    grep -qE '\.prev\.tmp' "${PRE}"
    grep -qE 'mv -f.*\.prev\.tmp.*\.prev' "${PRE}"
}

@test "swu-side and recipe-side post-install.sh are in sync" {
    SWU="$(dirname "${BATS_TEST_DIRNAME}")/../../swupdate/post-install.sh"
    diff -q "${POST}" "${SWU}"
}

@test "swu-side and recipe-side pre-install.sh are in sync" {
    SWU="$(dirname "${BATS_TEST_DIRNAME}")/../../swupdate/pre-install.sh"
    diff -q "${PRE}" "${SWU}"
}
