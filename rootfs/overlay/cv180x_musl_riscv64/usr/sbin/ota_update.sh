#!/bin/sh
# A/B system OTA updater for spinor layouts using BOOT/ROOTFS and BOOT_BAK/ROOTFS_BAK.
# Usage: ota_update.sh <ota_dir>
# ota_dir must contain manifest.env, boot.spinor, rootfs.spinor.

set -eu
PATH=/sbin:/usr/sbin:/bin:/usr/bin

PKG_DIR=${1:-}
MANIFEST="$PKG_DIR/manifest.env"
BOOT_IMG="$PKG_DIR/boot.spinor"
ROOTFS_IMG="$PKG_DIR/rootfs.spinor"
TRY_COUNT=${OTA_TRY_COUNT:-3}

log() { echo "[ota] $*"; }
die() { echo "[ota] ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

[ -n "$PKG_DIR" ] || die "usage: ota_update.sh <ota_dir>"
[ -d "$PKG_DIR" ] || die "ota dir not found: $PKG_DIR"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
[ -f "$BOOT_IMG" ] || die "boot image not found: $BOOT_IMG"
[ -f "$ROOTFS_IMG" ] || die "rootfs image not found: $ROOTFS_IMG"

need_cmd fw_printenv
need_cmd fw_setenv
need_cmd flashcp
need_cmd awk
need_cmd wc
need_cmd sha256sum

# shellcheck disable=SC1090
. "$MANIFEST"

[ "${BOARD:-}" = "${OTA_BOARD:-cv180zb_wevb_0008a_spinor}" ] || die "board mismatch: ${BOARD:-unset}"
[ -n "${BOOT_SHA256:-}" ] || die "BOOT_SHA256 missing"
[ -n "${ROOTFS_SHA256:-}" ] || die "ROOTFS_SHA256 missing"

check_sha256() {
	file=$1
	expect=$2
	actual=$(sha256sum "$file" | awk '{print $1}')
	[ "$actual" = "$expect" ] || die "sha256 mismatch for $file"
}

mtd_by_name() {
	name=$1
	awk -v n="\"$name\"" '$4 == n { sub(":", "", $1); print "/dev/" $1; exit }' /proc/mtd
}

mtd_size() {
	name=$1
	hex=$(awk -v n="\"$name\"" '$4 == n { print $2; exit }' /proc/mtd)
	[ -n "$hex" ] || return 1
	echo $((0x$hex))
}

check_fit() {
	file=$1
	part=$2
	fsize=$(wc -c < "$file")
	psize=$(mtd_size "$part")
	[ -n "$psize" ] || die "partition not found: $part"
	[ "$fsize" -le "$psize" ] || die "$file ($fsize) larger than $part ($psize)"
}

active=$(fw_printenv -n ota_active 2>/dev/null || echo A)
case "$active" in
	B) target=B; boot_part=BOOT; rootfs_part=ROOTFS ;;
	*) target=B; boot_part=BOOT_BAK; rootfs_part=ROOTFS_BAK ;;
esac

# If currently active B, update A; otherwise update B.
if [ "$active" = "B" ]; then
	target=A
	boot_part=BOOT
	rootfs_part=ROOTFS
else
	target=B
	boot_part=BOOT_BAK
	rootfs_part=ROOTFS_BAK
fi

boot_mtd=$(mtd_by_name "$boot_part")
rootfs_mtd=$(mtd_by_name "$rootfs_part")
[ -n "$boot_mtd" ] || die "cannot find $boot_part in /proc/mtd"
[ -n "$rootfs_mtd" ] || die "cannot find $rootfs_part in /proc/mtd"

log "active=$active target=$target boot=$boot_part($boot_mtd) rootfs=$rootfs_part($rootfs_mtd)"
check_sha256 "$BOOT_IMG" "$BOOT_SHA256"
check_sha256 "$ROOTFS_IMG" "$ROOTFS_SHA256"
check_fit "$BOOT_IMG" "$boot_part"
check_fit "$ROOTFS_IMG" "$rootfs_part"

log "writing $boot_part"
flashcp -v "$BOOT_IMG" "$boot_mtd"
log "writing $rootfs_part"
flashcp -v "$ROOTFS_IMG" "$rootfs_mtd"

log "setting pending slot $target"
fw_setenv ota_pending "$target"
fw_setenv ota_try "$TRY_COUNT"
fw_setenv ota_version_pending "${VERSION:-unknown}"
sync
log "OTA installed. Reboot to try slot $target. It will auto-rollback if not marked good."
