# SPDX-License-Identifier: MIT
# shellcheck shell=sh

stock_ufs_cpm_trace_mount() {
    cpm_trace_bb=$1
    cpm_trace_debug=/grizzly-inventory/cpm-debugfs
    cpm_trace_directory=no
    cpm_trace_mounted=no
    "$cpm_trace_bb" mkdir -m 0700 "$cpm_trace_debug" || return 1
    cpm_trace_directory=yes
    "$cpm_trace_bb" mount -t debugfs -o ro,nosuid,nodev,noexec,mode=0700 debugfs "$cpm_trace_debug" ||
        return 1
    cpm_trace_mounted=yes
    cpm_trace_ring=$cpm_trace_debug/fwtp_cpm/cpm/trace
}

stock_ufs_cpm_clock_sample() {
    cpm_trace_phase=$1
    cpm_trace_marker=$2/trace_marker
    IFS= read -r cpm_trace_clock < "$2/trace_clock" || return 1
    case $cpm_trace_clock in *'[boot]'*) ;; *) return 1 ;; esac
    printf 'grizzly-cpm-clock %s before\n' "$cpm_trace_phase" > "$cpm_trace_marker" || return 1
    IFS= read -r cpm_trace_ns < "$cpm_trace_debug/gtc/current_ns" || return 1
    case $cpm_trace_ns in ''|*[!0-9]*) return 1 ;; esac
    printf 'grizzly-cpm-clock %s after ns=%s\n' "$cpm_trace_phase" "$cpm_trace_ns" > "$cpm_trace_marker"
}

stock_ufs_cpm_trace_before_probe() {
    cpm_trace_wait=0
    while [ ! -r "$cpm_trace_ring" ]; do
        [ "$cpm_trace_wait" -lt 4 ] || return 1
        "$cpm_trace_bb" sleep 1 || return 1
        cpm_trace_wait=$((cpm_trace_wait + 1))
    done
    stock_ufs_cpm_clock_sample pre "$1"
}

stock_ufs_cpm_trace_capture() (
    ap_trace=$1
    stock_ufs_cpm_clock_sample post "$ap_trace" || return 1
    printf '0\n' > "$ap_trace/tracing_on" || return 1
    # Keep the raw firmware snapshot in RAM and log only the targeted records.
    snapshot=$("$cpm_trace_bb" mktemp /grizzly-inventory/cpm-ring.XXXXXXXX) || return 1
    trap '"$cpm_trace_bb" rm -f "$snapshot"' EXIT
    limit=262144
    "$cpm_trace_bb" timeout 8 "$cpm_trace_bb" head -c "$limit" "$cpm_trace_ring" > "$snapshot" ||
        return 1
    bytes=$("$cpm_trace_bb" wc -c < "$snapshot") || return 1
    [ "$bytes" -lt "$limit" ] || return 1
    output=$("$cpm_trace_bb" awk -f /grizzly-inventory/stock-ufs-cpm-trace.awk "$ap_trace/trace" "$snapshot") ||
        return 1
    while IFS= read -r line; do
        stock_inventory_log "UFS CPM trace $line" || return 1
    done <<EOF
$output
EOF
)

stock_ufs_cpm_trace_unmount() {
    cpm_trace_status=0
    if [ "$cpm_trace_mounted" = yes ]; then
        "$cpm_trace_bb" umount "$cpm_trace_debug" || cpm_trace_status=1
    fi
    if [ "$cpm_trace_directory" = yes ]; then
        "$cpm_trace_bb" rmdir "$cpm_trace_debug" || cpm_trace_status=1
    fi
    return "$cpm_trace_status"
}
