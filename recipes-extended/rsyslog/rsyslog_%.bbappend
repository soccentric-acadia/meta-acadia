# T-P29 (J03): rsyslog is the remote-syslog transport for WebConfig. Acadia
# keeps logs in journald; rsyslog only reads the journal (imjournal) and
# forwards when WebConfig drops a rule into /etc/rsyslog.d/ — it writes NO
# local /var/log files (SD/eMMC wear, and journald already stores them).
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
PACKAGECONFIG:append = " imjournal"

# The imjournal PACKAGECONFIG ships /etc/rsyslog.d/imjournal.conf with a bare
# `$ModLoad imjournal`; our rsyslog.conf already loads it with a state file
# (so a restart does not re-forward the whole journal). Loading it twice is
# an error — drop the recipe's snippet.
do_install:append() {
    rm -f ${D}${sysconfdir}/rsyslog.d/imjournal.conf
}
