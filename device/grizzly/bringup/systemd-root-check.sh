# SPDX-License-Identifier: MIT
set -eu

fail() {
    printf '<3>grizzly-systemd: %s\n' "$*" > /dev/kmsg
    exit 1
}

if [ "$#" -ne 0 ]; then
    [ "$#" -eq 1 ] && [ "$1" = status ] && [ "${SSH_ORIGINAL_COMMAND:-}" = status ] || exit 2
fi

[ "$(cat /proc/1/comm)" = systemd ] &&
    [ "$(readlink /proc/1/exe)" = /usr/lib/systemd/systemd ] || fail 'PID 1 is not systemd'
[ "$(findmnt -n -o SOURCE,FSTYPE /)" = '/dev/loop0 ext4' ] &&
    findmnt -n -o OPTIONS / | grep -Eq '(^|,)ro(,|$)' || fail 'root mount did not verify'
[ "$(cat /sys/class/block/loop0/ro)" = 1 ] &&
    [ "$(cat /sys/class/block/loop0/loop/backing_file)" = /run/grizzly-root/root.ext4 ] &&
    [ "$(findmnt -n -o FSTYPE /run/grizzly-root)" = tmpfs ] || fail 'root is not a read-only RAM loop'
for disk in /sys/class/block/sd*; do
    [ ! -e "$disk" ] && [ ! -L "$disk" ] || fail 'unexpected SCSI disk'
done
IFS= read -r timer < /run/grizzly-systemd-timer
kill -0 "$timer" && [ "$(readlink "/proc/$timer/exe")" = '/grizzly-systemd/return (deleted)' ] ||
    fail 'return helper missing after switch_root'
if [ "$#" -eq 1 ]; then
    printf '%s\n' 'GRIZZLY_LIVE_SSH_PASS pid1=systemd root=ext4 ro=1 ram=1 scsi_disks=0 timer=1'
    exit 0
fi
if ( : > /.grizzly-write-probe ); then fail 'root accepted a write'; fi
for unit in omamobile-firstboot.service omamobile-boot-success.service omamobile-usb-rescue.service; do
    [ "$(systemctl show --value -p LoadState "$unit")" = not-found ] || fail "unexpected unit $unit"
done
packages=$(pacman -Q omarchy omamobile-shell omamobile-omarchy hyprland) || fail 'Omarchy packages missing'
printf '%s\n' "$packages" | while IFS= read -r pkg; do
    printf '<6>grizzly-systemd: package %s\n' "$pkg" > /dev/kmsg
done
printf '<6>GRIZZLY_SYSTEMD_PASS pid1=systemd root=ext4 ro=1 ram=1 write_denied=1 scsi_disks=0 timer=1\n' > /dev/kmsg
