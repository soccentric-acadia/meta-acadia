# Acadia Instrumentation — plain CMake recipe (REQ §13).
# Clone the repo, run CMake, install the binaries and system files it ships.
SUMMARY = "Acadia Instrumentation on-device management and observability suite"
HOMEPAGE = "https://soccentric.example/instrumentation"
LICENSE = "CLOSED"

PV = "1.0.0+git${SRCPV}"
SRC_URI = "git://github.com/soccentric-acadia/Acadia-Instrumentation.git;protocol=ssh;user=git;branch=develop"
# Pinned — not AUTOREV. Two builds of the same release must produce the same
# bits; a floating branch is incompatible with an image that has an OTA/rollback
# story. Bump deliberately when releasing.
# Requires the commit that makes the Yocto cross build work end to end:
#  - instr_protos links Abseil's log_internal targets explicitly (protobuf 4.25's
#    generated map-field code calls Abseil's CHECK/LOG machinery; FindProtobuf
#    module-mode protobuf::libprotobuf does not propagate those deps — without
#    this every daemon dies with "undefined reference to
#    absl::lts_20240116::log_internal::...")
#  - binaries live in the build tree (${B}/daemons/..., ${B}/tools/...) which is
#    what do_install below installs — the old source-tree output_dir/ is gone
#  - catalog generates alarms_gen.h with the HOST alarmgen when cross compiling
#    (the bare target-name COMMAND gets rewritten by CMake to the target binary
#    and would die with "Exec format error" on the build host)
#  - the test suite honours -DBUILD_TESTING=OFF (no googletest dependency)
# T-P04: bumped to develop HEAD for the webconfigd.service.d/instr-socket.conf
# drop-in (SB-4 socket access) — this rev also carries StreamDeviceData, which
# closes the pinned-rev gap called out by SB-4/T-P05 for the telemetry path.
INSTR_SRCREV ?= "6f73cb7f27f9b0adfd6ab27a58c6e2e5f9ea5a63"
SRCREV = "${INSTR_SRCREV}"
S = "${WORKDIR}/git"

inherit cmake pkgconfig systemd

# Target libs. googletest deliberately absent: the test suite is gated on
# BUILD_TESTING (set OFF below), so nothing in a Yocto build needs it. abseil-cpp
# is listed explicitly (it is what the generated protobuf code links against) —
# protobuf/grpc stage it transitively, but naming it fails loudly if that changes.
DEPENDS = "grpc grpc-native protobuf protobuf-native abseil-cpp yaml-cpp openssl"

EXTRA_OECMAKE = "\
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
"

# catalog/CMakeLists.txt generates alarms_gen.h at build time. Cross-compiling,
# it runs the HOST alarmgen (resolved with find_program(NO_CMAKE_FIND_ROOT_PATH)
# in the source); the standard oe-core pattern stages it: a native variant of
# this same recipe, DEPENDS'd from the target. The native variant only needs the
# alarmgen binary — protoc/grpc_cpp_plugin come from protobuf-native/grpc-native
# which BBCLASSEXTEND already pulls as :class-native deps of the base DEPENDS.
BBCLASSEXTEND = "native"
DEPENDS:append:class-target = " instrumentation-native"

# Same workaround as acadia-hal_git.bb: gRPC carries Abseil as a private
# (non-propagated) dependency, so static archives built against gRPC/protobuf
# can end up with unresolved Abseil symbols at final link time (e.g. when
# protobuf is found via pkg-config and no absl CMake targets land on the link
# line). --copy-dt-needed-entries makes the linker follow transitive
# shared-library dependencies and resolve those references.
LDFLAGS:append = " -Wl,--copy-dt-needed-entries"

do_install:class-native() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/catalog/alarmgen ${D}${bindir}/alarmgen
}

FILES:${PN}:class-native = "${bindir}/alarmgen"
SYSTEMD_PACKAGES:class-native = ""
RDEPENDS:${PN}:class-native = ""
COMPATIBLE_MACHINE:class-native = ""

do_install() {
    install -d ${D}${bindir}
    for d in istate networkd monitord hardware faults alarms logmanager telemetry ota backup; do
        install -m 0755 ${B}/daemons/${d}/${d} ${D}${bindir}/instr-${d}
    done
    # tools/CMakeLists.txt defines all ten _ctrl executables in ONE directory
    # (tools/), so they land flat at ${B}/tools/<name> — not ${B}/tools/<name>/<name>.
    for t in istate_ctrl network_ctrl monitor_ctrl hardware_ctrl fault_ctrl alarm_ctrl \
             log_ctrl telemetry_ctrl ota_ctrl backup_ctrl; do
        install -m 0755 ${B}/tools/${t} ${D}${bindir}/${t}
    done
    # Standalone PREEMPT_RT demonstration app (task 005): not a daemon, no
    # unit, no ctrl tool — installed explicitly like any standalone tool.
    install -m 0755 ${B}/tools/instr-rt-test ${D}${bindir}/instr-rt-test
    # istate software watchdog (task 005): standalone observe-only tool with
    # its own unit (instr-istate-watchdog.service, SYSTEMD_SERVICE below) and
    # its own instr-watchdog user from the sysusers.d conf.
    install -m 0755 ${B}/tools/instr-istate-watchdog ${D}${bindir}/instr-istate-watchdog

    # System files shipped in the repo; daemon users come from sysusers.d at boot.
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/system/systemd/*.service ${D}${systemd_unitdir}/system/
    # T-P04 (SB-4): webconfigd joins the shared instr group via this drop-in
    # so istate's instr-configuration:instr-owned 0660 configuration socket is
    # connectable. Shipped only with Instrumentation — cm5 (no istate) keeps
    # webconfigd untouched.
    install -d ${D}${systemd_unitdir}/system/webconfigd.service.d
    install -m 0644 ${S}/system/systemd/webconfigd.service.d/instr-socket.conf \
        ${D}${systemd_unitdir}/system/webconfigd.service.d/instr-socket.conf
    install -d ${D}${sysconfdir}/sysusers.d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${S}/system/sysusers.d/instrumentation.conf ${D}${sysconfdir}/sysusers.d/
    install -m 0644 ${S}/system/tmpfiles.d/instrumentation.conf ${D}${nonarch_libdir}/tmpfiles.d/
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${S}/system/udev/70-instrumentation.rules ${D}${sysconfdir}/udev/rules.d/

    # Board descriptors under the plain names the daemons open.
    install -d ${D}${sysconfdir}/instrumentation
    for f in devices capabilities resource-profile; do
        install -m 0644 ${S}/descriptors/${f}-${INSTR_BOARD}.yaml \
            ${D}${sysconfdir}/instrumentation/${f}.yaml
    done
    if [ -f ${S}/descriptors/fault-rules-${INSTR_BOARD}.yaml ]; then
        install -m 0644 ${S}/descriptors/fault-rules-${INSTR_BOARD}.yaml \
            ${D}${sysconfdir}/instrumentation/fault-rules.yaml
    else
        install -m 0644 ${S}/catalog/fault-rules.yaml \
            ${D}${sysconfdir}/instrumentation/fault-rules.yaml
    fi

    install -d ${D}${datadir}/instrumentation/catalog \
                  ${D}${datadir}/instrumentation/defaults ${D}${datadir}/instrumentation/schemas
    install -m 0644 ${S}/catalog/alarms.yaml ${D}${datadir}/instrumentation/catalog/
    cp -r ${S}/system/defaults/. ${D}${datadir}/instrumentation/defaults/
    install -m 0644 ${S}/schemas/*.json ${D}${datadir}/instrumentation/schemas/

    # Application SDK: .proto files + CMake package config for building a client.
    install -d ${D}${datadir}/instrumentation/proto
    install -m 0644 ${S}/proto/*.proto ${D}${datadir}/instrumentation/proto/
    install -d ${D}${libdir}/cmake/instrumentation
    install -m 0644 ${B}/instrumentationConfig.cmake \
                    ${B}/instrumentationConfigVersion.cmake \
                    ${D}${libdir}/cmake/instrumentation/
}

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "instr-istate.service instr-networkd.service instr-monitord.service instr-hardware.service instr-faults.service instr-alarms.service instr-logmanager.service instr-telemetry.service instr-ota.service instr-backup.service instr-istate-watchdog.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Acadia-OS ships instrumentation on exactly these machines (acadia-image.bb
# appends it per-machine); skip everywhere else.
COMPATIBLE_MACHINE = "^(raspberrypi4-64|raspberrypi5)$"

INSTR_BOARD ?= "rpi-5"
INSTR_BOARD:raspberrypi4-64 = "rpi-4b"
INSTR_BOARD:raspberrypi5 = "rpi-5"

FILES:${PN} += "${sysusersdir} ${nonarch_libdir}/tmpfiles.d ${datadir}/instrumentation ${systemd_unitdir}/system/webconfigd.service.d/"