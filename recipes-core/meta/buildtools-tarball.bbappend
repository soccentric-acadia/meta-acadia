# buildtools-tarball is a pure host-tools SDK with no target architecture
# (TARGET_ARCH = "none"). It must NOT try to install machine-specific target
# packages.  kas/common.yaml appends `gdbserver perf trace-cmd` to
# TOOLCHAIN_TARGET_TASK so the real SDK/eSDK toolchain payload carries
# target-side debugging/profiling tools (feature.txt §8) — but buildtools
# inherits that append globally and dnf then fails to resolve the
# target-arch (e.g. cortexa76) packages against the nativesdk-only
# installroot, which made `make esdk-image` fail in
# buildtools-tarball:do_populate_sdk.  Strip them here so buildtools-tarball
# stays a host-tools-only SDK.
TOOLCHAIN_TARGET_TASK:remove = " gdbserver perf trace-cmd"
