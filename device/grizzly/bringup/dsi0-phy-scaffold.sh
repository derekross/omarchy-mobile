# SPDX-License-Identifier: MIT
# Sourced by the mainline inventory PID 1 after the read-only GPT check.

grizzly_dsi0_phy_vote_trace() {
    # shellcheck disable=SC2016
    "$bb" awk -v require_siblings="${1:-0}" -v require_gate="${2:-0}" '
        BEGIN {
            domain[1] = domain[6] = "wrapper"
            domain[2] = domain[5] = "be"
            domain[3] = domain[4] = "dsi0"
            phase[1] = "before-on"; position[1] = 4
            phase[2] = "after-on"; position[2] = 6
            phase[3] = "before-off"; position[3] = 6
            phase[4] = "after-off"; position[4] = 8
        }
        /grizzly-mainline-inventory: DSI0 PHY scaffold vote trace start$/ {
            armed = 1
            count = failed = samples = gates = 0
            next
        }
        armed && require_siblings && /display-dsi0-siblings:/ {
            if (require_gate && gates != samples)
                failed = 1
            samples++
            if (NF < 5 || $(NF - 4) != "display-dsi0-siblings:" ||
                $(NF - 3) != phase[samples] || count != position[samples] ||
                $(NF - 2) != "dsi1=0" || $(NF - 1) != "fe0=0" || $NF != "fe1=0")
                failed = 1
        }
        armed && require_gate && /display-dsi0-selector3-gate:/ {
            gates++
            if (NF < 3 || $(NF - 2) != "display-dsi0-selector3-gate:" ||
                $(NF - 1) != phase[gates] || count != position[gates] ||
                samples != gates || $NF !~ /^firmware=[01]$/)
                failed = 1
        }
        armed && /display-(wrapper|be|dsi0): requested=[01] (ack=[0-9]+|readback=[01])$/ {
            step = int(count / 2) + 1
            on = (step <= 3 ? 1 : 0)
            if (count % 2 == 0)
                reply_ok = ($NF == "ack=0" || $NF == "ack=5")
            else
                reply_ok = ($NF == ("readback=" on))
            if ((require_gate && gates != samples) ||
                $(NF - 2) != "display-" domain[step] ":" ||
                $(NF - 1) != "requested=" on || !reply_ok)
                failed = 1
            count++
        }
        END {
            exit !(armed && !failed && count == 12 &&
                   (!require_siblings || samples == 4) &&
                   (!require_gate || (require_siblings && gates == 4)))
        }'
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

    require_siblings=0
    require_gate=0
    parameters=/sys/module/clk_google_malibu_cpm/parameters
    marker=/grizzly-inventory/dsi0-sibling-votes
    if [ -e "$marker" ] || [ -L "$marker" ]; then
        parameter=$parameters/display_dsi0_siblings
        if ! { [ -f "$marker" ] && [ ! -L "$marker" ] &&
               [ -r "$parameter" ] && IFS= read -r enabled < "$parameter" &&
               [ "$enabled" = Y ]; }; then
            stock_inventory_log 'DSI0 PHY skipped: sibling vote checks are unavailable'
            return 1
        fi
        require_siblings=1
    fi
    marker=/grizzly-inventory/dsi0-selector3-gate
    if [ -e "$marker" ] || [ -L "$marker" ]; then
        parameter=$parameters/display_dsi0_selector3_gate
        if ! { [ "$require_siblings" -eq 1 ] && [ -f "$marker" ] && [ ! -L "$marker" ] &&
               [ -r "$parameter" ] && IFS= read -r enabled < "$parameter" &&
               [ "$enabled" = Y ]; }; then
            stock_inventory_log 'DSI0 PHY skipped: selector 3 gate checks are unavailable'
            return 1
        fi
        require_gate=1
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
        if "$bb" dmesg | grizzly_dsi0_phy_vote_trace "$require_siblings" "$require_gate"; then
            stock_inventory_no_scsi_disks /sys/class/block
            return $?
        fi
        "$bb" sleep 1 || return 1
    done
    stock_inventory_log 'DSI0 PHY scaffold vote trace did not pass'
    return 1
)
