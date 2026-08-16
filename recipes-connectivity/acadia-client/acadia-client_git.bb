SUMMARY = "Acadia Client daemon — gRPC client for the Acadia IV&V server"
DESCRIPTION = "C++ daemon that connects to an external Acadia server via gRPC, \
               runs hardware validation tests using Acadia-HAL, and reports results."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-Client"
LICENSE = "CLOSED"

# Use SSH transport explicitly.  The previous form
# 'git://git@github.com/...;protocol=ssh;user=git' was contradictory —
# the git:// scheme implies the unauthenticated git daemon (port 9418),
# but ;protocol=ssh switched the transport to SSH; ;user=git is only
# meaningful for the git:// protocol.  BitBake accepts the combination
# but the user=git part is silently ignored, and the URL displayed in
# fetch logs is misleading.  Use a clean SSH URL (issue #35).
SRC_URI = " \
    git://github.com/soccentric-acadia/Acadia-Client.git;protocol=ssh;branch=release \
    file://acadia-client.service \
    file://0001-fix-grpc-cpp-plugin-cross-compile.patch \
"
# TODO: replace with the real commit SHA once the upstream repo exists:
#   SRCREV = "<40-char-sha>"
# Using a hardcoded placeholder avoids a parse-time network fetch (AUTOREV
# forces BitBake to contact the remote during parsing, breaking offline builds).
# The placeholder SHA below was chosen as an unguessable-but-fixed value
# that will fail the fetch loudly if the upstream repo is wired up
# without the real SHA being substituted.  Issue #61.
SRCREV = "0000000000000000000000000000000000000000"

PV = "1.0+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake systemd useradd

OECMAKE_SOURCEPATH = "${S}"

DEPENDS += "grpc grpc-native protobuf spdlog tomlplusplus yaml-cpp sqlite3"
RDEPENDS:${PN} = "grpc spdlog yaml-cpp libsqlite3"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "-r -s /sbin/nologin -d /var/lib/acadia -g acadia acadia"
GROUPADD_PARAM:${PN} = "acadia"

SYSTEMD_SERVICE:${PN}     = "acadia-client.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/acadia-client.service \
                    ${D}${systemd_system_unitdir}/acadia-client.service
}

FILES:${PN} += "${systemd_system_unitdir}/acadia-client.service"
