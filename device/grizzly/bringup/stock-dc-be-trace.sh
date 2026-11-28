# SPDX-License-Identifier: MIT
# Sourced by stock-inventory-init after the NV guard succeeds.
# shellcheck disable=SC2154

stock_dc_be_capture() {
    # shellcheck disable=SC2016
    "$bb" awk '
        NR > 256 || length($0) > 512 || /LOST EVENTS/ { bad = 1; exit }
        /entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/) {
            split(substr($0, RSTART, RLENGTH), entries, "/")
            intact = (entries[1] == entries[2])
        }
        /^[[:space:]]*#/ || !NF { next }
        {
            if ($0 ~ /: be_read: /) reads++
            else if ($0 ~ /: be_isolation_write: /) writes++
            else if ($0 ~ /: be_isolation_returned: /) returns++
            else if ($0 ~ /: rpm_status: /) rpm++
            else if ($0 ~ /: power_domain_target: /) domains++
            else if ($0 ~ /: send_mail_mbfs: /) requests++
            else if ($0 ~ /: recv_result_mbfs: /) replies++
            else { bad = 1; exit }
            count++
            print
        }
        END {
            if (bad || !intact || !count || count != entries[1]) exit 1
            printf "samples reads=%d isolation_writes=%d isolation_returns=%d rpm=%d domains=%d requests=%d replies=%d\n",
                   reads, writes, returns, rpm, domains, requests, replies
        }
    ' "$1"
}

stock_dc_be_enable_event() {
    event=$instance/events/$1
    if [ "$#" -eq 2 ]; then
        printf '%s\n' "$2" > "$event/filter" || return 1
    fi
    printf '1\n' > "$event/enable"
}

stock_dc_be_add_probe() {
    name=$1
    location=$2
    shift 2
    printf '%s\n' "p:$group/$name $location" >> "$probes" || return 1
    created="$created $name"
    stock_dc_be_enable_event "$group/$name" "$@"
}

stock_dc_be_cleanup() {
    failed=0
    if [ -d "$instance" ]; then
        printf '0\n' > "$instance/tracing_on" || failed=1
        "$bb" rmdir "$instance" || failed=1
    fi
    for name in $created; do
        printf '%s\n' "-:$group/$name" >> "$probes" || failed=1
    done
    "$bb" umount "$tracefs" || failed=1
    return "$failed"
}

stock_dc_be_trace() (
    [ "$("$bb" uname -r)" = 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ] || return 1
    stock_dc_cid_check_tree /sys/firmware/devicetree/base || return 1
    # shellcheck disable=SC2016
    "$bb" awk '
        $1 == "power_controller" { controllers++ }
        $1 ~ /^(vs_drm|mipi_dsi2h|mipi_cdphy)$/ { bad = 1 }
        END { exit (bad || controllers != 1) }
    ' /proc/modules || return 1

    tracefs=/grizzly-inventory/dc-be-tracefs
    instance=$tracefs/instances/grizzly_dc_be
    group=grizzly_dc_be
    probes=$tracefs/kprobe_events
    created=
    "$bb" mkdir -m 0700 "$tracefs" || return 1
    "$bb" mount -t tracefs -o nosuid,nodev,noexec tracefs "$tracefs" || return 1
    if [ -e "$tracefs/events/$group" ] || [ -e "$instance" ]; then
        "$bb" umount "$tracefs"
        return 1
    fi
    trap 'stock_dc_be_cleanup || stock_inventory_log "DC BE trace cleanup failed"' 0
    "$bb" mkdir "$instance" || return 1
    printf '0\n' > "$instance/tracing_on" || return 1
    printf 'mono\n' > "$instance/trace_clock" || return 1
    printf '64\n' > "$instance/buffer_size_kb" || return 1

    # Audited DC offsets are relative to the dpu-fe-be resource at 0x0f600000.
    # At dc_read+0x30, x0 contains the returned value and x19 the offset.
    # The preceding NOP is reserved by the module's jump table.
    offsets='reg == 0xd4004 || reg == 0x80248 || reg == 0x80004 || reg == 0x80008 || reg == 0x80014'
    stock_dc_be_add_probe be_read 'vs_drm:dc_read+0x30 reg=%x19:x32 value=%x0:x32' "$offsets" ||
        return 1
    # Observe the stock isolation call and its return. No probe reads MMIO.
    stock_dc_be_add_probe be_isolation_write \
        'vs_drm:dc_hw_enable_clock_domain_iso+0x30 reg=%x1:x32 value=%x2:x32' 'reg == 0x80248' ||
        return 1
    stock_dc_be_add_probe be_isolation_returned 'vs_drm:dc_hw_enable_clock_domain_iso+0x34' ||
        return 1

    devices='name == "f600000.dc9x00" || name == "f600000.dc9x00:dpu_be@80000"'
    domains='name == "sswrp_dpu_pd" || name == "dpu_be_pd" || name == "dpu_fe0_pd" || name == "dpu_fe1_pd" || name == "dpu_dsi0_pd" || name == "dpu_dsi1_pd" || name == "dpu_dp0_pd"'
    resources='pm_resource_id == 8 || (pm_resource_id >= 512 && pm_resource_id <= 517)'
    stock_dc_be_enable_event rpm/rpm_status "$devices" || return 1
    stock_dc_be_enable_event power/power_domain_target "$domains" || return 1
    for vote_event in send_mail_mbfs recv_result_mbfs; do
        stock_dc_be_enable_event "power_controller/$vote_event" "$resources" || return 1
    done
    printf '1\n' > "$instance/tracing_on" || return 1
    stock_inventory_log 'DC BE trace armed before vs_drm load, DSI hosts and PHYs disabled' || return 1
    stock_inventory_modules load "$1" || return 1
    "$bb" sleep 3 || return 1
    printf '0\n' > "$instance/tracing_on" || return 1

    capture=$(stock_dc_be_capture "$instance/trace") || {
        stock_inventory_log 'DC BE trace empty, truncated or inconsistent'
        return 1
    }
    while IFS= read -r line; do
        stock_inventory_log "DC BE trace $line" || return 1
    done <<EOF
$capture
EOF
    if "$bb" dmesg | "$bb" grep -Eq 'trace_kprobe: Failed to re-register probe be_(read|isolation_write|isolation_returned) on vs_drm:'; then
        stock_inventory_log 'DC BE trace probe attachment incomplete'
        return 1
    fi
    trap - 0
    stock_dc_be_cleanup
)
