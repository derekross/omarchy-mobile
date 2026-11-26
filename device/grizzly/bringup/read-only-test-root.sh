# SPDX-License-Identifier: MIT

# Runs after the v73 partition comparison and the read-only disk checks.
grizzly_test_root() (
    image=/grizzly-inventory/test-root.ext4
    target=/run/grizzly-test-root
    loop=/dev/loop0
    sys_loop=/sys/class/block/loop0
    mounted=no
    attached=no

    cleanup() {
        if [ "$mounted" = yes ]; then
            "$bb" umount "$target" || return 1
            mounted=no
        fi
        if [ "$attached" = yes ]; then
            "$bb" losetup -d "$loop" || return 1
            attached=no
        fi
    }
    trap 'cleanup || stock_inventory_log "test root cleanup failed"' EXIT

    [ -f "$image" ] && [ ! -L "$image" ] &&
        [ ! -e "$loop" ] && [ ! -L "$loop" ] &&
        [ ! -e "$sys_loop/loop/backing_file" ] &&
        IFS= read -r devnum < "$sys_loop/dev" && [ "$devnum" = 7:0 ] ||
        exit 1
    "$bb" mkdir "$target" && "$bb" mknod -m 0600 "$loop" b 7 0 &&
        "$bb" losetup -r "$loop" "$image" || exit 1
    attached=yes
    IFS= read -r backing < "$sys_loop/loop/backing_file" &&
        [ "$backing" = "$image" ] &&
        IFS= read -r ro < "$sys_loop/ro" && [ "$ro" = 1 ] || exit 1

    "$bb" mount -t ext4 -o ro,noload,nosuid,nodev "$loop" "$target" || exit 1
    mounted=yes
    # shellcheck disable=SC2016
    "$bb" awk -v target="$target" -v dev="$devnum" '
        $5 == target {
            found++
            for (i = 7; i <= NF && $i != "-"; i++) {}
            if ($3 != dev || $4 != "/" || $6 !~ /(^|,)ro(,|$)/ ||
                $(i+1) != "ext4" || $(i+2) != "/dev/loop0" || $(i+3) !~ /(^|,)ro(,|$)/)
                bad = 1
        }
        END { exit bad || found != 1 }' /proc/self/mountinfo || exit 1
    "$bb" chroot "$target" /bin/busybox sh /root-smoke || exit 1
    cleanup || exit 1
    [ ! -e "$sys_loop/loop/backing_file" ] || exit 1
    stock_inventory_log 'Grizzly test root passed ram=1 loop_ro=1 write_denied=1 detached=1'
)
