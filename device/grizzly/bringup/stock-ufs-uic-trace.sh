# SPDX-License-Identifier: MIT
# shellcheck shell=sh

stock_ufs_uic_add() {
    ufs_uic_event=$ufs_trace_events/grizzly_uic/$1
    printf 'p:grizzly_uic/%s %s\n' "$1" "$2" >> "$ufs_trace_mount/kprobe_events" || return 1
    ufs_uic_probes="$ufs_uic_probes $1"
    if [ "$#" -eq 3 ]; then
        printf '%s\n' "$3" > "$ufs_uic_event/filter" || return 1
    fi
    printf '1\n' > "$ufs_uic_event/enable"
}

stock_ufs_uic_trace_enable() {
    [ "$("$ufs_trace_bb" uname -r)" = 6.12.81-android16-6-gf5369e7496cb-ab16467452-4k ] &&
        [ -f "$ufs_trace_mount/kprobe_events" ] &&
        [ ! -d "$ufs_trace_mount/events/grizzly_uic" ] || return 1
    "$ufs_trace_bb" awk '$1 == "ufs" { found=1 } END { exit found }' /proc/modules || return 1

    read_filter='cmd == 1 && (arg1 == 0x15870000 || arg1 == 0x15860000)'
    power_filter='cmd == 2 && arg1 == 0x15710000'
    command_filter="($read_filter) || ($power_filter)"
    command='cmd=+0(%x19):u32 arg1=+4(%x19):x32 arg2=+8(%x19):x32 arg3=+12(%x19):x32'
    # Both stock dispatch branches go through these two points. The first
    # is after the command becomes active, before the argument writes.
    stock_ufs_uic_add uic_dispatch "__ufshcd_send_uic_cmd+0x88 $command" "$command_filter" &&
    stock_ufs_uic_add uic_sent "__ufshcd_send_uic_cmd+0x10c $command" "$command_filter" &&
    stock_ufs_uic_add uic_read_result "ufshcd_wait_for_uic_cmd+0x68 $command ret=%x21:s32" "$read_filter" ||
        return 1
    # This wrapper only issues PA_PWRMODE. x0 holds the just-returned status.
    stock_ufs_uic_add uic_power_result 'ufshcd_uic_change_pwr_mode+0x90 ret=%x0:s32' ||
        return 1

    # IRQ has already read IS and IE. The command pointer comes from HBA
    # RAM and can be null after the waiter clears it on timeout.
    command='cmd=+0(+432(%x19)):u32 arg1=+4(+432(%x19)):x32'
    stock_ufs_uic_add uic_irq "ufshcd_intr+0xe0 status=%x20:x32 enable=%x0:x32 $command" \
        "(status & 0x470) && (($command_filter) || cmd == 0)" || return 1
    command='cmd=+0(%x27):u32 arg1=+4(%x27):x32'
    # At +0x184 stock has copied the ARG2 result into RAM and has just read ARG3.
    stock_ufs_uic_add uic_reply "ufshcd_intr+0x184 $command arg2=+8(%x27):x32 arg3=%x0:x32" "$command_filter" &&
    stock_ufs_uic_add uic_power_irq "ufshcd_intr+0x1ac $command pending=%x22:x32" "$power_filter"
}

stock_ufs_uic_trace_remove() {
    ufs_uic_cleanup=0
    for ufs_uic_name in $ufs_uic_probes; do
        printf '0\n' > "$ufs_trace_events/grizzly_uic/$ufs_uic_name/enable" || ufs_uic_cleanup=1
        printf '%s\n' "-:grizzly_uic/$ufs_uic_name" >> "$ufs_trace_mount/kprobe_events" ||
            ufs_uic_cleanup=1
    done
    return "$ufs_uic_cleanup"
}

stock_ufs_uic_trace_dump() {
    printf '0\n' > "$ufs_trace_instance/tracing_on" || return 1
    # Export bounded numeric fields with timestamps, without kernel pointers or task names.
    ufs_uic_output=$("$ufs_trace_bb" awk '
        /entries-in-buffer\/entries-written:/ && match($0, /[0-9]+\/[0-9]+/) {
            split(substr($0, RSTART, RLENGTH), counts, "/")
        }
        /LOST EVENTS/ { lost++ }
        match($0, /[0-9]+\.[0-9]+: uic_(dispatch|sent|read_result|power_result|irq|reply|power_irq): /) {
            split(substr($0, RSTART, RLENGTH), event, ": ")
            body = substr($0, RSTART + RLENGTH)
            if (!sub(/^\([^)]*\) /, "", body) ||
                body !~ /^([a-z][a-z0-9]*=(0x[0-9a-fA-F]+|-?[0-9]+) ?)+$/) {
                invalid++
                next
            }
            if (++matched <= 128)
                print event[1], event[2], body
        }
        END {
            if (counts[1] == "") exit 1
            printf "summary entries=%s/%s matches=%d omitted=%d malformed=%d lost=%d\n",
                counts[1], counts[2], matched, (matched > 128 ? matched - 128 : 0), invalid, lost
        }
    ' "$ufs_trace_instance/trace") || return 1
    ufs_uic_summary=
    while IFS= read -r ufs_uic_line; do
        stock_inventory_log "UFS UIC trace $ufs_uic_line" || return 1
        ufs_uic_summary=$ufs_uic_line
    done <<EOF
$ufs_uic_output
EOF
    ufs_uic_profile=$("$ufs_trace_bb" awk '
        $1 ~ /^uic_(dispatch|sent|read_result|power_result|irq|reply|power_irq)$/ {
            found++; missed += $3
        }
        END { printf "profile probes=%d missed=%d", found, missed }
    ' "$ufs_trace_mount/kprobe_profile") || return 1
    stock_inventory_log "UFS UIC trace $ufs_uic_profile" || return 1
    [ "$ufs_uic_profile" = 'profile probes=7 missed=0' ] || return 1
    printf '%s\n' "$ufs_uic_summary" | "$ufs_trace_bb" awk '
        $1 == "summary" {
            split($2, fields, "[=/]")
            if (fields[2] == fields[3] && $3 != "matches=0" &&
                $4 == "omitted=0" && $5 == "malformed=0" && $6 == "lost=0") ok=1
        }
        END { exit !ok }
    '
}
