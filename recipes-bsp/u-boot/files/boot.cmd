# boot.cmd — A/B OTA rollback for Raspberry Pi 5 / CM5 (closes C1)
#
# Compiled to boot.scr by mkimage via UBOOT_ENV/UBOOT_ENV_SUFFIX=scr in
# kas/common.yaml. U-Boot reads the kernel command line from the FDT
# (chosen/bootargs, populated by RPi firmware from cmdline.txt) and
# boots the matching slot.
#
# Bootcount flow:
#   1. First boot: uboot.env is absent on /boot. We saveenv with the
#      canonical defaults (bootlimit=3, altbootcmd toggles upgrade_available
#      and zeroes bootcount, upgrade_available=0, bootcount=0).
#   2. On every subsequent boot, if upgrade_available=1, we increment
#      bootcount and saveenv. If bootcount >= bootlimit, we run
#      altbootcmd, which clears upgrade_available and zeros bootcount —
#      effectively rolling back to the previous slot (since cmdline.txt
#      still points at the *old* PARTUUID).
#   3. On a healthy boot, swupdate-bootcheck.service triggers
#      bootcount-reset.service, which sets upgrade_available=0. The
#      counter stops accumulating.
#
# This file is a U-Boot Hush script (NOT bash).  See
# https://u-boot.readthedocs.io/en/latest/usage/cmdline.html and
# doc/README.bootcount in the U-Boot tree.

# On first ever boot, initialise the env so subsequent boots have a
# well-defined bootcount/altbootcmd/upgrade_available state.
if test ! -e mmc 0:1 uboot.env; then
    setenv bootlimit 3
    setenv altbootcmd "setenv upgrade_available 0; setenv bootcount 0; run bootcmd"
    setenv upgrade_available 0
    setenv bootcount 0
    saveenv
fi

# Pull bootargs (incl. root=PARTUUID) from the FDT chosen node — RPi
# firmware populates this from cmdline.txt.
fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs

# Load the kernel image from p1 (/boot).
fatload mmc 0:1 ${kernel_addr_r} Image

# If an update is pending, tick the bootcount and trip altbootcmd
# when we exceed bootlimit. altbootcmd clears upgrade_available, so
# the next reboot starts fresh.
if test "${upgrade_available}" = "1"; then
    setexpr.b bootcount ${bootcount} + 1
    saveenv
    if test ${bootcount} -ge ${bootlimit}; then
        echo "bootcount ${bootcount} >= ${bootlimit}, running altbootcmd"
        run altbootcmd
    fi
fi

booti ${kernel_addr_r} - ${fdt_addr}
