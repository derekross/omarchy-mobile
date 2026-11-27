#!/bin/sh
# SPDX-License-Identifier: MIT
# Observe existing stock PHY accesses. The caller supplies display activity.
set -eu

if [ "$#" != 3 ] || [ ! -x "$2" ] || [ ! -d "$1/instances" ] ||
   [ ! -f "$1/kprobe_events" ] ||
   [ "$("$2" uname -r)" != 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ]; then
    echo 'usage: stock-dsi0-rmw-trace.sh TRACEFS BUSYBOX arm|dump|cleanup (stock D1)' >&2
    exit 2
fi
bb=$2
instance=$1/instances/grizzly_phy_rmw
probes=$1/kprobe_events
group=grizzly_phy_rmw
sites='
cfg_shutdown_assert dw_dphy_configure_g301 80 84
cfg_reset_assert dw_dphy_configure_g301 9c a0
cfg_bit8_a dw_dphy_configure_g301 1e98 1e9c
cfg_shutdown_release_a dw_dphy_configure_g301 1eb4 1eb8
cfg_reset_release_a dw_dphy_configure_g301 1ed0 1ed4
cfg_bit8_b dw_dphy_configure_g301 1f50 1f54
cfg_shutdown_release_b dw_dphy_configure_g301 1f6c 1f70
cfg_reset_release_b dw_dphy_configure_g301 1f88 1f8c
off_shutdown dw_dphy_power_off_g301 40 44
off_reset dw_dphy_power_off_g301 5c 60'

remove_probes() {
    status=0
    for name in $1; do
        printf '%s\n' "-:$group/$name" >> "$probes" || status=1
    done
    return "$status"
}

add_probe() {
    printf 'p:%s/%s mipi_cdphy:%s bank=+64(%%x19):x64 %s\n' "$group" "$1" "$2" "$3" >> "$probes"
    created="$created $1"
    event=$instance/events/$group/$1
    printf '%s\n' 'bank == 0x0f7d8800' > "$event/filter"
    printf '1\n' > "$event/enable"
}

case $3 in
    arm)
        [ ! -d "$1/events/$group" ] || exit 1
        "$bb" awk '
            $3 == "dw_dphy_configure_g301" && $4 == "[mipi_cdphy]" { cfg++ }
            $3 == "dw_dphy_power_off_g301" && $4 == "[mipi_cdphy]" { off++ }
            END { exit !(cfg == 1 && off == 1) }
        ' /proc/kallsyms
        "$bb" mkdir "$instance"
        created=
        trap '"$bb" rmdir "$instance" && remove_probes "$created" ||
              echo "stock-dsi0-rmw-trace: cleanup failed" >&2' 0
        printf '0\n' > "$instance/tracing_on"
        printf 'mono\n' > "$instance/trace_clock"
        printf '64\n' > "$instance/buffer_size_kb"
        for event in regmap_reg_read regmap_reg_write; do
            path=$instance/events/regmap/$event
            printf '%s\n' 'name ~ "f7c0000.dw_mipi_cdphy*" && reg == 40' > "$path/filter"
            printf '1\n' > "$path/enable"
        done
        while read -r site symbol enter leave; do
            [ -n "$site" ] || continue
            add_probe "${site}_begin" "$symbol+0x$enter" 'value=%x2:u32'
            add_probe "${site}_end" "$symbol+0x$leave" 'result=%x0:s32'
        done <<EOF
$sites
EOF
        printf '1\n' > "$instance/tracing_on"
        printf 'DSI0 PHY register 0x28 trace armed\n' > "$instance/trace_marker"
        trap - 0
        ;;
    dump)
        printf '0\n' > "$instance/tracing_on"
        "$bb" awk '
            NR > 128 || length($0) > 512 { bad=1; exit }
            /entries-in-buffer\/entries-written:|LOST EVENTS|: (regmap_reg_(read|write)|((cfg|off)_[a-z0-9_]+_(begin|end))|tracing_mark_write): / { print }
            END { exit bad }
        ' "$instance/trace"
        "$bb" awk '
            $1 ~ /^(cfg|off)_[a-z0-9_]+_(begin|end)$/ { found++; missed += $3 }
            END { printf "PHY RMW probe profile count=%d missed=%d\n", found, missed;
                  exit !(found == 20 && missed == 0) }
        ' "$1/kprobe_profile"
        ;;
    cleanup)
        "$bb" rmdir "$instance"
        names=
        while read -r site rest; do
            [ -n "$site" ] || continue
            names="$names ${site}_begin ${site}_end"
        done <<EOF
$sites
EOF
        remove_probes "$names"
        ;;
    *) exit 2 ;;
esac
