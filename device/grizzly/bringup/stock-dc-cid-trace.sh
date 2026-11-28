#!/bin/sh
# SPDX-License-Identifier: MIT
# Sourced by stock-inventory-init after the NV guard succeeds.
# shellcheck disable=SC2154

stock_dc_cid_check_tree() {
    for node in dsi2host@3d8000 dsi2host@3f8000 dw_mipi_cdphy@3c0000 \
            dw_mipi_cdphy@3e0000 dp-encoder; do
        status=$("$bb" tr -d '\000' < "$1/sswrp_dpu@f400000/$node/status") || return 1
        [ "$status" = disabled ] || return 1
    done
}

stock_dc_cid_capture() {
    # shellcheck disable=SC2016
    "$bb" awk '
        function hex(field) {
            sub(/^[^=]*=0x0*/, "", field)
            return field == "" ? "0" : field
        }
        NR > 256 || length($0) > 512 || /LOST EVENTS/ { bad = 1; exit }
        /entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/) {
            split(substr($0, RSTART, RLENGTH), entries, "/")
            intact = (entries[1] == entries[2])
        }
        /: dc_customer_id: / {
            sub(/^.*: dc_customer_id: /, "")
            if (NF < 5 || $(NF-3) !~ /^chip_id=0x[0-9a-f]+$/ ||
                $(NF-2) !~ /^revision=0x[0-9a-f]+$/ || $(NF-1) !~ /^product_id=0x[0-9a-f]+$/ ||
                $NF !~ /^customer_id=0x[0-9a-f]+$/) { bad = 1; exit }
            chip = hex($(NF-3)); rev = hex($(NF-2)); product = hex($(NF-1)); cid = hex($NF)
            current = chip " " rev " " product " " cid
            if (count && current != sample) { bad = 1; exit }
            sample = current
            count++
        }
        END {
            if (bad || !intact || !count || count != entries[1]) exit 1
            layout = "unknown"
            if (chip == "9400" && rev == "7002" && product == "2094000" &&
                (cid == "32a" || cid == "20000005")) layout = "0x" cid
            printf "DC CID chip_id=0x%s revision=0x%s product_id=0x%s customer_id=0x%s gpcsr_layout=%s samples=%d\n", chip, rev, product, cid, layout, count
        }
    ' "$1"
}

stock_dc_cid_cleanup() {
    failed=0
    if [ -d "$instance" ]; then
        "$bb" echo 0 > "$instance/tracing_on" || failed=1
        "$bb" rmdir "$instance" || failed=1
    fi
    if [ "$created" = yes ]; then
        printf '%s\n' '-:grizzly_dc_cid/dc_customer_id' >> "$probes" || failed=1
    fi
    "$bb" umount "$tracefs" || failed=1
    return "$failed"
}

stock_dc_cid_trace() (
    [ "$("$bb" uname -r)" = 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ] || return 1
    stock_dc_cid_check_tree /sys/firmware/devicetree/base || return 1
    # shellcheck disable=SC2016
    "$bb" awk '$1 ~ /^(vs_drm|mipi_dsi2h|mipi_cdphy)$/ { bad=1 } END { exit bad }' \
        /proc/modules || return 1
    tracefs=/grizzly-inventory/dc-cid-tracefs
    instance=$tracefs/instances/grizzly_dc_cid
    probes=$tracefs/kprobe_events
    created=no
    "$bb" mkdir -m 0700 "$tracefs" || return 1
    "$bb" mount -t tracefs -o nosuid,nodev,noexec tracefs "$tracefs" || return 1
    [ ! -e "$tracefs/events/grizzly_dc_cid" ] && [ ! -e "$instance" ] || {
        "$bb" umount "$tracefs"
        return 1
    }
    trap 'stock_dc_cid_cleanup || stock_inventory_log "DC CID trace cleanup failed"' 0
    "$bb" mkdir "$instance" || return 1
    "$bb" echo 0 > "$instance/tracing_on" || return 1
    "$bb" echo 64 > "$instance/buffer_size_kb" || return 1
    printf '%s\n' 'p:grizzly_dc_cid/dc_customer_id vs_drm:vs_dc_get_chip_info chip_id=%x0:x32 revision=%x1:x32 product_id=%x2:x32 customer_id=%x3:x32' \
        >> "$probes" || return 1
    created=yes
    "$bb" echo 1 > "$instance/events/grizzly_dc_cid/dc_customer_id/enable" || return 1
    "$bb" echo 1 > "$instance/tracing_on" || return 1
    stock_inventory_log 'DC CID trace armed before vs_drm load, DSI host and PHY nodes disabled' || return 1
    stock_inventory_modules load "$1" || return 1
    for _ in 1 2 3 4 5; do
        "$bb" grep -q ': dc_customer_id: ' "$instance/trace" && break
        "$bb" sleep 1 || return 1
    done
    "$bb" echo 0 > "$instance/tracing_on" || return 1
    sample=$(stock_dc_cid_capture "$instance/trace") || return 1
    stock_inventory_log "$sample" || return 1
    trap - 0
    stock_dc_cid_cleanup
)
