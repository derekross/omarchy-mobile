# SPDX-License-Identifier: MIT
# shellcheck shell=sh

# The worker runs with a deadline and opens the verified tty before binding the UDC.
stock_usb2_exchange() {
    exchange_bb=$1
    exchange_dir=$2
    exchange_gadget=$3
    exchange_mode=${4:-dummy}
    exchange_payload=/grizzly-inventory/usb2-test.bin

    exec 3<> "$exchange_dir/ttyGS0" || exit 10
    "$exchange_bb" stty raw -echo clocal -hupcl min 1 time 0 <&3 || exit 10
    printf 'a210000.dwc3\n' > "$exchange_gadget/UDC" &&
        IFS= read -r exchange_bound < "$exchange_gadget/UDC" &&
        [ "$exchange_bound" = a210000.dwc3 ] || exit 11
    printf '<6>grizzly-stock-inventory: USB2 diagnostic ready udc=a210000.dwc3\n' > /dev/kmsg
    if [ "$exchange_mode" = nv-reader ]; then
        /grizzly-inventory/nv-reader <&3 >&3 3>&- || exit 15
        "$exchange_bb" sleep 2 && exec 3>&- || exit 14
        return 0
    fi

    # One fixed-length binary comparison. Incoming bytes never become arguments.
    "$exchange_bb" timeout -k 1 32 "$exchange_bb" dd bs=19 count=1 iflag=fullblock \
        status=none of="$exchange_dir/request" <&3 || exit 12
    printf 'GRIZZLY-USB2-PROBE\n' |
        "$exchange_bb" cmp -s - "$exchange_dir/request" || exit 13
    printf 'GRIZZLY-USB2-OK\n' > "$exchange_dir/header" || exit 14
    "$exchange_bb" timeout -k 1 8 "$exchange_bb" cat "$exchange_dir/header" \
        "$exchange_payload" >&3 || exit 14
    # Give the USB requests queued behind the tty's write buffer time to finish.
    "$exchange_bb" sleep 2 && exec 3>&- || exit 14
}

# Called by stock inventory PID 1 after storage protection has passed.
stock_usb2_test() (
    usb_bb=$1
    usb_mode=${2:-dummy}
    usb_home=/grizzly-inventory
    usb_dir=$usb_home/usb2-runtime
    usb_configfs=$usb_dir/configfs
    usb_gadget=$usb_configfs/usb_gadget/grizzly-usb2-test
    usb_config=$usb_gadget/configs/c.1
    usb_acm=$usb_gadget/functions/acm.GS0
    usb_udc=/sys/class/udc/a210000.dwc3
    usb_manifest=$usb_home/usb2.modules
    usb_payload=$usb_home/usb2-test.bin
    usb_firmware=/lib/firmware/usb_phy_fw_2.27.0.bin
    usb_modules='nvmem-rmem.ko i2c-designware-core.ko i2c-designware-platform.ko google-eusb2-repeater.ko google_icc.ko google-usb-phy.ko dwc3-google.ko'
    usb_rw=no
    usb_mounted=no
    usb_gadget_created=no
    usb_changed_repeater=no
    usb_changed_dwc3=no
    usb_ep0_requested=no
    usb_exchange_timeout=48
    umask 077
    set -f

    usb_fail() {
        stock_inventory_log "USB2 diagnostic refused: $*"
        exit 1
    }

    case $usb_mode in
        dummy) ;;
        nv-reader)
            if [ ! -f "$usb_home/nv-verified" ] || [ -L "$usb_home/nv-verified" ] ||
               [ ! -f "$usb_home/nv-reader" ] || [ -L "$usb_home/nv-reader" ] ||
               [ ! -x "$usb_home/nv-reader" ] ||
               [ -e "$usb_home/usb2-ep0" ] || [ -L "$usb_home/usb2-ep0" ]; then
                usb_fail 'NV reader or verified storage inventory unavailable'
            fi
            usb_exchange_timeout=1140 ;;
        *) usb_fail 'unknown USB2 exchange mode' ;;
    esac

    usb_remount() {
        "$usb_bb" mount -t sysfs -o "remount,$1,nosuid,nodev,noexec" sysfs /sys
    }

    usb_write() {
        # shellcheck disable=SC2016
        "$usb_bb" timeout -k 1 3 "$usb_bb" sh -c 'printf "%s\n" "$2" > "$1"' usb2-write "$1" "$2"
    }

    usb_set_role() {
        usb_write "$1" "$2" && IFS= read -r usb_role < "$1" && [ "$usb_role" = "$2" ]
    }

    # shellcheck disable=SC2329
    usb_cleanup() {
        usb_status=$1
        trap - 0
        trap '' HUP INT TERM
        if [ "$usb_ep0_requested" = yes ] && ! stock_usb2_ep0_close; then
            stock_inventory_log 'USB2 EP0 trace capture or cleanup failed'
            usb_status=1
        fi
        if [ "$usb_gadget_created" = yes ]; then
            usb_bound=$("$usb_bb" cat "$usb_gadget/UDC") || usb_status=1
            case $usb_bound in
                a210000.dwc3) usb_write "$usb_gadget/UDC" '' || usb_status=1 ;;
                '') ;;
                *) usb_status=1 ;;
            esac
            "$usb_bb" rm -f "$usb_config/acm.GS0" || usb_status=1
            for usb_item in "$usb_acm" "$usb_config" "$usb_gadget/strings/0x409" "$usb_gadget"; do
                if [ -d "$usb_item" ]; then
                    "$usb_bb" rmdir "$usb_item" || usb_status=1
                fi
            done
        fi
        if [ "$usb_mounted" = yes ]; then
            "$usb_bb" umount "$usb_configfs" || usb_status=1
        fi
        if [ "$usb_changed_dwc3" = yes ] || [ "$usb_changed_repeater" = yes ]; then
            if [ "$usb_rw" = no ]; then
                usb_rw=yes
                usb_remount rw || usb_status=1
            fi
            if [ "$usb_changed_dwc3" = yes ]; then
                usb_set_role "$usb_dwc3" "$usb_previous_dwc3" || usb_status=1
            fi
            if [ "$usb_changed_repeater" = yes ]; then
                usb_set_role "$usb_repeater" "$usb_previous_repeater" || usb_status=1
            fi
        fi
        if [ "$usb_rw" = yes ]; then
            if usb_remount ro; then
                stock_inventory_log 'USB2 diagnostic teardown sysfs=ro'
            else
                stock_inventory_log 'USB2 diagnostic teardown failed to seal sysfs read-only'
                usb_status=1
            fi
        fi
        "$usb_bb" rm -f "$usb_dir/ttyGS0" "$usb_dir/request" "$usb_dir/header" || usb_status=1
        "$usb_bb" rmdir "$usb_configfs" "$usb_dir" || usb_status=1
        stock_inventory_log "USB2 diagnostic exit status=$usb_status"
        exit "$usb_status"
    }

    usb_find_roles() (
        set +f
        usb_roles=/sys/class/usb_role
        usb_dwc_entry=$usb_roles/a200000.usb3-role-switch
        [ -L "$usb_dwc_entry" ] && [ -r "$usb_dwc_entry/role" ] || return 1
        usb_dwc_path=$("$usb_bb" readlink -f "$usb_dwc_entry") || return 1
        [ "$usb_dwc_path" = "$usb_wrapper/usb_role/a200000.usb3-role-switch" ] || return 1
        usb_found=
        for usb_entry in "$usb_roles"/i2c-*-003e-eusb2-repeater-role-switch; do
            [ -L "$usb_entry" ] && [ -r "$usb_entry/role" ] || continue
            usb_name=${usb_entry##*/}
            usb_bus=${usb_name#i2c-}
            usb_bus=${usb_bus%-003e-eusb2-repeater-role-switch}
            case $usb_bus in ''|*[!0-9]*) continue ;; esac
            usb_path=$("$usb_bb" readlink -f "$usb_entry") || return 1
            # dev_set_name() updates the I2C device name after registration.
            case $usb_path in
                "$usb_i2c/i2c-$usb_bus/$usb_bus-003e/usb_role/$usb_name"|\
                "$usb_i2c/i2c-$usb_bus/i2c-$usb_bus-003e-eusb2-repeater/usb_role/$usb_name") ;;
                *) continue ;;
            esac
            [ -z "$usb_found" ] || return 1
            usb_found=$usb_entry/role
        done
        [ -n "$usb_found" ] || return 1
        printf '%s\n' "$usb_found"
    )

    [ -f "$usb_manifest" ] && [ ! -L "$usb_manifest" ] || usb_fail 'missing module manifest'
    # shellcheck disable=SC2086
    set -- $usb_modules
    printf '%s\n' "$@" | "$usb_bb" cmp -s - "$usb_manifest" || usb_fail 'unexpected module manifest'
    [ -f "$usb_firmware" ] && [ ! -L "$usb_firmware" ] &&
        [ "$("$usb_bb" sha256sum < "$usb_firmware")" = '723ff8e0e2aeda20c9b3b18277c93a6a69ddb4f45ff22a30838d7392ebb2b345  -' ] ||
        usb_fail 'D1 USB PHY firmware mismatch'
    if [ "$usb_mode" = dummy ]; then
        [ -f "$usb_payload" ] && [ ! -L "$usb_payload" ] &&
            [ "$("$usb_bb" stat -c %s "$usb_payload")" = 65536 ] &&
            [ "$("$usb_bb" sha256sum < "$usb_payload")" = '7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2  -' ] ||
            usb_fail 'synthetic payload mismatch'
    fi

    for usb_module do
        [ -f "/lib/modules/$usb_module" ] && [ ! -L "/lib/modules/$usb_module" ] ||
            usb_fail "missing stock module=$usb_module"
    done
    for usb_module do
        stock_inventory_log "USB2 diagnostic loading module=$usb_module"
        "$usb_bb" timeout -k 1 4 "$usb_bb" insmod "/lib/modules/$usb_module" > /dev/kmsg 2>&1 ||
            usb_fail "module load failed=$usb_module"
    done

    usb_i2c=$("$usb_bb" readlink -f /sys/bus/platform/devices/3a1cd000.i2c) || usb_fail 'I2C path unavailable'
    usb_wrapper=$("$usb_bb" readlink -f /sys/bus/platform/devices/a200000.usb3) || usb_fail 'DWC3 path unavailable'
    case $usb_i2c in /sys/devices/platform/*) ;; *) usb_fail 'I2C device path mismatch' ;; esac
    case $usb_wrapper in /sys/devices/platform/*) ;; *) usb_fail 'DWC3 device path mismatch' ;; esac
    [ "${usb_i2c##*/}" = 3a1cd000.i2c ] && [ "${usb_wrapper##*/}" = a200000.usb3 ] ||
        usb_fail 'USB platform device name mismatch'
    usb_dwc3=/sys/class/usb_role/a200000.usb3-role-switch/role
    for _usb_try in 1 2 3 4 5 6 7 8; do
        usb_repeater=$(usb_find_roles) && break
        "$usb_bb" sleep 1 || break
    done
    [ -n "$usb_repeater" ] || usb_fail 'stock USB role switches unavailable or ambiguous'
    if ! IFS= read -r usb_previous_repeater < "$usb_repeater" ||
       ! IFS= read -r usb_previous_dwc3 < "$usb_dwc3"; then
        usb_fail 'USB role read failed'
    fi
    case $usb_previous_repeater:$usb_previous_dwc3 in
        none:none|none:device|device:none|device:device) ;;
        *) usb_fail 'unexpected starting USB role' ;;
    esac
    [ "$("$usb_bb" readlink -f "$usb_home")" = "$usb_home" ] || usb_fail 'runtime path mismatch'
    case $("$usb_bb" stat -f -c %T "$usb_home") in tmpfs|ramfs) ;; *) usb_fail 'runtime path outside RAM' ;; esac
    "$usb_bb" mkdir -m 0700 "$usb_dir" || usb_fail 'diagnostic runtime unavailable'
    trap 'usb_cleanup "$?"' 0
    trap 'exit 1' HUP INT TERM
    "$usb_bb" mkdir "$usb_configfs" || usb_fail 'configfs mountpoint unavailable'

    stock_inventory_log "USB2 diagnostic starting roles repeater=$usb_previous_repeater dwc3=$usb_previous_dwc3"
    usb_rw=yes
    usb_remount rw || usb_fail 'cannot remount sysfs writable'
    if [ "$usb_previous_repeater" != device ]; then
        usb_changed_repeater=yes
        usb_set_role "$usb_repeater" device || usb_fail 'USB2 repeater role failed'
    fi
    if [ "$usb_previous_dwc3" != device ]; then
        usb_changed_dwc3=yes
        usb_set_role "$usb_dwc3" device || usb_fail 'DWC3 role failed'
    fi
    usb_remount ro || usb_fail 'cannot seal sysfs read-only'
    usb_rw=no
    stock_inventory_log 'USB2 diagnostic role requests complete sysfs=ro'

    # Stock DWC3 schedules the role transition instead of doing it in role_store.
    for _usb_try in 1 2 3 4 5 6 7 8; do
        [ -L "$usb_udc" ] && [ -r "$usb_udc/state" ] && break
        "$usb_bb" sleep 1 || break
    done
    [ -L "$usb_udc" ] && [ -r "$usb_udc/current_speed" ] &&
        [ "$("$usb_bb" readlink -f "$usb_udc")" = "$usb_wrapper/a210000.dwc3/udc/a210000.dwc3" ] ||
        usb_fail 'stock UDC unavailable or path mismatch'
    "$usb_bb" mount -t configfs -o nosuid,nodev,noexec configfs "$usb_configfs" || usb_fail 'configfs mount failed'
    usb_mounted=yes
    "$usb_bb" mkdir "$usb_gadget" || usb_fail 'gadget already present or cannot be created'
    usb_gadget_created=yes
    if ! { "$usb_bb" mkdir "$usb_gadget/strings/0x409" "$usb_config" "$usb_acm" &&
           printf '0x1d6b\n' > "$usb_gadget/idVendor" &&
           printf '0x0104\n' > "$usb_gadget/idProduct" &&
           printf 'high-speed\n' > "$usb_gadget/max_speed" &&
           printf 'Omamobile\n' > "$usb_gadget/strings/0x409/manufacturer" &&
           printf 'Grizzly USB2 Diagnostic\n' > "$usb_gadget/strings/0x409/product" &&
           printf 'grizzly-usb2-test\n' > "$usb_gadget/strings/0x409/serialnumber" &&
           "$usb_bb" ln -s "$usb_acm" "$usb_config/acm.GS0"; }; then
        usb_fail 'ACM gadget setup failed'
    fi

    usb_tty=/sys/class/tty/ttyGS0
    if ! { IFS= read -r usb_port < "$usb_acm/port_num" && [ "$usb_port" = 0 ] &&
           [ -L "$usb_tty" ] && [ "$("$usb_bb" readlink -f "$usb_tty")" = /sys/devices/virtual/tty/ttyGS0 ] &&
           IFS= read -r usb_devnum < "$usb_tty/dev"; }; then
        usb_fail 'ACM tty identity mismatch'
    fi
    if [ -e "$usb_acm/console" ]; then
        IFS= read -r usb_console < "$usb_acm/console" && [ "$usb_console" = 0 ] || usb_fail 'ACM console enabled'
    fi
    # shellcheck disable=SC2016
    "$usb_bb" awk '$1 == "ttyGS0" { console=1 } END { exit (console || !NR) }' /proc/consoles ||
        usb_fail 'ACM tty is a console or console list unavailable'
    # shellcheck disable=SC2016
    "$usb_bb" awk -F= -v dev="$usb_devnum" '
        $1 == "DEVNAME" && $2 == "ttyGS0" { names++ }
        $1 == "MAJOR" { major=$2; majors++ }
        $1 == "MINOR" { minor=$2; minors++ }
        END {
            exit (names != 1 || majors != 1 || minors != 1 || major !~ /^[1-9][0-9]*$/ ||
                  major+0 > 4095 || minor != "0" || major ":" minor != dev)
        }' "$usb_tty/uevent" || usb_fail 'ACM tty device number mismatch'
    usb_major=${usb_devnum%:*}
    "$usb_bb" mknod -m 0600 "$usb_dir/ttyGS0" c "$usb_major" 0 &&
        [ -c "$usb_dir/ttyGS0" ] &&
        [ "$("$usb_bb" stat -c '%a:%t:%T' "$usb_dir/ttyGS0")" = "$(printf '600:%x:0' "$usb_major")" ] ||
        usb_fail 'private ACM tty setup failed'

    if [ -e "$usb_home/usb2-ep0" ] || [ -L "$usb_home/usb2-ep0" ]; then
        if [ ! -f "$usb_home/usb2-ep0" ] || [ -L "$usb_home/usb2-ep0" ] ||
           [ ! -f "$usb_home/usb2-ep0.sh" ] || [ -L "$usb_home/usb2-ep0.sh" ]; then
            usb_fail 'EP0 trace fixture is incomplete'
        fi
        # shellcheck source=stock-usb2-ep0.sh
        . "$usb_home/usb2-ep0.sh"
        usb_ep0_requested=yes
        stock_usb2_ep0_start "$usb_bb" "$usb_dir/tracefs" || usb_fail 'cannot arm EP0 trace'
    fi
    usb_result=0
    "$usb_bb" timeout -k 1 "$usb_exchange_timeout" "$usb_bb" sh -c '
        . /grizzly-inventory/usb2-test.sh
        stock_usb2_exchange "$@"
    ' usb2-exchange "$usb_bb" "$usb_dir" "$usb_gadget" "$usb_mode" || usb_result=$?
    usb_speed=$("$usb_bb" cat "$usb_udc/current_speed") || usb_speed=unavailable
    usb_state=$("$usb_bb" cat "$usb_udc/state") || usb_state=unavailable
    case $usb_mode:$usb_result in
        nv-reader:0) stock_inventory_log "NV restricted reader acknowledged completion speed=$usb_speed state=$usb_state" ;;
        dummy:0) stock_inventory_log "USB2 diagnostic queued bytes=65536 speed=$usb_speed state=$usb_state" ;;
        *) stock_inventory_log "USB2 diagnostic exchange failed status=$usb_result speed=$usb_speed state=$usb_state" ;;
    esac
    exit "$usb_result"
)
