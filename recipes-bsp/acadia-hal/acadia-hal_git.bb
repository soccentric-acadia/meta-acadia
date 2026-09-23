SUMMARY = "Acadia Hardware Abstraction Layer"
DESCRIPTION = "HAL library for the Acadia platform, providing hardware abstraction interfaces."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-HAL"
LICENSE = "CLOSED"
# Upstream is a private repo; no LICENSE file is shipped.  BitBake
# requires a LIC_FILES_CHKSUM entry (issue #34).  We point at the
# recipe file itself, which is always present, and use a literal
# md5.  The reviewed security.md policy is used as the stable local
# checksum source until upstream publishes a real LICENSE file.
LIC_FILES_CHKSUM = "file://security.md;md5=1606e3c70e7eb33ddfd7fa686c3b5ff0"

SRC_URI = " \
    git://github.com/soccentric-acadia/Acadia-HAL.git;protocol=ssh;user=git;branch=develop \
    file://security.md \
"
# Pin the private upstream to avoid AUTOREV parse-time network lookups.
# T-P05 (P-O02): moved to the single develop pin — the old master pin
# (7184d94) predates the client-facing adapters the embedded-HAL sibling
# already used and most verdict-integrity fixes (OS-034). Same rev as
# acadia-client_git.bb's SRCREV_hal so exactly one HAL revision forms a build.
f6fb89e7d6325aad2d8c97db6bf44b02c3bd8987

PV = "1.0+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake

DEPENDS = "protobuf protobuf-native grpc grpc-native abseil-cpp pkgconfig-native"

OECMAKE_SOURCEPATH = "${S}"

# Explicitly point CMake at the host-native grpc_cpp_plugin so it is never
# resolved to the cross-compiled (aarch64) binary from the target sysroot.
OECMAKE_EXTRA_OECMAKE = "-DGRPC_CPP_PLUGIN=${STAGING_BINDIR_NATIVE}/grpc_cpp_plugin"

# When cross-compiling, gRPCConfig.cmake skips gRPCPluginTargets.cmake
# (guarded by `if(NOT CMAKE_CROSSCOMPILING)`), so gRPC::grpc_cpp_plugin is
# never defined and the unconditional get_target_property() call fatally
# errors.  Guard it with a TARGET check so the pkg-config fallback path
# (which uses find_program and is then overridden by -DGRPC_CPP_PLUGIN above)
# is taken instead.
#
# TODO: convert this sed to a proper SRC_URI patch once the upstream
# protos/CMakeLists.txt is in the in-tree cache (issue #48).  Until then,
# the sed must silently succeed on every SRCREV — the sanity check below
# fails the build loudly if upstream drifts and the regex no longer
# matches, instead of letting cmake emit a confusing error later.
do_configure:prepend() {
    CMAKE_FILE="${S}/protos/CMakeLists.txt"
    if [ ! -f "${CMAKE_FILE}" ]; then
        bbfatal "acadia-hal: expected ${CMAKE_FILE} after SRC_URI fetch — upstream layout changed?"
    fi
    if ! grep -q 'get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)' "${CMAKE_FILE}"; then
        bbfatal "acadia-hal: sed pattern did not match in ${CMAKE_FILE}. Upstream protos/CMakeLists.txt likely drifted; convert this in-recipe sed to a SRC_URI patch (issue #48)."
    fi
    sed -i \
        's|get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)|if(TARGET gRPC::grpc_cpp_plugin)\n        get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)\n    else()\n        find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin REQUIRED)\n    endif()|' \
        "${CMAKE_FILE}"
}

# Upstream source uses -Werror but has intentionally-ignored return values
# for write()/read()/system() calls in test code; suppress the error promotion
# for that specific warning only.
CXXFLAGS:append = " -Wno-error=unused-result"

# gRPC carries abseil as a private (non-propagated) dependency.  Static
# archives built against gRPC therefore have unresolved abseil symbols at
# final link time.  --copy-dt-needed-entries makes the linker follow
# transitive shared-library dependencies automatically, resolving those refs.
LDFLAGS:append = " -Wl,--copy-dt-needed-entries"

# The upstream CMakeLists.txt has no install() rules; install artifacts manually.
do_install() {
    # Shared libraries → runtime package
    install -d ${D}${libdir}
    find ${B}/lib -maxdepth 1 -name "*.so*" -exec install -m 0755 {} ${D}${libdir}/ \;

    # Static libraries → staticdev package
    find ${B}/lib -maxdepth 1 -name "*.a" -exec install -m 0644 {} ${D}${libdir}/ \;

    # Test / diagnostic executables → main package
    install -d ${D}${bindir}
    find ${B}/bin -maxdepth 1 -type f -exec install -m 0755 {} ${D}${bindir}/ \;

    # Public headers → dev package
    install -d ${D}${includedir}/${PN}
    find ${S}/src -name "*.h" -o -name "*.hpp" | while read f; do
        install -m 0644 "$f" ${D}${includedir}/${PN}/
    done

    # Issue #47: install the security policy doc into /usr/share/doc
    # so an operator reading 'dpkg -L acadia-hal' (or rpm -ql) sees it.
    install -d ${D}${docdir}/${PN}
    install -m 0644 ${WORKDIR}/security.md ${D}${docdir}/${PN}/security.md
}

# Unversioned .so files: upstream produces no versioned .so names.
# Move them to the main package (not -dev) and suppress the related QA
# checks.  Issue #52: the previous recipe also suppressed dev-elf on
# -dev, which masked any other packaging bug in the -dev package.  We
# now explicitly remove the .so files from -dev (and the static .a
# files, which BitBake auto-assigns to -dev), so dev-elf passes on
# the -dev package's *own* contents (the headers and the .cmake glue).
FILES:${PN}      += "${libdir}/*.so"
# Strip the unversioned .so out of -dev so dev-elf QA passes there
# without being suppressed.  Static archives also go in -dev by default;
# leave them so consumers can link statically.
FILES:${PN}-dev  = "${includedir} ${libdir}/cmake ${libdir}/pkgconfig ${datadir}/cmake ${datadir}/${BPN}"
# dev-so on the main package is the legitimate skip — we ship
# unversioned .so as a deliberate consequence of upstream layout.
INSANE_SKIP:${PN} += "dev-so"

# Issue #47: security policy.  See files/security.md (installed to
# /usr/share/doc/acadia-hal/security.md by the do_install step below).
# The HAL ships no setuid binaries and no file capabilities — neither
# the recipe nor the systemd units add them.  Future contributors must
# NOT add chmod u+s, setcap, or AmbientCapabilities without review.
PRIVATE_LIBS = "libacadia-hal*.so"
