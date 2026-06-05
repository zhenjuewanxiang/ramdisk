#!/bin/sh
set -eu

OTA_META_DEV=${OTA_META_DEV:-/dev/mtd6}
OTA_META_TMP=${OTA_META_TMP:-/tmp/ota_meta.bin}

ota_current_slot()
{
	cmdline=$(cat /proc/cmdline 2>/dev/null || true)
	case "$cmdline" in
		*cvi_ota_slot=B*) echo B ;;
		*) echo A ;;
	esac
}

ota_other_slot()
{
	case "$1" in
		A) echo B ;;
		B) echo A ;;
		*) echo B ;;
	esac
}

ota_write_meta()
{
	active=${1:-A}
	pending=${2:-none}
	try_count=${3:-0}
	version=${4:-unknown}

	{
		printf 'CVIOTA1\n'
		printf 'active=%s\n' "$active"
		printf 'pending=%s\n' "$pending"
		printf 'try=%s\n' "$try_count"
		printf 'version=%s\n' "$version"
	} > "$OTA_META_TMP.txt"

	dd if=/dev/zero of="$OTA_META_TMP" bs=512 count=1 >/dev/null 2>&1
	dd if="$OTA_META_TMP.txt" of="$OTA_META_TMP" conv=notrunc >/dev/null 2>&1
	flashcp "$OTA_META_TMP" "$OTA_META_DEV"
	rm -f "$OTA_META_TMP" "$OTA_META_TMP.txt"
}

case "${1:-}" in
	write)
		ota_write_meta "${2:-A}" "${3:-none}" "${4:-0}" "${5:-unknown}"
		;;
	current-slot)
		ota_current_slot
		;;
	other-slot)
		ota_other_slot "${2:-$(ota_current_slot)}"
		;;
	*)
		echo "Usage: $0 write <active> <pending|none> <try> [version]" >&2
		exit 1
		;;
esac
