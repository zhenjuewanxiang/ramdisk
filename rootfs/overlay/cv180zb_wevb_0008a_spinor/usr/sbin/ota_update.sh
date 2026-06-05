#!/bin/sh
set -eu

PKG=${1:?usage: ota_update.sh <ota_package_dir>}
META=$PKG/manifest.env
BOOT=$PKG/boot.spinor
ROOTFS=$PKG/rootfs.spinor
TRIES=${OTA_TRIES:-3}

[ -f "$META" ] || { echo "missing $META" >&2; exit 1; }
[ -f "$BOOT" ] || { echo "missing $BOOT" >&2; exit 1; }
[ -f "$ROOTFS" ] || { echo "missing $ROOTFS" >&2; exit 1; }

. "$META"

check_sha()
{
	file=$1
	expect=$2
	actual=$(sha256sum "$file" | awk '{print $1}')
	[ "$actual" = "$expect" ] || {
		echo "sha256 mismatch: $file" >&2
		echo "expect: $expect" >&2
		echo "actual: $actual" >&2
		exit 1
	}
}

check_sha "$BOOT" "$BOOT_SHA256"
check_sha "$ROOTFS" "$ROOTFS_SHA256"

ACTIVE=$(fw_printenv -n ota_active 2>/dev/null || /usr/sbin/ota_meta.sh current-slot)
case "$ACTIVE" in
	A) TARGET=B; BOOT_DEV=/dev/mtd3; ROOTFS_DEV=/dev/mtd5 ;;
	B) TARGET=A; BOOT_DEV=/dev/mtd2; ROOTFS_DEV=/dev/mtd4 ;;
	*) ACTIVE=A; TARGET=B; BOOT_DEV=/dev/mtd3; ROOTFS_DEV=/dev/mtd5 ;;
esac

echo "OTA active=$ACTIVE target=$TARGET version=${VERSION:-unknown}"
flashcp "$BOOT" "$BOOT_DEV"
flashcp "$ROOTFS" "$ROOTFS_DEV"

fw_setenv ota_active "$ACTIVE" || true
fw_setenv ota_pending "$TARGET" || true
fw_setenv ota_try "$TRIES" || true
fw_setenv ota_version_pending "${VERSION:-unknown}" || true
/usr/sbin/ota_meta.sh write "$ACTIVE" "$TARGET" "$TRIES" "${VERSION:-unknown}"

echo "OTA written to slot $TARGET. Reboot to test it."
