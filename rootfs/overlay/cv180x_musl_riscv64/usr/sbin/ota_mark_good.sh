#!/bin/sh
# Mark current A/B OTA slot as successfully booted.

set -u
PATH=/sbin:/usr/sbin:/bin:/usr/bin
log() { echo "[ota] $*"; }

command -v fw_printenv >/dev/null 2>&1 || exit 0
command -v fw_setenv >/dev/null 2>&1 || exit 0

slot=$(sed -n 's/.*cvi_ota_slot=\([AB]\).*/\1/p' /proc/cmdline)
[ -n "$slot" ] || slot=$(fw_printenv -n ota_active 2>/dev/null || echo A)

pending=$(fw_printenv -n ota_pending 2>/dev/null || echo none)
if [ "$pending" = "$slot" ]; then
	log "mark slot $slot good"
	fw_setenv ota_active "$slot"
	fw_setenv ota_pending none
	fw_setenv ota_try 0
	ver=$(fw_printenv -n ota_version_pending 2>/dev/null || true)
	[ -n "$ver" ] && fw_setenv ota_version_active "$ver"
	fw_setenv ota_version_pending ""
fi

exit 0
