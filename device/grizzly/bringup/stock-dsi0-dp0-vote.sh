#!/bin/sh
# SPDX-License-Identifier: MIT

# Sourced by the stock D1 inventory after the storage and live DT guards.
dp0_instance_owned=no
dp0_debugfs_owned=no
dp0_debugfs=/grizzly-inventory/dp0-debugfs
dp0_phy_event=': regmap_reg_read: f7c0000.dw_mipi_cdphy reg=7124 '

stock_dp0_vote_sample() (
    # The audited 0220 debugfs node has a read handler. Root opens it O_RDONLY.
    # It reads the AP client's MBFS vote, without resuming the domain.
    if ! vote=$("$bb" timeout 3 "$bb" cat "$dp0_debugfs/power_controller/dpu_dp0_pd/state"); then
        stock_inventory_log "DSI0 DP0 vote phase=$1 read failed"
        return 1
    fi
    case $vote in
        0|1|2) ;;
        *) stock_inventory_log "DSI0 DP0 vote phase=$1 invalid reply"; return 1 ;;
    esac
    printf 'DP0 %s vote=%s\n' "$1" "$vote" > "$dp0_instance/trace_marker" || return 1
    stock_inventory_log "DSI0 DP0 vote phase=$1 resource=0x205 value=$vote"
)

stock_dp0_trace_begin() {
    dp0_instance=$1/instances/grizzly_dp0_vote
    "$bb" mkdir "$dp0_instance" || return 1
    dp0_instance_owned=yes
    printf '0\n' > "$dp0_instance/tracing_on" &&
        printf 'mono\n' > "$dp0_instance/trace_clock" &&
        printf '64\n' > "$dp0_instance/buffer_size_kb" || return 1
    phy_event=$dp0_instance/events/regmap/regmap_reg_read
    printf '%s\n' 'name == "f7c0000.dw_mipi_cdphy" && reg == 28964' > "$phy_event/filter" &&
        printf '1\n' > "$phy_event/enable" || return 1
    for event in send_mail_mbfs recv_result_mbfs; do
        event_dir=$dp0_instance/events/power_controller/$event
        printf 'pm_resource_id == 517\n' > "$event_dir/filter" &&
            printf '1\n' > "$event_dir/enable" || return 1
    done
    "$bb" mkdir -m 0700 "$dp0_debugfs" || return 1
    if ! "$bb" mount -t debugfs -o ro,nosuid,nodev,noexec,mode=0700 debugfs "$dp0_debugfs"; then
        "$bb" rmdir "$dp0_debugfs"
        return 1
    fi
    dp0_debugfs_owned=yes
    printf '1\n' > "$dp0_instance/tracing_on" && stock_dp0_vote_sample before
}

stock_dp0_trace_dump() (
    # Print a bounded excerpt even if the capture fails validation.
    lines=$("$bb" awk -v phy="$dp0_phy_event" '
        /entries-in-buffer\/entries-written:/ {
            headers++
            split($3, entries, "/")
            if (entries[1] != entries[2]) invalid = 1
        }
        /LOST EVENTS/ { invalid = 1 }
        /: tracing_mark_write: DP0 before vote=[012]$/ {
            if (phase != 0) invalid = 1
            phase = 1
        }
        index($0, phy) {
            reads++
            if (phase != 1 || reads != 1) invalid = 1
        }
        /: tracing_mark_write: DP0 sampling after$/ {
            if (phase != 1 || reads != 1) invalid = 1
            phase = 2
        }
        /: tracing_mark_write: DP0 after vote=[012]$/ {
            if (phase != 2) invalid = 1
            phase = 3
        }
        /entries-in-buffer\/entries-written:|LOST EVENTS|: (send_mail_mbfs|recv_result_mbfs|tracing_mark_write): / ||
            index($0, phy) { if (++lines <= 24) print }
        END { if (headers != 1 || invalid || phase != 3 || reads != 1 || lines > 24) exit 1 }
    ' "$dp0_instance/trace")
    trace_result=$?
    while IFS= read -r line; do
        [ -n "$line" ] && stock_inventory_log "DSI0 DP0 trace $line"
    done <<EOF
$lines
EOF
    [ "$trace_result" -eq 0 ]
)

stock_dp0_trace_finish() {
    # vs_drm starts the audited PHY init, which can run asynchronously.
    # Poll only the trace buffer. The existing PHY read is the trigger.
    observed=no
    for attempt in 1 2 3 4 5; do
        if "$bb" grep -Fq "$dp0_phy_event" "$dp0_instance/trace"; then
            observed=yes
            break
        fi
        if [ "$attempt" -lt 5 ]; then
            "$bb" sleep 1 || return 1
        fi
    done
    if [ "$observed" = yes ]; then
        if printf 'DP0 sampling after\n' > "$dp0_instance/trace_marker"; then
            stock_dp0_vote_sample after
        fi
    else
        stock_inventory_log "DSI0 DP0 vote missing stock PHY init read"
    fi
    printf '0\n' > "$dp0_instance/tracing_on" || return 1
    if ! stock_dp0_trace_dump; then
        stock_inventory_log "DSI0 DP0 vote trace incomplete"
        return 1
    fi
    stock_inventory_log "DSI0 DP0 vote trace complete with one bracketed stock PHY init read"
}

stock_dp0_trace_cleanup() {
    cleanup_failed=0
    if [ "$dp0_debugfs_owned" = yes ]; then
        if "$bb" umount "$dp0_debugfs"; then
            dp0_debugfs_owned=no
            "$bb" rmdir "$dp0_debugfs" || cleanup_failed=1
        else
            cleanup_failed=1
        fi
    fi
    if [ "$dp0_instance_owned" = yes ]; then
        if "$bb" rmdir "$dp0_instance"; then
            dp0_instance_owned=no
        else
            cleanup_failed=1
        fi
    fi
    [ "$cleanup_failed" -eq 0 ]
}
