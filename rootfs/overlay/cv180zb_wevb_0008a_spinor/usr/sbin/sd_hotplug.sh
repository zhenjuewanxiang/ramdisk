#!/bin/sh
# Hotplug helper for removable SD/MMC partitions.
# First available partition is mounted at /mnt/sd for compatibility.

PRIMARY_MNT=${SD_PRIMARY_MNT:-/mnt/sd}
EXTRA_BASE=${SD_EXTRA_BASE:-/mnt/sd_parts}
LOG_TAG=sd_hotplug
ACTION=${1:-}
DEVNAME=${2:-${MDEV:-}}

log()
{
	echo "[$LOG_TAG] $*" >/dev/console 2>/dev/null || echo "[$LOG_TAG] $*"
}

is_sd_part()
{
	case "$1" in
		mmcblk*p[0-9]*) return 0 ;;
		*) return 1 ;;
	esac
}

is_mounted()
{
	grep -qs "^[^ ]* $1 " /proc/mounts
}

mounted_dev_at()
{
	awk -v mnt="$1" '$2 == mnt { print $1; exit }' /proc/mounts
}

mounted_path_for_dev()
{
	awk -v dev="$1" '$1 == dev { print $2; exit }' /proc/mounts
}

is_dev_mounted()
{
	grep -qs "^$1 " /proc/mounts
}

wait_for_dev()
{
	dev=$1
	i=0
	while [ $i -lt 3 ]; do
		[ -b "$dev" ] && return 0
		sleep 1
		i=$((i + 1))
	done
	return 1
}

mount_opts_for_type()
{
	case "$1" in
		vfat|msdos|exfat) echo "sync,noatime,utf8=1" ;;
		*) echo "sync,noatime" ;;
	esac
}

detect_fstype()
{
	dev=$1
	if command -v blkid >/dev/null 2>&1; then
		blkid -o value -s TYPE "$dev" 2>/dev/null && return 0
	fi
	echo auto
}

mount_one()
{
	dev=$1
	mnt=$2
	fstype=$(detect_fstype "$dev")
	opts=$(mount_opts_for_type "$fstype")

	mkdir -p "$mnt"
	if [ "$fstype" != auto ]; then
		if mount -t "$fstype" -o "$opts" "$dev" "$mnt" 2>/dev/null; then
			log "mounted $dev on $mnt type=$fstype"
			return 0
		fi
	fi

	if mount -o sync,noatime "$dev" "$mnt" 2>/dev/null; then
		log "mounted $dev on $mnt"
		return 0
	fi

	for t in vfat exfat ext4 ext3 ext2; do
		opts=$(mount_opts_for_type "$t")
		if mount -t "$t" -o "$opts" "$dev" "$mnt" 2>/dev/null; then
			log "mounted $dev on $mnt type=$t"
			return 0
		fi
	done

	return 1
}


trigger_ota_check()
{
	mnt=$1
	if [ -x /usr/sbin/ota_sd_autoupdate.sh ]; then
		/usr/sbin/ota_sd_autoupdate.sh "$mnt" >/dev/null 2>&1 &
	fi
}

mount_sd()
{
	devname=$1
	dev=/dev/$devname
	mnt=$PRIMARY_MNT

	is_sd_part "$devname" || return 0
	[ -b "$dev" ] || wait_for_dev "$dev" || { log "$dev not ready"; return 1; }
	if is_dev_mounted "$dev"; then
		old_mnt=$(mounted_path_for_dev "$dev")
		if [ -n "$old_mnt" ]; then
			umount "$old_mnt" 2>/dev/null || umount -l "$old_mnt" 2>/dev/null || true
			log "refreshed stale mount $dev on $old_mnt"
		fi
	fi

	mkdir -p "$PRIMARY_MNT" "$EXTRA_BASE"
	if is_mounted "$PRIMARY_MNT"; then
		mnt=$EXTRA_BASE/$devname
	fi

	if mount_one "$dev" "$mnt"; then
		trigger_ota_check "$mnt"
		return 0
	fi

	log "failed to mount $dev"
	rmdir "$mnt" 2>/dev/null || true
	return 1
}

try_promote_another_sd()
{
	is_mounted "$PRIMARY_MNT" && return 0
	for dev in /dev/mmcblk*p[0-9]*; do
		[ -b "$dev" ] || continue
		is_dev_mounted "$dev" && continue
		if mount_one "$dev" "$PRIMARY_MNT"; then
			trigger_ota_check "$PRIMARY_MNT"
			return 0
		fi
	done
	return 0
}

umount_sd()
{
	devname=$1
	dev=/dev/$devname
	primary_dev=$(mounted_dev_at "$PRIMARY_MNT")
	mnt=$EXTRA_BASE/$devname

	is_sd_part "$devname" || return 0
	if [ "$primary_dev" = "$dev" ]; then
		mnt=$PRIMARY_MNT
	fi

	if is_mounted "$mnt"; then
		umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
		log "unmounted $mnt"
	fi

	case "$mnt" in
		"$EXTRA_BASE"/*) rmdir "$mnt" 2>/dev/null || true ;;
	esac
	try_promote_another_sd
}

cleanup_stale_mounts()
{
	awk '$2 == "/mnt/sd" || $2 ~ "^/mnt/sd_parts/" { print $1 " " $2 }' /proc/mounts | while read dev mnt; do
		case "$dev" in
			/dev/mmcblk*p[0-9]*)
				[ -b "$dev" ] && continue
				umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
				log "cleaned stale mount $dev on $mnt"
				;;
		esac
	done
}

scan_sd()
{
	mkdir -p "$PRIMARY_MNT" "$EXTRA_BASE"
	cleanup_stale_mounts
	for dev in /dev/mmcblk*p[0-9]*; do
		[ -b "$dev" ] || continue
		is_dev_mounted "$dev" && continue
		mount_sd "$(basename "$dev")"
	done
	if is_mounted "$PRIMARY_MNT"; then
		trigger_ota_check "$PRIMARY_MNT"
	fi
}

case "$ACTION" in
	add) [ -n "$DEVNAME" ] && mount_sd "$DEVNAME" ;;
	remove) [ -n "$DEVNAME" ] && umount_sd "$DEVNAME" ;;
	scan) scan_sd ;;
	*) echo "Usage: $0 {add|remove <dev>|scan}" >&2; exit 1 ;;
esac
