# SPDX-License-Identifier: MIT
set -f
bb=/grizzly-inventory/busybox
tools=/grizzly-systemd
control=/run/grizzly-systemd
backing=/run/grizzly-root
image=$backing/root.ext4
LD_LIBRARY_PATH=$tools/lib
export LD_LIBRARY_PATH
umask 077

log() { printf '<6>grizzly-systemd: %s\n' "$*" > /dev/kmsg; }
hold() {
    log "$*"
    while :; do "$bb" sleep 30; done
}

no_scsi() (
    set +f
    [ -d /sys/class/block ] || exit 1
    for disk in /sys/class/block/sd*; do
        [ ! -e "$disk" ] && [ ! -L "$disk" ] || exit 1
    done
)

ready() {
    [ -f "$control/ready" ] &&
        IFS= read -r timer < /run/grizzly-systemd-timer &&
        "$bb" kill -0 "$timer" &&
        IFS=' ' read -r uptime _ < /proc/uptime &&
        [ "${uptime%%.*}" -lt 570 ] && no_scsi
}

receive() (
    ready || exit 1
    "$bb" mkdir "$control/receiving" || exit 1
    partial=$backing/root.part
    trap '"$bb" rm -f "$partial"; "$bb" rmdir "$control/receiving"' EXIT
    trap 'exit 1' HUP INT TERM
    [ ! -e "$image" ] || exit 1
    "$tools/zstd" -d --sparse --memory=128MiB -q -o "$partial" || exit 1
    [ "$("$bb" stat -c %s "$partial")" = "$image_size" ] || exit 1
    digest=$("$tools/openssl" dgst -sha256 -r < "$partial") || exit 1
    [ "${digest%% *}" = "$image_sha" ] || { log 'RAM root digest refused'; exit 1; }
    "$bb" chmod 0400 "$partial" && "$bb" mv "$partial" "$image" || exit 1
    log 'Omarchy RAM image SHA-256 verified'
    printf '%s\n' GRIZZLY_ROOT_VERIFIED
)

usb_start() {
    config=/sys/kernel/config
    gadget=$config/usb_gadget/grizzly-root
    udc=a210000.usb
    "$bb" mount -t configfs configfs "$config" &&
        "$bb" mkdir -p "$gadget" "$gadget/configs/c.1/strings/0x409" "$gadget/strings/0x409" &&
        printf '%s\n' 0x1d6b > "$gadget/idVendor" &&
        printf '%s\n' 0x0104 > "$gadget/idProduct" &&
        printf '%s\n' 'Grizzly RAM root' > "$gadget/strings/0x409/product" &&
        printf '%s\n' 'Omarchy root transfer' > "$gadget/configs/c.1/strings/0x409/configuration" &&
        "$bb" mkdir "$gadget/functions/ncm.usb0" &&
        "$bb" ln -s "$gadget/functions/ncm.usb0" "$gadget/configs/c.1/ncm.usb0" ||
        { log 'USB NCM configfs setup failed'; return 1; }
    for wait in 1 2 3 4 5 6 7 8 9 10; do
        [ -e "/sys/class/udc/$udc" ] && break
        "$bb" sleep 1
    done
    [ -e "/sys/class/udc/$udc" ] ||
        { log "USB controller missing: $udc"; return 1; }
    printf '%s\n' "$udc" > "$gadget/UDC" &&
        IFS= read -r bound < "$gadget/UDC" && [ "$bound" = "$udc" ] ||
        { log "USB NCM bind failed: $udc"; return 1; }
    log "USB NCM bound: $udc"
    "$bb" ip link set lo up &&
        "$bb" ip link set usb0 up &&
        "$bb" ip -6 addr add fe80::b8e7/64 dev usb0 ||
        { log 'USB NCM link-local setup failed'; return 1; }
    tries=0
    while [ "$tries" -lt 30 ]; do
        if "$bb" ip -6 addr show dev usb0 |
            "$bb" awk '$1 == "inet6" && $2 == "fe80::b8e7/64" &&
                      !/tentative|dadfailed/ { found = 1 } END { exit !found }'; then
            log 'USB NCM link-local address ready'
            return 0
        fi
        "$bb" sleep 1
        tries=$((tries + 1))
    done
    log 'USB NCM link-local address did not become ready'
    return 1
}

boot() {
    [ "$$" -eq 1 ] || exit 1
    for wait in 1 2 3 4 5 6 7 8 9 10; do
        no_scsi && break
        "$bb" sleep 1
    done
    no_scsi || hold 'UFS diagnostic disk did not retire'
    log 'SCSI disks retired after UFS guard'
    available=$("$bb" awk '$1 == "MemAvailable:" { print $2 }' /proc/meminfo)
    [ "$available" -ge 12000000 ] || hold 'insufficient RAM for the Omarchy image'
    "$bb" mkdir -m 0700 "$control" "$backing" &&
        "$bb" mount -t tmpfs -o "mode=0700,nodev,nosuid,noexec,size=$image_size" tmpfs "$backing" &&
        "$bb" cp -a "$tools/systemd/." "$control/" || hold 'RAM root workspace failed'
    usb_start || hold 'USB NCM setup failed'
    "$tools/dropbear" -F -E -s -j -k -p '[fe80::b8e7%usb0]:2222' \
        -r "$tools/host-key" -c '/bin/sh /grizzly-systemd/root.sh ssh' &
    ssh_pid=$!
    : > "$control/ready"
    log 'waiting for authenticated Omarchy RAM root'
    dvfs=/sys/devices/platform/system-controller/display_dvfs
    if [ -r "$dvfs" ]; then
        (
            log 'display-dvfs: query start'
            if result=$("$bb" cat "$dvfs"); then
                printf '%s\n' "$result" | while IFS= read -r row; do log "display-dvfs: $row"; done
                log 'display-dvfs: query complete'
            else
                log 'display-dvfs: query failed'
            fi
        ) &
    fi
    wrapper=/sys/class/misc/grizzly-display-wrapper/dev
    if [ -r "$wrapper" ]; then
        (
            trigger=/dev/grizzly-display-wrapper
            if ! IFS=: read -r major minor < "$wrapper" ||
               ! "$bb" mknod -m 0200 "$trigger" c "$major" "$minor"; then
                log 'display-wrapper: could not create trigger'
                exit 1
            fi
            log 'display-wrapper: vote cycle start'
            if printf 'run\n' > "$trigger"; then
                log 'display-wrapper: vote cycle returned'
            else
                log 'display-wrapper: vote cycle failed'
            fi
            "$bb" rm "$trigger"
        ) &
    fi
    while [ ! -f "$control/handoff" ]; do "$bb" sleep 1; done
    "$bb" sleep 1
    ready && [ -f "$image" ] || hold 'handoff refused'
    "$bb" kill "$ssh_pid" || hold 'cannot stop USB receiver'
    wait "$ssh_pid" || :
    if [ ! -f "$control/sshd-live.conf" ]; then
        { printf '\n' > "$gadget/UDC"; } || hold 'cannot unbind USB receiver'
    fi
    finish_root
}

finish_root() {
    "$bb" mkdir /newroot &&
        "$bb" mknod -m 0600 /dev/loop0 b 7 0 &&
        "$bb" losetup -r /dev/loop0 "$image" &&
        [ "$("$bb" cat /sys/class/block/loop0/ro)" = 1 ] &&
        [ "$("$bb" cat /sys/class/block/loop0/loop/backing_file)" = "$image" ] &&
        "$bb" mount -t ext4 -o ro,noload,nosuid,nodev /dev/loop0 /newroot &&
        [ -x /newroot/usr/lib/systemd/systemd ] &&
        no_scsi || hold 'read-only Omarchy loop mount refused'
    export SYSTEMD_UNIT_PATH="$control/units"
    export SYSTEMD_GENERATOR_PATH="$control/empty"
    export SYSTEMD_ENVIRONMENT_GENERATOR_PATH="$control/empty"
    unset LD_LIBRARY_PATH
    for mount in /dev /proc /sys /run; do
        [ -d "/newroot$mount" ] || hold "Omarchy mountpoint missing: $mount"
    done
    log 'switching to isolated Omarchy systemd'
    for mount in /dev /proc /sys /run; do
        "$bb" mount --move "$mount" "/newroot$mount" || hold "cannot move $mount"
    done
    exec "$bb" switch_root /newroot /usr/lib/systemd/systemd --unit=grizzly-userspace.target
}

IFS=' ' read -r image_size image_sha < "$tools/root.raw.meta" || exit 1
case "${1:-}" in
    boot) boot ;;
    ssh)
        case "${SSH_ORIGINAL_COMMAND:-}" in
            status) ready && printf '%s\n' GRIZZLY_ROOT_READY ;;
            receive) receive ;;
            handoff)
                ready && [ -f "$image" ] && [ ! -d "$control/receiving" ] &&
                    : > "$control/handoff" && printf '%s\n' GRIZZLY_ROOT_HANDOFF_REQUESTED ;;
            *) exit 2 ;;
        esac ;;
    *) exit 2 ;;
esac
