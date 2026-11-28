# SPDX-License-Identifier: MIT
# Sourced by the mainline inventory PID 1 after the read-only GPT check.

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
    [ "$result" -eq 0 ] && stock_inventory_no_scsi_disks /sys/class/block
)
