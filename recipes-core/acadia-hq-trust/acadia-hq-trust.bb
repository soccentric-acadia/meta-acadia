SUMMARY = "Optional fleet-wide HQ trust material baked into the image (P-A10, OS-071)"
DESCRIPTION = "Installs /etc/acadia/hq-ca.pem and/or /etc/acadia/hq-config-pub.pem \
from files named at build time (local.conf / kas: ACADIA_HQ_CA_FILE, \
ACADIA_HQ_CONFIG_PUBKEY_FILE). Either may be left unset: devices can be \
provisioned on first use instead (WebConfig Provisioning page), and a \
device-provisioned file on /pst always takes precedence over these."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

ACADIA_HQ_CA_FILE ??= ""
ACADIA_HQ_CONFIG_PUBKEY_FILE ??= ""

# The inputs are host paths, not SRC_URI entries: rebuild when they change.
do_install[file-checksums] += "${@' '.join('%s:True' % f for f in (d.getVar('ACADIA_HQ_CA_FILE'), d.getVar('ACADIA_HQ_CONFIG_PUBKEY_FILE')) if f)}"
do_install[vardeps] += "ACADIA_HQ_CA_FILE ACADIA_HQ_CONFIG_PUBKEY_FILE"

inherit allarch

do_install() {
    # /etc/acadia is created only when something is installed into it: other
    # recipes own the directory, and an empty one here fails installed-vs-shipped.
    if [ -n "${ACADIA_HQ_CA_FILE}" ]; then
        install -d ${D}${sysconfdir}/acadia
        grep -q -- '-----BEGIN CERTIFICATE-----' "${ACADIA_HQ_CA_FILE}" || \
            bbfatal "ACADIA_HQ_CA_FILE ${ACADIA_HQ_CA_FILE} is not a PEM certificate"
        install -m 0644 "${ACADIA_HQ_CA_FILE}" ${D}${sysconfdir}/acadia/hq-ca.pem
    fi
    if [ -n "${ACADIA_HQ_CONFIG_PUBKEY_FILE}" ]; then
        install -d ${D}${sysconfdir}/acadia
        grep -q -- '-----BEGIN PUBLIC KEY-----' "${ACADIA_HQ_CONFIG_PUBKEY_FILE}" || \
            bbfatal "ACADIA_HQ_CONFIG_PUBKEY_FILE ${ACADIA_HQ_CONFIG_PUBKEY_FILE} is not a PEM public key"
        install -m 0644 "${ACADIA_HQ_CONFIG_PUBKEY_FILE}" ${D}${sysconfdir}/acadia/hq-config-pub.pem
    fi
}

FILES:${PN} = "${sysconfdir}/acadia/hq-ca.pem ${sysconfdir}/acadia/hq-config-pub.pem"
ALLOW_EMPTY:${PN} = "1"
