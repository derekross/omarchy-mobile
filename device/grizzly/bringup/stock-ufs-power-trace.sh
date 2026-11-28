# SPDX-License-Identifier: MIT
# shellcheck shell=sh

stock_ufs_psm1_arm() {
    psm1_ufs=/lib/modules/ufs.ko
    psm1_sampler=/grizzly-inventory/grizzly_stock_psm1.ko
    psm1_attribute=/sys/module/grizzly_stock_psm1/parameters/sample
    [ -f "$psm1_ufs" ] && [ ! -L "$psm1_ufs" ] &&
        [ -f "$psm1_sampler" ] && [ ! -L "$psm1_sampler" ] || return 1
    IFS=' ' read -r psm1_expected psm1_path < "$1" &&
        [ "${#psm1_expected}" -eq 64 ] && [ "$psm1_path" = "$psm1_ufs" ] || return 1
    psm1_digest=$("$ufs_trace_bb" sha256sum "$psm1_ufs") || return 1
    if [ "${psm1_digest%% *}" != "$psm1_expected" ]; then
        stock_inventory_log 'UFS PSM1 trace factory module hash mismatch'
        return 1
    fi
    stock_inventory_log "UFS PSM1 trace factory ufs.ko SHA-256 verified=$psm1_expected"
    "$ufs_trace_bb" awk '$1 == "ufs" || $1 == "grizzly_stock_psm1" { found = 1 } END { exit found }' /proc/modules ||
        return 1
    set --
    if [ "${ufs_psm1_prep_requested:-no}" = yes ]; then
        set -- prep_trace=1
    fi
    "$ufs_trace_bb" insmod "$psm1_sampler" "$@" >/dev/kmsg 2>&1 || return 1
    if stock_ufs_psm1_pending &&
       stock_inventory_log 'UFS PSM1 sampler armed before factory ufs.ko load'; then
        return 0
    fi
    "$ufs_trace_bb" rmmod grizzly_stock_psm1 || stock_inventory_log 'UFS PSM1 sampler unload failed'
    return 1
}

stock_ufs_psm1_pending() {
    IFS= read -r psm1_initial < "$psm1_attribute" &&
        [ "$psm1_initial" = 'registration=-11 sample=-11' ] || return 1
    [ "${ufs_psm1_prep_requested:-no}" = yes ] || return 0
    for psm1_phase in prep_before prep_after; do
        IFS= read -r psm1_initial < "${psm1_attribute%/*}/$psm1_phase" &&
            [ "$psm1_initial" = 'registration=-11 sample=-11' ] || return 1
    done
}

stock_ufs_psm1_log_sample() {
    if IFS= read -r psm1_sample < "$2"; then
        if printf '%s\n' "$psm1_sample" |
            "$ufs_trace_bb" grep -Eq '^registration=0 raw=(0|0x[0-9a-f]+) psm1=(0|0x[1-9a-f]) mono_ns=[1-9][0-9]*$'; then
            stock_inventory_log "UFS power trace $1 PSM1 $psm1_sample"
            return $?
        elif printf '%s\n' "$psm1_sample" |
            "$ufs_trace_bb" grep -Eq '^registration=-?[0-9]+ sample=-?[0-9]+$'; then
            stock_inventory_log "UFS power trace $1 PSM1 unavailable $psm1_sample"
        else
            stock_inventory_log "UFS power trace $1 PSM1 malformed"
        fi
    else
        stock_inventory_log "UFS power trace $1 PSM1 unreadable"
    fi
    return 1
}

stock_ufs_psm1_close() {
    psm1_status=0
    if [ "${ufs_psm1_prep_requested:-no}" = yes ]; then
        stock_ufs_psm1_log_sample pre-prep "${psm1_attribute%/*}/prep_before" || psm1_status=1
        stock_ufs_psm1_log_sample post-prep "${psm1_attribute%/*}/prep_after" || psm1_status=1
    fi
    stock_ufs_psm1_log_sample pre-core "$psm1_attribute" || psm1_status=1
    "$ufs_trace_bb" rmmod grizzly_stock_psm1 || {
        stock_inventory_log 'UFS PSM1 sampler unload failed'
        psm1_status=1
    }
    return "$psm1_status"
}

stock_ufs_genpd_snapshot() (
    genpd_mount=/grizzly-inventory/ufs-genpd-debugfs
    "$ufs_trace_bb" mkdir -m 0700 "$genpd_mount" || return 1
    if ! "$ufs_trace_bb" mount -t debugfs -o ro,nosuid,nodev,noexec,mode=0700 debugfs "$genpd_mount"; then
        "$ufs_trace_bb" rmdir "$genpd_mount"
        return 1
    fi
    genpd_status=0
    for genpd_name in hsio_s_ufs_prep_pd hsio_s_ufs_pd; do
        genpd_dir=$genpd_mount/pm_genpd/$genpd_name
        if IFS= read -r genpd_state < "$genpd_dir/current_state" &&
           printf '%s\n' "$genpd_state" | "$ufs_trace_bb" grep -Eq '^(on|off-[0-9]+)$' &&
           genpd_idle=$("$ufs_trace_bb" awk '
               NR == 1 { next }
               NF == 4 && $1 ~ /^S[0-9]+$/ && $2 ~ /^[0-9]+$/ &&
                   $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ {
                   print "idle=" $1 " time_ms=" $2 " usage=" $3 " rejected=" $4
                   seen++
                   next
               }
               { invalid = 1 }
               END { if (!seen || invalid) exit 1 }
           ' "$genpd_dir/idle_states"); then
            while IFS= read -r genpd_line; do
                stock_inventory_log "UFS genpd pre-load domain=$genpd_name state=$genpd_state $genpd_line" ||
                    genpd_status=1
            done <<EOF
$genpd_idle
EOF
        else
            stock_inventory_log "UFS genpd pre-load domain=$genpd_name unavailable"
            genpd_status=1
        fi
    done
    "$ufs_trace_bb" umount "$genpd_mount" || genpd_status=1
    "$ufs_trace_bb" rmdir "$genpd_mount" || genpd_status=1
    return "$genpd_status"
)

stock_ufs_power_trace_start() {
    ufs_trace_bb=$1
    ufs_trace_clock=${2:-mono}
    ufs_trace_pre_on=${3:-no}
    ufs_trace_pre_on_created=no
    ufs_uic_probes=
    ufs_trace_mount=/grizzly-inventory/ufs-tracefs
    ufs_trace_instance=$ufs_trace_mount/instances/grizzly-ufs-power
    ufs_trace_state=none
    # The 64 KiB trial retained 1,362 of 3,234 events. Allow for the
    # full observed stream even if most records land on a single CPU.
    ufs_trace_buffer_kib=512
    "$ufs_trace_bb" mkdir -m 0700 "$ufs_trace_mount" || return 1
    ufs_trace_state=directory
    "$ufs_trace_bb" mount -t tracefs -o nosuid,nodev,noexec,mode=0700 tracefs "$ufs_trace_mount" ||
        return 1
    ufs_trace_state=mounted
    "$ufs_trace_bb" mkdir "$ufs_trace_instance" || return 1
    ufs_trace_state=instance
    ufs_trace_events=$ufs_trace_instance/events
    if ! { printf '0\n' > "$ufs_trace_instance/tracing_on" &&
           IFS= read -r ufs_trace_tracer < "$ufs_trace_instance/current_tracer" &&
           [ "$ufs_trace_tracer" = nop ] &&
           printf '%s\n' "$ufs_trace_clock" > "$ufs_trace_instance/trace_clock" &&
           printf '%s\n' "$ufs_trace_buffer_kib" > "$ufs_trace_instance/buffer_size_kb"; }; then
        return 1
    fi
    if [ "${ufs_uic_requested:-no}" = yes ]; then
        stock_ufs_uic_trace_enable || return 1
        printf '1\n' > "$ufs_trace_instance/tracing_on" || return 1
        ufs_trace_state=running
        stock_inventory_log 'UFS UIC trace armed before factory ufs.ko load'
        return $?
    fi
    # Count every provider record before selecting UFS resource IDs in awk.
    for ufs_trace_event in send_mail_mbfs recv_result_mbfs send_mail_lpcm recv_result_lpcm send_mail_lpb recv_result_lpb; do
        ufs_trace_event_dir=$ufs_trace_events/power_controller/$ufs_trace_event
        [ -f "$ufs_trace_event_dir/enable" ] &&
            printf '1\n' > "$ufs_trace_event_dir/enable" || return 1
    done
    ufs_trace_event_dir=$ufs_trace_events/rwmmio/rwmmio_post_read
    # The 4 KiB page offsets of PHY PSM and TOP readiness are 0x108 and 0x008.
    # Symbolized callers distinguish them from other accesses at those offsets.
    [ -f "$ufs_trace_event_dir/filter" ] && [ -f "$ufs_trace_event_dir/enable" ] &&
        printf '%s\n' 'width == 32 && (addr & 0x8) && !(addr & 0xef7)' > "$ufs_trace_event_dir/filter" &&
        printf '1\n' > "$ufs_trace_event_dir/enable" || return 1
    if [ "$ufs_trace_pre_on" = yes ]; then
        # Arm this before ufs.ko loads. Only fetch w0, the PHY-wait return.
        ufs_trace_pre_on_event=$ufs_trace_events/grizzly_ufs/pre_on
        [ ! -e "$ufs_trace_pre_on_event" ] &&
            [ -f "$ufs_trace_mount/kprobe_events" ] &&
            printf '%s\n' 'p:grizzly_ufs/pre_on ufs:ufs_google_pd_notifier+0x68 phy_wait_ret=%x0:s32' \
                >> "$ufs_trace_mount/kprobe_events" || return 1
        ufs_trace_pre_on_created=yes
        printf '1\n' > "$ufs_trace_pre_on_event/enable" || return 1
    fi
    printf '1\n' > "$ufs_trace_instance/tracing_on" || return 1
    ufs_trace_state=running
    stock_inventory_log "UFS power trace armed phase=consumer clock=$ufs_trace_clock buffer_kib_per_cpu=$ufs_trace_buffer_kib"
}

stock_ufs_power_trace_dump() {
    printf '0\n' > "$ufs_trace_instance/tracing_on" || return 1
    # Export only the audited driver call sites and resource IDs. Omit raw
    # addresses, process names and unrelated trace lines from the console.
    # shellcheck disable=SC2016
    ufs_trace_output=$("$ufs_trace_bb" awk -v pre_on="$ufs_trace_pre_on" '
        function emit(line) {
            if (++matched <= 80)
                print stamp, line
        }
        pre_on == "yes" &&
            match($0, /[0-9]+\.[0-9]+: pre_on: .*phy_wait_ret=-?[0-9]+[[:space:]]*$/) {
            split(substr($0, RSTART, RLENGTH), event, ": ")
            stamp = event[1]
            result = event[3]
            sub(/^.*phy_wait_ret=/, "", result)
            sub(/[[:space:]]*$/, "", result)
            landmarks++
            emit("pre-on phy_wait_ret=" result)
            next
        }
        /^# entries-in-buffer\/entries-written:/ {
            if (match($0, /[0-9]+\/[0-9]+/)) {
                split(substr($0, RSTART, RLENGTH), counts, "/")
                buffered = counts[1]
                written = counts[2]
            }
        }
        match($0, /[0-9]+\.[0-9]+: ((send_mail|recv_result)_(mbfs|lpcm|lpb)|rwmmio_post_read): /) {
            split(substr($0, RSTART, RLENGTH), event, ": ")
            stamp = event[1]
            body = substr($0, RSTART + RLENGTH)
            if (event[2] != "rwmmio_post_read") {
                family = event[2]
                sub(/^(send_mail|recv_result)_/, "", family)
                raw[family]++
                sub(/^[[:space:]]+/, "", body)
                if (!match(body, /^(0x[[:xdigit:]]+|0)(\.[[:xdigit:]][[:xdigit:]])?:[^[:space:]]+[[:space:]]+en:[01]/)) {
                    unparsed++
                    next
                }
                split(substr(body, RSTART, RLENGTH), vote, ":")
                split(vote[1], ids, /\./)
                sub(/^0x0*/, "0x", ids[1])
                if (ids[1] !~ /^0x(1a|220|222)$/ &&
                    !(family == "lpcm" && ids[1] == "0x8" && ids[2] ~ /^0[02]$/))
                    next
                detail = "resource=" ids[1] " on=" vote[3]
                if (ids[2] != "")
                    detail = detail " subdomain=0x" ids[2]
                if (event[2] ~ /^recv_result_/) {
                    if (!match(body, /\(res:-?[0-9]+\)[[:space:]]*$/)) {
                        unparsed++
                        next
                    }
                    result = substr(body, RSTART + 5)
                    sub(/\).*/, "", result)
                    detail = detail " ret=" result
                }
                votes++
                emit(event[2] " " detail)
                last_sample = ""
            } else if (match(body, / width=32 val=(0|0x[[:xdigit:]]+) addr=0x[[:xdigit:]]+$/)) {
                split(substr(body, RSTART + 1), access, " ")
                addr = access[3]
                kind = ""
                if (body ~ /^ufs_google_psm_wait_for_state\+0x(38|84|9c)\// && addr ~ /108$/) {
                    kind = "phy-psm"
                    phy++
                } else if (body ~ /^ufs_google_pd_notifier\+0x(dc|114|210)\// && addr ~ /008$/) {
                    kind = "top"
                    top++
                }
                if (kind != "") {
                    sample = kind " " access[2]
                    if (sample == last_sample)
                        repeated++
                    else
                        emit(sample)
                    last_sample = sample
                }
            }
        }
        END {
            if (buffered == "" || written == "")
                exit 1
            printf "summary entries=%s/%s votes=%d phy=%d top=%d repeated=%d omitted=%d\n",
                buffered, written, votes, phy, top, repeated, (matched > 80 ? matched - 80 : 0)
            printf "provider totals mbfs=%d lpcm=%d lpb=%d unparsed=%d\n",
                raw["mbfs"], raw["lpcm"], raw["lpb"], unparsed
            if (pre_on == "yes")
                printf "pre-on landmarks=%d\n", landmarks
        }
    ' "$ufs_trace_instance/trace") || return 1
    while IFS= read -r ufs_trace_line; do
        stock_inventory_log "UFS power trace $ufs_trace_line" || return 1
    done <<EOF
$ufs_trace_output
EOF
}

stock_ufs_power_trace_close() {
    ufs_trace_status=0
    case $ufs_trace_state in
        running)
            if [ "${ufs_uic_requested:-no}" = yes ]; then
                stock_ufs_uic_trace_dump || ufs_trace_status=1
            else
                stock_ufs_power_trace_dump || ufs_trace_status=1
            fi ;;
    esac
    if [ -n "$ufs_uic_probes" ]; then
        stock_ufs_uic_trace_remove || ufs_trace_status=1
    fi
    if [ "$ufs_trace_pre_on_created" = yes ]; then
        printf '0\n' > "$ufs_trace_pre_on_event/enable" || ufs_trace_status=1
        printf '%s\n' '-:grizzly_ufs/pre_on' >> "$ufs_trace_mount/kprobe_events" ||
            ufs_trace_status=1
    fi
    case $ufs_trace_state in
        running|instance) "$ufs_trace_bb" rmdir "$ufs_trace_instance" || ufs_trace_status=1 ;;
    esac
    case $ufs_trace_state in
        running|instance|mounted) "$ufs_trace_bb" umount "$ufs_trace_mount" || ufs_trace_status=1 ;;
    esac
    case $ufs_trace_state in
        running|instance|mounted|directory) "$ufs_trace_bb" rmdir "$ufs_trace_mount" || ufs_trace_status=1 ;;
    esac
    return "$ufs_trace_status"
}
