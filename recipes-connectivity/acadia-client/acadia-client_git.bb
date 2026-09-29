SUMMARY = "Acadia Client daemon — gRPC client for the Acadia IV&V server"
DESCRIPTION = "C++ daemon that connects to an external Acadia server via gRPC, \
               runs hardware validation tests using Acadia-HAL, and reports results."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-Client"
LICENSE = "CLOSED"

# Follow the upstream repository's develop branch (same policy as webconfigd).
# develop carries the Yocto-ready CMake logic: it prefers an installed
# acadia-hal CMake package and falls back to a sibling Acadia-HAL source tree.
# That sibling is provided by the second git:// URI below, fetched next to the
# client so ${CMAKE_SOURCE_DIR}/../Acadia-HAL resolves as upstream intends.
#
# Use SSH transport.  BitBake converts this to 'ssh://git@github.com/...' —
# without ;user=git it connects as the container's local user (builder@) and
# auth fails with 'Permission denied (publickey)'.  The earlier form
# 'git://git@github.com/...;user=git' also worked but displayed a misleading
# fetch URL; the explicit ;user=git parameter is the clean spelling (issue #35).
SRC_URI = " \
    git://github.com/soccentric-acadia/Acadia-Client.git;protocol=ssh;user=git;branch=develop;name=client;destsuffix=git \
    git://github.com/soccentric-acadia/Acadia-HAL.git;protocol=ssh;user=git;branch=develop;name=hal;destsuffix=Acadia-HAL \
    file://acadia-client.service \
"

# Client pinned (OS-028: the recipe is now in the production image, so the
# build must be reproducible; bump this pin when client changes are validated).
# T-P05 (P-O02): pinned to develop HEAD — b702bdd carries CLI-355..357
# (statement-use-after-free fixes, watchdog join, per-process test spools).
# OS-072: 6bf0411 fixes the fmt formatting of std::atomic / toml::key that
# broke the aarch64 cross-compile.
# VB-2 (task 013): bumped to develop HEAD 79433fe — a CHANGELOG-only commit
# over 6bf0411, no functional diff; bumped anyway to close the "behind
# develop" gap exactly rather than by inspection only.
SRCREV_client = "79433fe60a73007cb61a23c2a1d5574bb47346bc"
#
# The embedded HAL sibling pins the SAME Acadia-HAL revision as
# acadia-hal_git.bb (T-P05: one HAL revision per build) — develop HEAD,
# which now exists as a standalone recipe pin too (OS-034 resolved).
SRCREV_hal = "f6fb89e7d6325aad2d8c97db6bf44b02c3bd8987"

# Required when multiple SCM fetchers are used (client + embedded HAL).
SRCREV_FORMAT = "client_hal"

PV = "1.0+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake systemd useradd

OECMAKE_SOURCEPATH = "${S}"

# Unit tests pull GTest in at configure time (find_package(GTest REQUIRED))
# but are never shipped in the target image — build without them instead of
# bloating the target sysroot.
OECMAKE_EXTRA_OECMAKE = "-DBUILD_TESTS=OFF"

# Cross-compilation guard for gRPC::grpc_cpp_plugin — same workaround as
# acadia-hal_git.bb (issue #48): gRPCConfig.cmake skips gRPCPluginTargets.cmake
# when CMAKE_CROSSCOMPILING, so the imported target does not exist and the
# unconditional get_target_property() calls fatal-error at configure time.
# Wrapping them in TARGET checks lets the find_program() fallbacks locate the
# host-native plugin via PATH.
#
#   - The pinned HAL sibling is frozen → sanity-check loudly on drift, like
#     acadia-hal_git.bb does.
#   - The client CMakeLists.txt floats on develop → best-effort only, so the
#     sed self-retires once upstream guards the call (the Acadia-Client
#     working tree carries exactly that fix for the next push).
do_configure:prepend() {
    CLIENT_CMAKE="${S}/CMakeLists.txt"
    if [ -f "${CLIENT_CMAKE}" ] && \
       ! grep -q 'if(TARGET gRPC::grpc_cpp_plugin)' "${CLIENT_CMAKE}" && \
       grep -q 'get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)' "${CLIENT_CMAKE}"; then
        sed -i \
            's|^\(\s*\)get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)$|\1if(TARGET gRPC::grpc_cpp_plugin)\n\1    get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)\n\1endif()|' \
            "${CLIENT_CMAKE}"
    fi

    HAL_PROTO_CMAKE="${WORKDIR}/Acadia-HAL/protos/CMakeLists.txt"
    if [ ! -f "${HAL_PROTO_CMAKE}" ]; then
        bbfatal "acadia-client: expected ${HAL_PROTO_CMAKE} (embedded HAL sibling) after do_unpack — SRC_URI layout changed?"
    fi
    if ! grep -q 'get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)' "${HAL_PROTO_CMAKE}"; then
        bbfatal "acadia-client: grpc-plugin sed pattern did not match in ${HAL_PROTO_CMAKE}. SRCREV_hal likely drifted; update the in-recipe sed."
    fi
    sed -i \
        's|^\(\s*\)get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)$|\1if(TARGET gRPC::grpc_cpp_plugin)\n\1    get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)\n\1endif()|' \
        "${HAL_PROTO_CMAKE}"
}

DEPENDS += "grpc grpc-native protobuf spdlog tomlplusplus yaml-cpp sqlite3"
RDEPENDS:${PN} = "grpc spdlog yaml-cpp libsqlite3"

# The embedded HAL sibling (see SRC_URI) compiles with -Werror, and HAL
# source ignores write()/read() return values in places — same suppression
# acadia-hal_git.bb needs.
CXXFLAGS:append = " -Wno-error=unused-result"

# The HAL is linked as a static archive and its gRPC objects reference abseil
# symbols that gRPC's shared libraries expose only transitively; let the
# linker follow DT_NEEDED entries — same as acadia-hal_git.bb.
LDFLAGS:append = " -Wl,--copy-dt-needed-entries"

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
