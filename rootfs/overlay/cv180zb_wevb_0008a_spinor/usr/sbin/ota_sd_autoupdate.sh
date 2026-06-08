#!/bin/sh
set -eu

LOG_TAG=ota_sd
LOCK_DIR=/tmp/ota_sd_autoupdate.lock
SD_ROOT=${1:-/mnt/sd}
REBOOT_AFTER_OTA=${OTA_SD_REBOOT:-1}

log()
{
	if [ -w /dev/console ]; then
		echo "[$LOG_TAG] $*" >/dev/console
	else
		echo "[$LOG_TAG] $*"
	fi
}

cleanup()
{
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

lock()
{
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		log "another OTA check is running"
		exit 0
	fi
	trap cleanup EXIT INT TERM
}

version_from_file()
{
	sed -n "s/^$1=//p" "$2" 2>/dev/null | head -n 1
}

current_version()
{
	version_from_file FW_VERSION /etc/firmware_version
}

current_board()
{
	version_from_file FW_BOARD /etc/firmware_version
}

is_pending_ota()
{
	pending=$(fw_printenv -n ota_pending 2>/dev/null || echo none)
	try=$(fw_printenv -n ota_try 2>/dev/null || echo 0)
	[ "$pending" != none ] && [ "$pending" != "" ] && [ "$try" != 0 ]
}

valid_pkg()
{
	pkg=$1
	[ -f "$pkg/upgrade.ready" ] || return 1
	[ -f "$pkg/manifest.env" ] || return 1
	[ -f "$pkg/boot.spinor" ] || return 1
	[ -f "$pkg/rootfs.spinor" ] || return 1
	return 0
}

find_pkg()
{
	root=$1
	if valid_pkg "$root/ota"; then
		echo "$root/ota"
		return 0
	fi

	for pkg in "$root"/ota-*; do
		[ -d "$pkg" ] || continue
		valid_pkg "$pkg" || continue
		echo "$pkg"
		return 0
	done

	return 1
}

check_pkg()
{
	pkg=$1
	manifest=$pkg/manifest.env
	board=$(current_board)
	version=$(current_version)

	# shellcheck disable=SC1090
	. "$manifest"

	if [ -n "${BOARD:-}" ] && [ -n "$board" ] && [ "$BOARD" != "$board" ]; then
		log "skip $pkg: board mismatch pkg=$BOARD current=$board"
		return 1
	fi

	if [ -n "${OTA_BOARD:-}" ] && [ -n "$board" ] && [ "$OTA_BOARD" != "$board" ]; then
		log "skip $pkg: ota board mismatch pkg=$OTA_BOARD current=$board"
		return 1
	fi

	if [ -n "${VERSION:-}" ] && [ -n "$version" ] && [ "$VERSION" = "$version" ]; then
		log "skip $pkg: same version $VERSION"
		return 1
	fi

	return 0
}

main()
{
	lock
	[ -d "$SD_ROOT" ] || { log "$SD_ROOT not found"; exit 0; }

	if is_pending_ota; then
		log "skip: OTA pending already exists"
		exit 0
	fi

	pkg=$(find_pkg "$SD_ROOT" || true)
	[ -n "$pkg" ] || { log "no ready OTA package in $SD_ROOT"; exit 0; }
	check_pkg "$pkg" || exit 0

	log "start OTA package $pkg"
	/usr/sbin/ota_update.sh "$pkg"
	sync

	if [ "$REBOOT_AFTER_OTA" = 1 ]; then
		log "OTA done, reboot"
		reboot
	else
		log "OTA done, reboot disabled"
	fi
}

main "$@"
