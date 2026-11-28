# SPDX-License-Identifier: MIT
# Sourced by the mainline inventory PID 1 after the read-only GPT check.

grizzly_dc9x00_be_gate_trace() {
    # shellcheck disable=SC2016
    "$1" awk '
        BEGIN {
            expected[1] = "before-on firmware="
            expected[2] = "requested=1 ack="
            expected[3] = "requested=1 readback=1"
            expected[4] = "after-on firmware="
            expected[5] = "before-off firmware="
            expected[6] = "requested=0 ack="
            expected[7] = "requested=0 readback=0"
            expected[8] = "after-off firmware="
        }
        /grizzly-mainline-inventory: DC9x00 BE selector 4 gate trace start$/ {
            if (armed) failed = 1
            armed = 1
            next
        }
        armed && NF >= 3 && $(NF - 2) == "display-be-selector4-gate:" {
            count++
            if (count !~ /^(1|4|5|8)$/ || index($(NF - 1) " " $NF, expected[count]) != 1 ||
                $NF !~ /^firmware=-?[0-9]+$/)
                failed = 1
        }
        armed && NF >= 3 && $(NF - 2) == "display-be:" && $(NF - 1) ~ /^requested=[01]$/ {
            count++
            if (count == 2 || count == 6) {
                if (expected[count] != $(NF - 1) " ack=" || $NF !~ /^ack=[05]$/)
                    failed = 1
            } else if ((count != 3 && count != 7) || expected[count] != $(NF - 1) " " $NF) {
                failed = 1
            }
        }
        END { exit !(armed && !failed && count == 8) }'
}

grizzly_dc9x00_binding() (
    bb=$1
    module=/grizzly-inventory/malibu-dc9x00.ko
    platform=/sys/bus/platform/devices
    device=$platform/f600000.display-controller

    attempt=0
    while [ "$attempt" -lt 10 ] && ! stock_inventory_no_scsi_disks /sys/class/block; do
        "$bb" sleep 1 || return 1
        attempt=$((attempt + 1))
    done
    if ! stock_inventory_no_scsi_disks /sys/class/block; then
        stock_inventory_log 'DC9x00 skipped: UFS disk did not retire'
        return 1
    fi
    if [ ! -f "$module" ] || [ -L "$module" ] ||
       [ ! -d "$device" ] || [ -L "$device/driver" ] ||
       [ -d /sys/module/malibu_dc9x00 ]; then
        stock_inventory_log 'DC9x00 skipped: module or platform binding state invalid'
        return 1
    fi

    for router in f46e080.interrupt-controller f46e020.interrupt-controller; do
        driver=$("$bb" readlink "$platform/$router/driver")
        if [ "${driver##*/}" != google-malibu-sgia ]; then
            stock_inventory_log "DC9x00 skipped: display SGIA not bound device=$router"
            return 1
        fi
        stock_inventory_log "display SGIA bound device=$router"
    done

    marker=/grizzly-inventory/dc9x00-be-gate
    require_gate=no
    if [ -e "$marker" ] || [ -L "$marker" ]; then
        parameter=/sys/module/clk_google_malibu_cpm/parameters/display_be_selector4_gate
        if ! { [ -f "$marker" ] && [ ! -L "$marker" ] &&
               [ -r "$parameter" ] && IFS= read -r enabled < "$parameter" &&
               [ "$enabled" = Y ]; }; then
            stock_inventory_log 'DC9x00 skipped: BE selector 4 gate sampler unavailable'
            return 1
        fi
        require_gate=yes
        stock_inventory_log 'DC9x00 BE selector 4 gate trace start'
    fi

    if ! "$bb" insmod "$module"; then
        stock_inventory_log 'DC9x00 module insertion failed'
        return 1
    fi
    result=1
    driver=$("$bb" readlink "$device/driver")
    irq=$("$bb" dmesg | "$bb" sed -n \
        's/^.*malibu-dc9x00 f600000\.display-controller: frame-start IRQ \([0-9][0-9]*\) reserved and masked$/\1/p')
    case $irq in
        ''|*[!0-9]*) stock_inventory_log 'DC9x00 masked frame-start reservation missing' ;;
        *)
            if [ "${driver##*/}" = malibu-dc9x00 ] &&
               [ "$("$bb" cat "/sys/kernel/irq/$irq/hwirq")" = 4 ] &&
               [ "$("$bb" cat "/sys/kernel/irq/$irq/chip_name")" = malibu-sgia ]; then
                stock_inventory_log "DC9x00 bound frame-start irq=$irq hwirq=4 masked"
                result=0
            else
                stock_inventory_log "DC9x00 binding or SGIA input mismatch irq=$irq"
            fi ;;
    esac
    if ! "$bb" rmmod malibu_dc9x00 || [ -L "$device/driver" ]; then
        stock_inventory_log 'DC9x00 module removal failed'
        return 1
    fi
    [ "$result" -eq 0 ] && stock_inventory_no_scsi_disks /sys/class/block || return 1
    if [ "$require_gate" = yes ]; then
        # Platform detach queues genpd power-off work.
        for attempt in 1 2 3 4 5; do
            if "$bb" dmesg | grizzly_dc9x00_be_gate_trace "$bb"; then
                stock_inventory_log 'DC9x00 BE selector 4 gate trace complete'
                return 0
            fi
            "$bb" sleep 1 || return 1
        done
        stock_inventory_log 'DC9x00 BE selector 4 gate trace incomplete'
        return 1
    fi
)
