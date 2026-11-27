# SPDX-License-Identifier: MIT
# Sourced by the mainline inventory PID 1 after the read-only GPT check.

grizzly_dsi0_phy_vote_trace() {
    # shellcheck disable=SC2016
    "$bb" awk '
        BEGIN {
            domain[1] = domain[6] = "wrapper"
            domain[2] = domain[5] = "be"
            domain[3] = domain[4] = "dsi0"
        }
        /grizzly-mainline-inventory: DSI0 PHY scaffold vote trace start$/ {
            armed = 1
            count = failed = 0
            next
        }
        armed && /display-(wrapper|be|dsi0): requested=[01] (ack=[0-9]+|readback=[01])$/ {
            step = int(count / 2) + 1
            on = (step <= 3 ? 1 : 0)
            if (count % 2 == 0)
                reply_ok = ($NF == "ack=0" || $NF == "ack=5")
            else
                reply_ok = ($NF == ("readback=" on))
            if ($(NF - 2) != "display-" domain[step] ":" ||
                $(NF - 1) != "requested=" on || !reply_ok)
                failed = 1
            count++
        }
        END { exit !(armed && !failed && count == 12) }'
}

grizzly_dsi0_phy_cycle() (
    module=/grizzly-inventory/phy-google-malibu-cdphy.ko
    device=/sys/bus/platform/devices/f7c0000.phy

    # The kernel retires the read-only disk after the comparison. Require
    # retirement before loading anything that can trigger display votes.
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        stock_inventory_no_scsi_disks /sys/class/block && break
        "$bb" sleep 1 || return 1
    done
    if ! stock_inventory_no_scsi_disks /sys/class/block; then
        stock_inventory_log 'DSI0 PHY skipped: UFS disk did not retire'
        return 1
    fi
    if [ ! -f "$module" ] || [ -L "$module" ] ||
       [ ! -d "$device" ] || [ -L "$device/driver" ] ||
       [ ! -r /proc/modules ] ||
       "$bb" grep -q '^phy_google_malibu_cdphy ' /proc/modules; then
        stock_inventory_log 'DSI0 PHY skipped: module or platform binding state invalid'
        return 1
    fi

    stock_inventory_log 'DSI0 PHY scaffold vote trace start'
    if ! "$bb" insmod "$module"; then
        stock_inventory_log 'DSI0 PHY scaffold module insertion failed'
        return 1
    fi
    bound=$("$bb" readlink "$device/driver")
    stock_inventory_log "DSI0 PHY scaffold bound=${bound##*/}"
    if ! "$bb" rmmod phy_google_malibu_cdphy || [ -L "$device/driver" ]; then
        stock_inventory_log 'DSI0 PHY scaffold module removal failed'
        return 1
    fi
    [ "${bound##*/}" = malibu-cdphy ] || return 1

    # Platform detach queues genpd power-off work.
    for attempt in 1 2 3 4 5; do
        if "$bb" dmesg | grizzly_dsi0_phy_vote_trace; then
            stock_inventory_no_scsi_disks /sys/class/block
            return $?
        fi
        "$bb" sleep 1 || return 1
    done
    stock_inventory_log 'DSI0 PHY scaffold did not complete all six ordered vote acknowledgements and readbacks'
    return 1
)
