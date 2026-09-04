SUMMARY = "SoCcentric on-device WebConfig daemon and UI"
DESCRIPTION = "Fetches, builds, and installs the WebConfig daemon, frontend, schemas, and Acadia board manifest."
HOMEPAGE = "https://github.com/soccentric-acadia/Acadia-Configuration"
LICENSE = "CLOSED"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3382002c026d2dcb5817068a8f184313"

PV = "0.1.0+git${SRCPV}"
SRC_URI = "git://github.com/soccentric-acadia/Acadia-Configuration.git;protocol=ssh;user=git;branch=develop"
# vendor.tar.gz is kept inside this layer (not via a path pointing outside the
# layer) so populate_sdk_ext can package it into the relocated SDK layer tree.
FILESEXTRAPATHS:prepend := "${THISDIR}:"
SRC_URI += " file://vendor.tar.gz"
SRCREV = "ad0bdde732c0fd6a792e9cbcfbb5007269a35435"
S = "${WORKDIR}/git"
B = "${S}"

PACKAGES = "${PN} webconfig-static webconfig-schemas webconfig-manifest"

inherit cargo pkgconfig systemd useradd

CARGO_SRC_DIR = "${S}"
CARGO_BUILD_FLAGS = "--release"
export CARGO_NET_OFFLINE = "0"

do_compile() {
    rm -rf ${S}/vendor
    cp -a ${WORKDIR}/vendor ${S}/vendor
    # NOTE: no edition/rust-version downgrade seds here anymore.  Those were a
    # workaround for oe-core Scarthgap's rust 1.75 and corrupted the vendored
    # .cargo-checksum.json entries ("checksum has changed" build failure).  The
    # build now uses the meta-lts-mixins scarthgap/rust toolchain (>= 1.86), which
    # handles the edition-2024 / rust-version 1.85+ crates natively.

    # oe-core's DEBUG_PREFIX_MAP injects `-fcanon-prefix-map` (requires GCC >= 13), but
    # the KAS build container's host gcc is Debian 12's gcc 12.2, which rejects it when
    # cc-rs compiles bundled C (ring / libsqlite3-sys).  It only canonicalises build
    # paths in debug info, so drop it from the compiler flags for this cargo build.
    export CFLAGS="$(printf '%s' "$CFLAGS" | sed -e 's/ -fcanon-prefix-map//g')"

    # MUST cross-compile for the target triple: without `--target`, cargo builds a
    # host (x86_64) binary, which cargo_do_install cannot find under the Yocto target
    # subdir and which the aarch64 image must not ship.  The source .cargo/config.toml
    # only defines linkers for the Docker cross targets, so point the linker at the
    # Yocto target-rust-ccld wrapper (which supplies --sysroot so libc/CRT resolve).
    export RUSTFLAGS="${RUSTFLAGS}"
    export CARGO_TARGET_AARCH64_POKY_LINUX_GNU_LINKER="${RUST_TARGET_CCLD}"
    cargo build --release --target ${RUST_HOST_SYS} --manifest-path ${S}/Cargo.toml \
        --config 'source.crates-io.replace-with="vendored-sources"' \
        --config 'source.vendored-sources.directory="${S}/vendor"'
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