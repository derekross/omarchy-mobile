#!/bin/sh
# SPDX-License-Identifier: MIT
# Run on stock D1 with tracefs already mounted, before loading the display driver.
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || [ ! -f "$1/available_events" ] ||
   [ ! -d "$1/instances" ] || [ ! -x "$2" ]; then
    echo 'usage: stock-dsi0-trace.sh TRACEFS BUSYBOX [--mbfs|--apb-reset|--pll-lock|--pll-probes|--cleanup]' >&2
    exit 2
fi
bb=$2
mode=${3:-}
instance=$1/instances/grizzly_dsi0
probes=$1/kprobe_events
group=grizzly_dsi0_cpm
events='dsi0_clk_call dsi0_clk_result dsi0_rst_call dsi0_rst_result'
pll_events='dsi0_pll_first dsi0_pll_last dsi0_pll_relock_first dsi0_pll_relock_last dsi0_pll_cfg_first dsi0_pll_cfg_last dsi0_pll_cfg_timeout'

remove_probes() {
    result=0
    for name in $1; do
        printf '%s\n' "-:$group/$name" >> "$probes" || result=1
    done
    return "$result"
}

if [ "$("$bb" uname -r)" != 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ]; then
    echo 'stock-dsi0-trace: expected the audited D1 kernel release' >&2
    exit 1
fi
add_probe() {
    printf '%s\n' "$1:$group/$2 $3" >> "$probes"
    created="$created $2"
    probe_dir=$instance/events/$group/$2
    if [ "$#" -eq 4 ]; then
        "$bb" echo "$4" > "$probe_dir/filter"
    fi
    "$bb" echo 1 > "$probe_dir/enable"
}

case $mode in
    --cleanup)
        for name in $pll_events; do
            if [ -d "$1/events/$group/$name" ]; then
                events="$events $name"
            fi
        done
        "$bb" rmdir "$instance" && remove_probes "$events"
        exit $? ;;
    --pll-probes)
        [ -d "$instance" ] || exit 1
        "$bb" awk '
            $3 == "dw_dphy_set_mode_g301" && $4 == "[mipi_cdphy]" { found++ }
            $3 == "dw_dphy_configure_g301" && $4 == "[mipi_cdphy]" { config++ }
            END { if (found != 1 || config != 1) exit 1 }
        ' /proc/kallsyms || exit 1
        created=
        # x0 is the already-read word. x22+0x40 holds the resource start in RAM.
        samples='bank=+64(%x22):x64 value=%x0:x32'
        bank='bank == 0x0f7d8800'
        add_probe p dsi0_pll_first "mipi_cdphy:dw_dphy_set_mode_g301+0x9c8 $samples" "$bank"
        add_probe p dsi0_pll_last "mipi_cdphy:dw_dphy_set_mode_g301+0xa18 $samples" "$bank"
        add_probe p dsi0_pll_relock_first "mipi_cdphy:dw_dphy_set_mode_g301+0x538 $samples" "$bank"
        add_probe p dsi0_pll_relock_last "mipi_cdphy:dw_dphy_set_mode_g301+0x6b4 $samples" "$bank"
        # The configure callback keeps the same RAM structure in x19.
        samples='bank=+64(%x19):x64 value=%x0:x32'
        add_probe p dsi0_pll_cfg_first "mipi_cdphy:dw_dphy_configure_g301+0x207c $samples" "$bank"
        add_probe p dsi0_pll_cfg_last "mipi_cdphy:dw_dphy_configure_g301+0x20b4 $samples" "$bank"
        add_probe p dsi0_pll_cfg_timeout "mipi_cdphy:dw_dphy_configure_g301+0x20fc $samples" "$bank"
        "$bb" echo 'DSI0 PLL lock probes armed' > "$instance/trace_marker"
        exit 0 ;;
    ''|--mbfs|--apb-reset|--pll-lock) ;;
    *) exit 2 ;;
esac

provider_probes=no
case $mode in --apb-reset|--pll-lock) provider_probes=yes ;; esac

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
if [ "$provider_probes" = yes ]; then
    # Tracefs can accept module-qualified probes before the module exists.
    "$bb" awk '
        $3 == "goog_cpm_clk_send_mba_mail" && $4 == "[clk_cpm]" { clk++ }
        $3 == "goog_cpm_rst_send_mba_mail" && $4 == "[rst_cpm]" { rst++ }
        END { if (clk != 1 || rst != 1) exit 1 }
    ' /proc/kallsyms || {
        echo 'stock-dsi0-trace: D1 clock and reset provider symbols must already be loaded' >&2
        exit 1
    }
fi

# Refuse to re-arm an instance whose existing contents might be a capture.
"$bb" mkdir "$instance"
created=
trap '"$bb" rmdir "$instance" && remove_probes "$created" ||
      echo "stock-dsi0-trace: instance or probe cleanup failed" >&2' 0

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

reads=$status
if [ "$provider_probes" = yes ]; then
    host_reads='name ~ "f7d8000.dsi2host*" && (reg == 0 || reg == 4 || reg == 12)'
    # 28964 is the PHY init callback's existing register offset, 0x7124.
    phy_read='name == "f7c0000.dw_mipi_cdphy" && reg == 28964'
    reads="($host_reads) || ($phy_read)"
fi
enable_event regmap/regmap_reg_read "$reads"
for event in rpm_resume rpm_return_int rpm_status; do
    enable_event "rpm/$event" "$host"
done
enable_event power/power_domain_target "$domains"
for event in clk_enable clk_disable clk_set_rate; do
    enable_event "clk/$event" "$clocks"
done
if [ -n "$mode" ]; then
    # Stock D1 power_controller.ko exposes the resource as a u32 in both events.
    resources='pm_resource_id == 8 || pm_resource_id == 512 || pm_resource_id == 515'
    for event in send_mail_mbfs recv_result_mbfs; do
        enable_event "power_controller/$event" "$resources"
    done
fi

if [ "$provider_probes" = yes ]; then
    # These files and offsets are qualified against the pinned D1 images.
    # The fetches inspect RAM-backed provider arguments, with no extra MMIO.
    [ -f "$probes" ] && [ ! -d "$1/events/$group" ] || exit 1
    add_probe p dsi0_clk_call 'clk_cpm:goog_cpm_clk_send_mba_mail lpcm=+40(%x0):u32 id=+44(%x0):u32 op=%x1:u32'
    add_probe r64 dsi0_clk_result 'clk_cpm:goog_cpm_clk_send_mba_mail result=$retval:s32'
    add_probe p dsi0_rst_call 'rst_cpm:goog_cpm_rst_send_mba_mail lpcm=+0(%x0):u32 id=%x1:u32 op=%x2:u32'
    add_probe r64 dsi0_rst_result 'rst_cpm:goog_cpm_rst_send_mba_mail result=$retval:s32'
fi

# The PLL path may run after host probe. PID 1 stops that capture.
if [ "$mode" != --pll-lock ]; then
    "$bb" echo "traceoff:1 if $status" > "$instance/events/regmap/regmap_reg_read/trigger"
fi
"$bb" echo 1 > "$instance/tracing_on"
if [ "$provider_probes" = yes ]; then
    "$bb" echo 'DSI0 CPM provider probes armed' > "$instance/trace_marker"
    "$bb" echo 'DSI0 PHY init read trace armed' > "$instance/trace_marker"
fi
trap - 0
