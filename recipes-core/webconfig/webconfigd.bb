SUMMARY = "SoCcentric on-device WebConfig daemon and UI"
DESCRIPTION = "Fetches, builds, and installs the WebConfig daemon, frontend, schemas, and Acadia board manifest."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-Configuration"
LICENSE = "CLOSED"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3382002c026d2dcb5817068a8f184313"

PV = "0.1.0+git${SRCPV}"
# Follow the upstream repository's default branch.
SRC_URI = "git://github.com/soccentric-acadia/Acadia-Configuration.git;protocol=ssh;user=git;branch=develop"
SRCREV = "30887b5a9eca298417652c38b7f35ff30a3ceccc"  # X-009: pinned — a reproducible image build must not track a branch
S = "${WORKDIR}/git"
B = "${S}"

PACKAGES = "${PN} webconfig-static webconfig-schemas webconfig-manifest"

inherit cargo pkgconfig systemd useradd

# The hq-agent crate uses prost-build, whose build script shells out to a host
# `protoc` to generate code from proto/acadiahq/agent.proto.  With the vendor
# tarball gone (live crates.io build), nothing supplies it — provide the native
# protobuf compiler and point prost-build at it explicitly, since PATH in
# do_compile does not include ${STAGING_BINDIR_NATIVE}.
DEPENDS += "protobuf-native"
export PROTOC = "${STAGING_BINDIR_NATIVE}/protoc"

CARGO_SRC_DIR = "${S}"
CARGO_BUILD_FLAGS = "--release"

# Build against the live crates.io registry, with dependency versions pinned by
# the repo's committed Cargo.lock.  No vendor tarball.
#
# CARGO_DISABLE_BITBAKE_VENDORING: cargo_common_do_configure otherwise writes
#   [source.crates-io] replace-with = "bitbake" into ${CARGO_HOME}/config,
#   pointing at an empty directory — cargo would fail to resolve any crate.
# do_compile[network]: bitbake blocks network in tasks by default (only
#   do_fetch/do_unpack are granted it), so cargo's crates.io downloads in
#   do_compile need the flag explicitly.
CARGO_DISABLE_BITBAKE_VENDORING = "1"
do_compile[network] = "1"
export CARGO_NET_OFFLINE = "false"

do_compile() {
    # NOTE: no edition/rust-version downgrade seds here anymore.  The build
    # uses the meta-lts-mixins scarthgap/rust toolchain (>= 1.86), which
    # handles the edition-2024 / rust-version 1.85+ crates natively.

    # oe-core's DEBUG_PREFIX_MAP injects `-fcanon-prefix-map` (requires GCC >= 13), but
    # the KAS build container's host gcc is Debian 12's gcc 12.2, which rejects it when
    # cc-rs compiles bundled C (ring / libsqlite3-sys).  It only canonicalises build
    # paths in debug info, so drop it from the compiler flags for this cargo build.
    export CFLAGS="$(printf '%s' "$CFLAGS" | sed -e 's/ -fcanon-prefix-map//g')"

    # MUST cross-compile for the target triple: without `--target`, cargo builds a
    # host (x86_64) binary, which cargo_do_install cannot find under the Yocto target
    # subdir and which the aarch64 image must not ship.  The linker for the poky
    # triple (the Yocto target-rust-ccld wrapper, which supplies --sysroot so
    # libc/CRT resolve) is already written into ${CARGO_HOME}/config by
    # cargo_common_do_configure; the repo's own .cargo/config.toml only defines
    # linkers for the Docker cross targets, so nothing conflicts.
    export RUSTFLAGS="${RUSTFLAGS}"
    cargo build --release --target ${RUST_HOST_SYS} --manifest-path ${S}/Cargo.toml
}

WEBCONFIG_USER = "webconfig"
WEBCONFIG_GROUP = "webconfig"
USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "-r -M -d /var/lib/webconfig -s /usr/sbin/nologin -g ${WEBCONFIG_GROUP} ${WEBCONFIG_USER}"
GROUPADD_PARAM:${PN} = "-r ${WEBCONFIG_GROUP}"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/target/${RUST_HOST_SYS}/release/webconfigd ${D}${bindir}/webconfigd

    install -d -o ${WEBCONFIG_USER} -g ${WEBCONFIG_GROUP} ${D}/var/lib/webconfig

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/meta-webconfig/recipes-core/webconfig/files/webconfigd.service \
        ${D}${systemd_system_unitdir}/webconfigd.service
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${S}/meta-webconfig/recipes-core/webconfig/files/webconfigd.env \
        ${D}${sysconfdir}/default/webconfigd

    install -d ${D}${datadir}/polkit-1/rules.d
    install -m 0644 ${S}/meta-webconfig/recipes-core/webconfig/files/50-webconfigd.polkit.rules \
        ${D}${datadir}/polkit-1/rules.d/50-webconfigd.rules

    install -d ${D}/usr/local/bin
    install -m 0755 ${S}/meta-webconfig/recipes-core/webconfig/files/pico-flash \
        ${D}/usr/local/bin/pico-flash

    install -d ${D}/usr/share/webconfig/static
    cp -a --no-preserve=ownership ${S}/frontend/. ${D}/usr/share/webconfig/static/
    install -d ${D}/usr/share/webconfig/schemas
    install -m 0644 ${S}/schemas/*.schema.json ${D}/usr/share/webconfig/schemas/
    install -d ${D}/usr/share/webconfig
    install -m 0644 ${S}/board-manifests/acadia.json \
        ${D}/usr/share/webconfig/board-manifest.json
}

SYSTEMD_SERVICE:${PN} = "webconfigd.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "ca-certificates"
RRECOMMENDS:${PN} = "systemd"

# The release profile (Cargo.toml, spec §2) mandates strip = "symbols" for size,
# so the produced binary is already stripped — opt out of Yocto's QA re-strip check.
INSANE_SKIP:${PN} = "already-stripped"

FILES:${PN} = "${bindir}/webconfigd /var/lib/webconfig ${systemd_system_unitdir}/webconfigd.service ${sysconfdir}/default/webconfigd ${datadir}/polkit-1/rules.d/50-webconfigd.rules /usr/local/bin/pico-flash"
FILES:webconfig-static = "/usr/share/webconfig/static"
FILES:webconfig-schemas = "/usr/share/webconfig/schemas"
FILES:webconfig-manifest = "/usr/share/webconfig/board-manifest.json"

RDEPENDS:webconfig-static = "${PN}"
RDEPENDS:webconfig-schemas = "${PN}"
RDEPENDS:webconfig-manifest = "${PN}"