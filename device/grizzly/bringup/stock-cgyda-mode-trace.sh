#!/bin/sh
# SPDX-License-Identifier: MIT
# Observe a stock D1 DRM client through tracefs.
set -eu

if [ "$#" != 3 ] || [ ! -x "$2" ] || [ ! -d "$1/instances" ] ||
   [ ! -f "$1/kprobe_events" ] ||
   [ "$("$2" uname -r)" != 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ]; then
    echo 'usage: stock-cgyda-mode-trace.sh TRACEFS BUSYBOX arm|dump|cleanup (stock D1)' >&2
    exit 2
fi
tracefs=$1
bb=$2
group=grizzly_cgyda
instance=$tracefs/instances/$group
probes=$tracefs/kprobe_events
sites='
p cgyda_getconnector drm_mode_getconnector connector_id=+48(%x1):u32 requested_modes=+32(%x1):u32
p cgyda_modes_enter gs_panel:gs_panel_get_modes
r cgyda_modes_return gs_panel:gs_panel_get_modes result=$retval:s32
p cgyda_dsi_enter mipi_dsi2h:dw_mipi_dsi2h_host_transfer type=+1(%x1):x8 tx_len=+8(%x1):u64 rx_len=+24(%x1):u64
r cgyda_dsi_return mipi_dsi2h:dw_mipi_dsi2h_host_transfer result=$retval:s64
p cgyda_postclose vs_drm:vs_drm_postclose open_count=+224(%x0):s32'

remove_probes() {
    failed=0
    for name in $1; do
        printf '%s\n' "-:$group/$name" >> "$probes" || failed=1
    done
    return "$failed"
}

case $3 in
    arm)
        "$bb" awk '
            $3 == "drm_mode_getconnector" && NF == 3 { query++ }
            $3 == "gs_panel_get_modes" && $4 == "[gs_panel]" { modes++ }
            $3 == "dw_mipi_dsi2h_host_transfer" && $4 == "[mipi_dsi2h]" { dsi++ }
            $3 == "vs_drm_postclose" && $4 == "[vs_drm]" { close_hook++ }
            END { exit !(query == 1 && modes == 1 && dsi == 1 && close_hook == 1) }
        ' /proc/kallsyms || {
            echo 'CGYDA trace symbols unavailable or ambiguous' >&2
            exit 1
        }
        [ ! -d "$tracefs/events/$group" ] || exit 1
        "$bb" mkdir "$instance"
        created=
        trap '"$bb" rmdir "$instance" && remove_probes "$created" ||
              echo "CGYDA trace cleanup failed" >&2' 0
        printf '0\n' > "$instance/tracing_on"
        printf 'mono\n' > "$instance/trace_clock"
        printf '64\n' > "$instance/buffer_size_kb"
        while read -r kind name symbol fields; do
            [ -n "$name" ] || continue
            printf '%s:%s/%s %s %s\n' "$kind" "$group" "$name" "$symbol" "$fields" >> "$probes"
            created="$created $name"
            event=$instance/events/$group/$name
            if [ "$name" = cgyda_getconnector ]; then
                printf '%s\n' 'requested_modes == 0' > "$event/filter"
            fi
            printf '1\n' > "$event/enable"
        done <<EOF
$sites
EOF
        printf '1\n' > "$instance/tracing_on"
        printf 'CGYDA stock DRM trace armed\n' > "$instance/trace_marker"
        trap - 0
        ;;
    dump)
        [ -d "$instance/events/$group" ] && [ -f "$instance/tracing_on" ] || exit 1
        printf '0\n' > "$instance/tracing_on"
        capture_ok=yes
        "$bb" awk '
            NR > 2048 || length($0) > 512 { bad=1; exit }
            /LOST EVENTS/ { bad=1 }
            /entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/) {
                split(substr($0, RSTART, RLENGTH), counts, "/")
                matched = (counts[1] == counts[2])
            }
            /entries-in-buffer\/entries-written:|LOST EVENTS|: (cgyda_[a-z_]+|tracing_mark_write): / { print }
            END { exit (bad || !matched) }
        ' "$instance/trace" || capture_ok=no
        "$bb" awk '
            $1 ~ /^cgyda_(getconnector|modes_enter|modes_return|dsi_enter|dsi_return|postclose)$/ {
                seen[$1]++; count++; missed += $3
            }
            END {
                for (name in seen) if (seen[name] != 1) bad=1
                printf "CGYDA probes=%d missed=%d\n", count, missed
                exit (bad || count != 6 || missed != 0)
            }
        ' "$tracefs/kprobe_profile" || capture_ok=no
        if [ "$capture_ok" != yes ]; then
            echo 'CGYDA trace incomplete' >&2
            exit 1
        fi
        ;;
    cleanup)
        [ -d "$instance/events/$group" ] || exit 1
        "$bb" rmdir "$instance"
        names=
        while read -r kind name rest; do
            [ -n "$name" ] && names="$names $name"
        done <<EOF
$sites
EOF
        remove_probes "$names"
        ;;
    *) exit 2 ;;
esac
