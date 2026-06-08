#!/bin/sh
set -eu

SLOT=$(/usr/sbin/ota_meta.sh current-slot)
VERSION=$(sed -n 's/^FW_VERSION=//p' /etc/firmware_version 2>/dev/null | head -n 1)
if [ -z "$VERSION" ]; then
	VERSION=$(fw_printenv -n ota_version_pending 2>/dev/null || fw_printenv -n ota_version_active 2>/dev/null || echo unknown)
fi

fw_setenv ota_active "$SLOT" || true
fw_setenv ota_pending none || true
fw_setenv ota_try 0 || true
fw_setenv ota_version_active "$VERSION" || true
fw_setenv ota_version_pending "" || true
/usr/sbin/ota_meta.sh write "$SLOT" none 0 "$VERSION"

echo "OTA slot $SLOT marked good."
