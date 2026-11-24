# SPDX-License-Identifier: MIT
# shellcheck shell=sh

# Configure a private instance so the tracefs root events are untouched.
stock_usb2_ep0_start() {
    usb_ep0_bb=$1
    usb_ep0_mount=$2
    usb_ep0_instance=$usb_ep0_mount/instances/grizzly-usb2-ep0
    usb_ep0_events=$usb_ep0_instance/events/dwc3
    usb_ep0_dir=no
    usb_ep0_mounted=no
    usb_ep0_created=no
    usb_ep0_running=no

    "$usb_ep0_bb" mkdir -m 0700 "$usb_ep0_mount" || return 1
    usb_ep0_dir=yes
    "$usb_ep0_bb" mount -t tracefs -o nosuid,nodev,noexec,mode=0700 tracefs "$usb_ep0_mount" ||
        return 1
    usb_ep0_mounted=yes
    "$usb_ep0_bb" mkdir "$usb_ep0_instance" || return 1
    usb_ep0_created=yes
    if ! { printf '0\n' > "$usb_ep0_instance/tracing_on" &&
           IFS= read -r usb_ep0_tracer < "$usb_ep0_instance/current_tracer" &&
           [ "$usb_ep0_tracer" = nop ] &&
           printf '16\n' > "$usb_ep0_instance/buffer_size_kb" &&
           printf '1\n' > "$usb_ep0_events/dwc3_ctrl_req/enable"; }; then
        return 1
    fi

    usb_ep0_event_context=no
    usb_ep0_stalls=no
    # Keep controller and control-endpoint events.
    if printf '%s\n' '(event & 1) || !(event & 0x3c)' > "$usb_ep0_events/dwc3_event/filter" &&
       printf '1\n' > "$usb_ep0_events/dwc3_event/enable"; then
        usb_ep0_event_context=yes
    fi
    # SETSTALL has no transfer buffer parameters.
    if printf '%s\n' 'name ~ "ep0*" && cmd == 4' > "$usb_ep0_events/dwc3_gadget_ep_cmd/filter" &&
       printf '1\n' > "$usb_ep0_events/dwc3_gadget_ep_cmd/enable"; then
        usb_ep0_stalls=yes
    fi
    printf '1\n' > "$usb_ep0_instance/tracing_on" || return 1
    usb_ep0_running=yes
    stock_inventory_log "USB2 EP0 trace armed context=$usb_ep0_event_context stalls=$usb_ep0_stalls"
}

stock_usb2_ep0_dump() {
    printf '0\n' > "$usb_ep0_instance/tracing_on" || return 1
    # shellcheck disable=SC2016
    usb_ep0_output=$("$usb_ep0_bb" awk '
        /^# entries-in-buffer\/entries-written:/ { print; next }
        match($0, /[0-9]+\.[0-9]+: dwc3_(ctrl_req|event|gadget_ep_cmd):/) {
            line = substr($0, RSTART, 240)
            if (line ~ /: dwc3_ctrl_req:/) {
                if (++setup <= 64)
                    print line
                else
                    omitted++
            } else if (++context <= 40) {
                print line
            } else {
                omitted++
            }
        }
        END { printf "summary setup=%d context=%d omitted=%d\n", setup, context, omitted }
    ' "$usb_ep0_instance/trace") || return 1
    while IFS= read -r usb_ep0_line; do
        stock_inventory_log "USB2 EP0 $usb_ep0_line" || return 1
    done <<EOF
$usb_ep0_output
EOF
}

stock_usb2_ep0_close() {
    usb_ep0_status=0
    if [ "$usb_ep0_running" = yes ]; then
        stock_usb2_ep0_dump || usb_ep0_status=1
    fi
    if [ "$usb_ep0_created" = yes ]; then
        "$usb_ep0_bb" rmdir "$usb_ep0_instance" || usb_ep0_status=1
    fi
    if [ "$usb_ep0_mounted" = yes ]; then
        "$usb_ep0_bb" umount "$usb_ep0_mount" || usb_ep0_status=1
    fi
    if [ "$usb_ep0_dir" = yes ]; then
        "$usb_ep0_bb" rmdir "$usb_ep0_mount" || usb_ep0_status=1
    fi
    return "$usb_ep0_status"
}
