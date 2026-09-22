#!/bin/bash
# reboot-tryboot.sh — postupdatecmd wrapper (OS-016).
#
# SWUpdate's postupdatecmd must reboot with the RPi firmware **tryboot** flag
# so the freshly installed slot is booted exactly once via autoboot.txt's
# boot_prefix_try. A kernel panic / hang on that boot consumes the tryboot
# flag and the firmware falls back to boot_prefix (the confirmed slot) with
# zero userspace involvement.
#
# `/sbin/reboot "0 tryboot"` propagates the reboot argument to the firmware,
# which interprets it as the tryboot flag for the next boot only.

exec /sbin/reboot "0 tryboot"