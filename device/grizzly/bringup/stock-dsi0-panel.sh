# SPDX-License-Identifier: MIT
# shellcheck shell=sh

panel_bus=3a1ce000.i2c
panel_other_buses='3a1ca000.i2c 3a1cd000.i2c 3bdcb000.i2c'
panel_i2c_driver=i2c_designware
panel_excluded=grizzly-panel-excluded

stock_panel_scope_i2c() (
    sys=$1
    platform=$sys/bus/platform
    seen=
    set +f
    [ -d "$platform/devices" ] && [ ! -e "$platform/drivers/$panel_i2c_driver" ] || return 1
    for device in "$platform/devices"/*; do
        name=${device##*/}
        compatible=
        if [ -e "$device/of_node/compatible" ]; then
            compatible=$("$bb" tr '\000' '\n' < "$device/of_node/compatible") || return 1
        fi
        case $name in
            "$panel_bus"|3a1ca000.i2c|3a1cd000.i2c|3bdcb000.i2c)
                [ "$compatible" = google,i2c-mbu ] && [ ! -L "$device/driver" ] &&
                    IFS= read -r override < "$device/driver_override" || return 1
                case $override in ''|'(null)') ;; *) return 1 ;; esac
                seen="$seen $name"
                ;;
            *)
                case $name in i2c_designware|i2c_designware.*) return 1 ;; esac
                if printf '%s\n' "$compatible" | "$bb" grep -Exq \
                    'snps,designware-i2c|google,i2c(-mbu)?|mscc,ocelot-i2c|baikal,bt1-sys-i2c'; then
                    stock_inventory_log "DSI0 panel scope refused: unexpected I2C match $name"
                    return 1
                fi
                ;;
        esac
    done
    for name in "$panel_bus" $panel_other_buses; do
        case " $seen " in *" $name "*) ;; *) return 1 ;; esac
    done

    "$bb" mount -t sysfs -o remount,rw,nosuid,nodev,noexec sysfs "$sys" || return 1
    trap '"$bb" mount -t sysfs -o remount,ro,nosuid,nodev,noexec sysfs "$sys" ||
          stock_inventory_log "DSI0 panel scope: cannot restore read-only sysfs"' 0
    for name in $panel_other_buses; do
        printf '%s\n' "$panel_excluded" > "$platform/devices/$name/driver_override" || return 1
    done
    "$bb" mount -t sysfs -o remount,ro,nosuid,nodev,noexec sysfs "$sys" || return 1
    trap - 0
    for name in $panel_other_buses; do
        IFS= read -r override < "$platform/devices/$name/driver_override" &&
            [ "$override" = "$panel_excluded" ] || return 1
    done
    stock_inventory_log "DSI0 panel scope armed bus=$panel_bus excluded=3 sysfs=ro"
)

stock_panel_check_i2c() (
    platform=$1/bus/platform
    set +f
    for name in $panel_other_buses; do
        device=$platform/devices/$name
        [ ! -L "$device/driver" ] &&
            IFS= read -r override < "$device/driver_override" &&
            [ "$override" = "$panel_excluded" ] || return 1
    done
    driver=$platform/drivers/$panel_i2c_driver
    [ -L "$driver/$panel_bus" ] || return 1
    for device in "$driver"/*; do
        [ -L "$device" ] || continue
        case ${device##*/} in "$panel_bus"|module) ;; *) return 1 ;; esac
    done
)

stock_panel_discover() (
    sys=$1
    set +f
    stock_panel_check_i2c "$sys" || return 1
    supply=
    for device in "$sys"/bus/i2c/devices/*-0060; do
        [ -L "$device/driver" ] || continue
        path=$("$bb" readlink -f "$device") || return 1
        case $path in */"$panel_bus"/i2c-*/*-0060) ;; *) continue ;; esac
        driver=$("$bb" readlink -f "$device/driver") || return 1
        [ "${driver##*/}" = s2dos07x02 ] && [ -z "$supply" ] || return 1
        supply=${device##*/}
    done
    panel=
    for device in "$sys"/bus/mipi-dsi/devices/*; do
        [ -L "$device/driver" ] || continue
        path=$("$bb" readlink -f "$device") || return 1
        case $path in */f7d8000.dsi2host/*) ;; *) continue ;; esac
        driver=$("$bb" readlink -f "$device/driver") || return 1
        [ "${driver##*/}" = panel-gs-pkcgda ] && [ -z "$panel" ] || return 1
        panel=${device##*/}
    done
    stock_inventory_log "DSI0 panel supplier=${supply:-missing} panel=${panel:-missing}" || return 1
    [ -n "$supply" ] && [ -n "$panel" ] || return 1

    count=0
    for connector in "$sys"/class/drm/card*-DSI-*; do
        [ -d "$connector" ] || continue
        count=$((count + 1))
        IFS= read -r status < "$connector/status" &&
            IFS= read -r enabled < "$connector/enabled" || return 1
        case $status:$enabled in
            connected:disabled|unknown:disabled|disconnected:disabled) ;;
            *) return 1 ;;
        esac
        # These sysfs attributes expose cached connector data.
        modes=$("$bb" awk 'END { print NR }' "$connector/modes") || return 1
        stock_inventory_log "DSI0 panel connector=${connector##*/} status=$status enabled=$enabled cached_modes=$modes" ||
            return 1
    done
    [ "$count" -eq 1 ] && [ "$status" = connected ]
)
