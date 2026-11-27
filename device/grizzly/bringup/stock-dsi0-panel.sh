# SPDX-License-Identifier: MIT
# shellcheck shell=sh

panel_bus=3a1ce000.i2c
panel_other_buses='3a1ca000.i2c 3a1cd000.i2c 3bdcb000.i2c'
panel_i2c_driver=i2c_designware
panel_excluded=grizzly-panel-excluded
panel_drm_master=sswrp_dpu@f400000:display-subsystem
panel_dp_encoder=sswrp_dpu@f400000:dp-encoder

stock_panel_check_dp_off() (
    status="$1/sswrp_dpu@f400000/dp-encoder/status"
    [ -r "$status" ] || return 1
    value=$("$bb" tr '\000' '\n' < "$status") || return 1
    [ "$value" = disabled ] || return 1
    stock_inventory_log "DSI0 panel live DT confirms DP encoder disabled"
)

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

stock_panel_drm_components() (
    debugfs=$1
    "$bb" mkdir -m 0700 "$debugfs" || return 1
    if ! "$bb" mount -t debugfs -o ro,nosuid,nodev,noexec,mode=0700 debugfs "$debugfs"; then
        "$bb" rmdir "$debugfs"
        stock_inventory_log "DSI0 panel sample=late reason=component-debugfs-unavailable"
        return 1
    fi
    trap '"$bb" umount "$debugfs" && "$bb" rmdir "$debugfs"' 0
    report=$debugfs/device_component/$panel_drm_master
    if [ -r "$report" ]; then
        rows=$("$bb" awk '
            NR > 64 || length($0) > 160 { bad=1; exit }
            NF > 1 && /(not registered|not bound|bound)$/ {
                sub(/[[:space:]]+/, " ")
                print
            }
            END { exit (bad || NR == 0) }
        ' "$report") || return 1
        [ -n "$rows" ] || return 1
        while IFS= read -r row; do
            stock_inventory_log "DSI0 panel sample=late component=$row" || return 1
        done <<EOF
$rows
EOF
    else
        stock_inventory_log "DSI0 panel sample=late reason=component-report-unavailable" || return 1
    fi
    deferred=$debugfs/devices_deferred
    if [ -r "$deferred" ]; then
        rows=$("$bb" awk -v device="$panel_dp_encoder" '
            NR > 256 || length($0) > 256 { bad=1; exit }
            $1 == device { print }
            END { exit bad }
        ' "$deferred") || return 1
        stock_inventory_log "DSI0 panel sample=late dp_encoder_deferred=${rows:-no-entry}"
    fi
)

stock_panel_discover() (
    sys=$1
    sample=$2
    set +f
    if ! stock_panel_check_i2c "$sys"; then
        stock_inventory_log "DSI0 panel sample=$sample reason=i2c-scope-failed"
        return 1
    fi
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
    stock_inventory_log "DSI0 panel sample=$sample supplier=${supply:-missing} panel=${panel:-missing}" || return 1
    [ -n "$supply" ] && [ -n "$panel" ] || return 1
    drm_class=$sys/class/drm
    if [ ! -d "$drm_class" ]; then
        stock_inventory_log "DSI0 panel sample=$sample reason=drm-class-missing"
        return 1
    fi
    cards=0
    for card in "$drm_class"/card[0-9]*; do
        [ -d "$card" ] || continue
        case ${card##*/} in *-*) ;; *) cards=$((cards + 1)) ;; esac
    done

    count=0
    accepted=0
    for connector in "$drm_class"/card[0-9]*-DSI-*; do
        [ -d "$connector" ] || continue
        count=$((count + 1))
        name=${connector##*/}
        for attr in status enabled modes; do
            [ -r "$connector/$attr" ] || break
        done
        if [ ! -r "$connector/$attr" ]; then
            stock_inventory_log "DSI0 panel sample=$sample connector=$name reason=attribute-unavailable attribute=$attr" || return 1
            continue
        fi
        if ! IFS= read -r status < "$connector/status"; then
            stock_inventory_log "DSI0 panel sample=$sample connector=$name reason=attribute-read-failed attribute=status" || return 1
            continue
        fi
        if ! IFS= read -r enabled < "$connector/enabled"; then
            stock_inventory_log "DSI0 panel sample=$sample connector=$name reason=attribute-read-failed attribute=enabled" || return 1
            continue
        fi
        # These sysfs attributes expose cached connector data.
        if ! modes=$("$bb" awk 'END { print NR }' "$connector/modes"); then
            stock_inventory_log "DSI0 panel sample=$sample connector=$name reason=attribute-read-failed attribute=modes" || return 1
            continue
        fi
        state=rejected
        if [ "$status:$enabled" = connected:disabled ]; then
            state=accepted
            accepted=$((accepted + 1))
        fi
        stock_inventory_log "DSI0 panel sample=$sample connector=$name status=$status enabled=$enabled cached_modes=$modes state=$state" || return 1
    done
    stock_inventory_log "DSI0 panel sample=$sample drm_cards=$cards dsi_connectors=$count accepted=$accepted" || return 1
    [ "$count" -eq 1 ] && [ "$accepted" -eq 1 ]
)

stock_panel_check_gpio() (
    set +f
    count=0
    for device in "$1"/bus/platform/drivers/da9188-gpio/*; do
        [ -L "$device" ] && [ -r "$device/of_node/compatible" ] || continue
        compatible=$("$bb" tr '\000' '\n' < "$device/of_node/compatible") || return 1
        [ "$compatible" = google,da9188-gpio ] || continue
        # The driver link can appear before probe has registered the chip.
        for chip in "$device"/gpiochip*; do
            [ -d "$chip" ] || continue
            count=$((count + 1))
        done
    done
    [ "$count" -eq 1 ]
)

stock_panel_trace_begin() {
    [ ! -d "$panel_tracefs/events/grizzly_vddd" ] || return 1
    "$bb" mkdir "$panel_instance" || return 1
    panel_instance_owned=yes
    printf '0\n' > "$panel_instance/tracing_on" &&
        printf 'mono\n' > "$panel_instance/trace_clock" &&
        printf '64\n' > "$panel_instance/buffer_size_kb" || return 1
    for name in smbus_read smbus_reply smbus_write smbus_result; do
        event=$panel_instance/events/smbus/$name
        printf '%s\n' 'adapter_nr == 9 && addr == 0x60 && (command == 3 || command == 4)' > "$event/filter" &&
            printf '1\n' > "$event/enable" || return 1
    done
    printf '1\n' > "$panel_instance/tracing_on" &&
        printf 'VDDD SMBus trace armed\n' > "$panel_instance/trace_marker"
}

stock_panel_trace_irq() {
    event=$panel_instance/events/i2c_dw/i2c_dw_isr
    printf '%s\n' 'label == "3a1ce000.i2c"' > "$event/filter" &&
        printf '1\n' > "$event/enable"
}

stock_panel_trace_disable_probe() (
    events=$panel_instance/events/grizzly_vddd
    "$bb" awk '
        $3 == "s2dos07x02_disable" && $4 == "[s2dos07x02_regulator]" { found++ }
        END { exit !(found == 1) }
    ' /proc/kallsyms || return 1
    # w0 holds the SMBus result at +0x34 and the returned status at +0x38.
    printf '%s\n' 'p:grizzly_vddd/vddd_i2c s2dos07x02_regulator:s2dos07x02_disable+0x34 result=%x0:s32' \
        >> "$panel_tracefs/kprobe_events" && printf '1\n' > "$events/vddd_i2c/enable" &&
    printf '%s\n' 'p:grizzly_vddd/vddd_return s2dos07x02_regulator:s2dos07x02_disable+0x38 result=%x0:s32' \
        >> "$panel_tracefs/kprobe_events" && printf '1\n' > "$events/vddd_return/enable" &&
    printf 'VDDD disable probes armed\n' > "$panel_instance/trace_marker"
)

stock_panel_trace_cleanup() {
    "$bb" rmdir "$panel_instance" || return 1
    failed=0
    for name in vddd_i2c vddd_return; do
        if [ -d "$panel_tracefs/events/grizzly_vddd/$name" ]; then
            printf '%s\n' "-:grizzly_vddd/$name" >> "$panel_tracefs/kprobe_events" || failed=1
        fi
    done
    [ "$failed" -eq 0 ]
}

stock_panel_trace_dump() (
    printf '0\n' > "$panel_instance/tracing_on" || return 1
    trace=$("$bb" awk '
        NR > 96 || length($0) > 512 { bad=1; exit }
        /entries-in-buffer\/entries-written:|LOST EVENTS|: (smbus_(read|reply|write|result)|i2c_dw_isr|vddd_(i2c|return)|tracing_mark_write): / {
            print
        }
        END { exit bad }
    ' "$panel_instance/trace") || return 1
    while IFS= read -r line; do
        stock_inventory_log "DSI0 panel VDDD trace $line" || return 1
    done <<EOF
$trace
EOF
    profile=$("$bb" awk '
        $1 ~ /^vddd_(i2c|return)$/ { probes++; missed += $3 }
        END { printf "probes=%d missed=%d", probes, missed }
    ' "$panel_tracefs/kprobe_profile") || return 1
    stock_inventory_log "DSI0 panel VDDD profile $profile" || return 1
    [ "$profile" = 'probes=2 missed=0' ] || return 1
    printf '%s\n' "$trace" | "$bb" awk '
        /LOST EVENTS/ { lost=1 }
        /entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/) {
            split(substr($0, RSTART, RLENGTH), c, "/")
        }
        END { exit !(c[1] != "" && c[1] == c[2] && !lost) }
    '
)

stock_panel_run() (
    panel_tracefs=/grizzly-inventory/panel-tracefs
    panel_instance=$panel_tracefs/instances/grizzly_vddd
    panel_instance_owned=no
    "$bb" mkdir -m 0700 "$panel_tracefs" || return 1
    if ! "$bb" mount -t tracefs -o nosuid,nodev,noexec,mode=0700 tracefs "$panel_tracefs"; then
        "$bb" rmdir "$panel_tracefs"
        return 1
    fi
    trap 'if [ "${dsi0_dp0_vote_requested:-no}" = yes ]; then
              stock_dp0_trace_cleanup || stock_inventory_log "DSI0 DP0 vote cleanup failed"
          fi
          if [ "$panel_instance_owned" = yes ]; then
              stock_panel_trace_cleanup || stock_inventory_log "DSI0 panel VDDD cleanup failed"
          fi
          "$bb" umount "$panel_tracefs" && "$bb" rmdir "$panel_tracefs"' 0
    stock_panel_trace_begin || return 1
    if [ "${dsi0_dp0_vote_requested:-no}" = yes ]; then
        stock_dp0_trace_begin "$panel_tracefs" || {
            stock_inventory_log "DSI0 DP0 vote trace could not arm before display load"
            return 1
        }
    fi
    loaded=no
    discovered=no
    if stock_inventory_modules load "$1"; then
        if [ "${dsi0_dp0_vote_requested:-no}" = yes ]; then
            stock_dp0_trace_cleanup || return 1
        fi
        loaded=yes
        if "$bb" sleep 3 && stock_panel_discover /sys initial; then
            discovered=yes
        fi
    else
        stock_inventory_log "DSI0 panel module load failed"
    fi
    # The previous disable timed out at 31.92 s. End before the return timer.
    IFS=' .' read -r uptime rest < /proc/uptime || return 1
    if [ "$uptime" -lt 45 ]; then
        "$bb" sleep "$((45 - uptime))" || return 1
    fi
    trace_ok=yes
    stock_panel_trace_dump || {
        stock_inventory_log "DSI0 panel VDDD capture incomplete"
        trace_ok=no
    }
    if [ "$loaded:$discovered" = yes:no ] && stock_panel_discover /sys late; then
        discovered=yes
    fi
    if [ "$loaded" = yes ] && ! stock_panel_drm_components /grizzly-inventory/panel-debugfs; then
        stock_inventory_log "DSI0 panel sample=late reason=component-snapshot-incomplete"
    fi
    [ "$discovered:$trace_ok" = yes:yes ]
)
