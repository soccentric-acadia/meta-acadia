# Acadia Instrumentation — plain CMake recipe (REQ §13).
# Clone the repo, run CMake, install the binaries and system files it ships.
SUMMARY = "Acadia Instrumentation on-device management and observability suite"
HOMEPAGE = "https://soccentric.example/instrumentation"
LICENSE = "CLOSED"

PV = "1.0.0+git${SRCPV}"
SRC_URI = "git://github.com/soccentric-acadia/Acadia-Instrumentation.git;protocol=ssh;user=git;branch=develop"
SRCREV = "effb8bc3dbefd7c1577b962af06311e2d322af0a"
S = "${WORKDIR}/git"

inherit cmake pkgconfig systemd

# Target libs, plus host tools the build invokes: protoc + grpc_cpp_plugin
# (protos compile at build time) and alarmgen (below).
DEPENDS = "grpc grpc-native protobuf protobuf-native yaml-cpp openssl googletest"

EXTRA_OECMAKE = "-DCMAKE_BUILD_TYPE=Release"

# catalog/CMakeLists.txt runs the freshly-built alarmgen during the build to
# generate alarms_gen.h; cross-compiling, that must be a build-host binary.
# Standard oe-core pattern: a native variant of the same recipe.
BBCLASSEXTEND = "native"
DEPENDS:append:class-target = " instrumentation-native"
DEPENDS:append:class-native = " googletest-native"

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
    for t in istate_ctrl network_ctrl monitor_ctrl hardware_ctrl fault_ctrl alarm_ctrl \
             log_ctrl telemetry_ctrl ota_ctrl backup_ctrl; do
        install -m 0755 ${B}/tools/${t}/${t} ${D}${bindir}/${t}
    done

    # System files shipped in the repo; daemon users come from sysusers.d at boot.
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/system/systemd/*.service ${D}${systemd_unitdir}/system/
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
SYSTEMD_SERVICE:${PN} = "instr-istate.service instr-networkd.service instr-monitord.service instr-hardware.service instr-faults.service instr-alarms.service instr-logmanager.service instr-telemetry.service instr-ota.service instr-backup.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Acadia-OS ships instrumentation on exactly these machines (acadia-image.bb
# appends it per-machine); skip everywhere else.
COMPATIBLE_MACHINE = "^(raspberrypi4-64|raspberrypi5)$"

INSTR_BOARD ?= "rpi-5"
INSTR_BOARD:raspberrypi4-64 = "rpi-4b"
INSTR_BOARD:raspberrypi5 = "rpi-5"

FILES:${PN} += "${sysusersdir} ${nonarch_libdir}/tmpfiles.d ${datadir}/instrumentation"