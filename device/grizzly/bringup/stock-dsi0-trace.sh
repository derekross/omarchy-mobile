#!/bin/sh
# SPDX-License-Identifier: MIT
# Run on stock D1 with tracefs already mounted, before loading the display driver.
set -eu

if [ "$#" -ne 2 ] || [ ! -f "$1/available_events" ] || [ ! -d "$1/instances" ] || [ ! -x "$2" ]; then
    echo 'usage: stock-dsi0-trace.sh TRACEFS_MOUNT BUSYBOX' >&2
    exit 2
fi
bb=$2
if [ "$("$bb" uname -r)" != 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ]; then
    echo 'stock-dsi0-trace: expected the audited D1 kernel release' >&2
    exit 1
fi

if [ ! -r /proc/modules ]; then
    echo 'stock-dsi0-trace: mount proc before arming the trace' >&2
    exit 1
fi
while IFS=' ' read -r module rest; do
    case $module in
        mipi_dsi2h|vs_drm)
            echo 'stock-dsi0-trace: display module already loaded' >&2
            exit 1;;
    esac
done < /proc/modules

instance=$1/instances/grizzly_dsi0
# Refuse to re-arm an instance whose existing contents might be a capture.
"$bb" mkdir "$instance"
trap '"$bb" rmdir "$instance" || echo "stock-dsi0-trace: instance cleanup failed" >&2' 0

enable_event() {
    event_dir=$instance/events/$1
    "$bb" echo "$2" > "$event_dir/filter"
    "$bb" echo 1 > "$event_dir/enable"
}

"$bb" echo 0 > "$instance/tracing_on"
"$bb" echo mono > "$instance/trace_clock"
"$bb" echo 64 > "$instance/buffer_size_kb"

host='name == "f7d8000.dsi2host"'
status='name ~ "f7d8000.dsi2host*" && reg == 12'
domains='name == "sswrp_dpu_pd" || name == "dpu_be_pd" || name == "dpu_dsi0_pd" || name == "dpu.v" || name == "DpuBe.v" || name == "DpuDsi0.v"'
clocks='name ~ "*dsi*" || name ~ "*dpu*"'

enable_event regmap/regmap_reg_read "$status"
for event in rpm_resume rpm_return_int rpm_status; do
    enable_event "rpm/$event" "$host"
done
enable_event power/power_domain_target "$domains"
for event in clk_enable clk_disable clk_set_rate; do
    enable_event "clk/$event" "$clocks"
done

# Stop this instance after the existing driver records its first status read.
"$bb" echo "traceoff:1 if $status" > "$instance/events/regmap/regmap_reg_read/trigger"
"$bb" echo 1 > "$instance/tracing_on"
trap - 0
