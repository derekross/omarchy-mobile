# SPDX-License-Identifier: MIT
# shellcheck shell=sh

# The caller sources stock-inventory-scan.sh and supplies stock_inventory_log.
# Arguments are BusyBox, the block class directory, mountinfo, a fresh RAM
# directory and optionally the verified-topology output alongside that directory.
stock_nv_guard() (
    nv_bb=$1
    nv_block=$2
    nv_mountinfo=$3
    nv_tmp=$4
    nv_verified=${5:-}
    nv_published=no
    nv_parents='sda sdb sdc sdd sde'
    nv_targets=$(stock_inventory_targets) || return 1
    umask 077
    set +f

    nv_fail() {
        stock_inventory_log "NV read-only guard refused: $*"
        exit 1
    }

    nv_topology() (
        nv_seen=' '
        for nv_name in $nv_parents; do
            [ -L "$nv_block/$nv_name" ] && [ -d "$nv_block/$nv_name" ] ||
                nv_fail "missing UFS parent $nv_name"
        done
        for nv_entry in "$nv_block"/*; do
            nv_name=${nv_entry##*/}
            case $nv_name in
                sda|sdb|sdc|sdd|sde)
                    nv_parent=$nv_name
                    nv_type=disk ;;
                sd[a-e][1-9]*)
                    nv_part=${nv_name#???}
                    case $nv_part in *[!0-9]*) nv_fail 'invalid SCSI partition name' ;; esac
                    nv_parent=${nv_name%"$nv_part"}
                    nv_type=partition ;;
                sd*) nv_fail 'unexpected SCSI device' ;;
                *)
                    nv_label=$(stock_inventory_partname "$nv_entry/uevent" 2>/dev/null) || continue
                    if stock_inventory_expected_sectors "$nv_label" >/dev/null; then
                        nv_fail 'expected NV label on a non-UFS device'
                    fi
                    continue ;;
            esac

            nv_path=$("$nv_bb" readlink -f "$nv_entry") || nv_fail "cannot resolve $nv_name"
            case $nv_path in *[!a-zA-Z0-9_./:@+-]*) nv_fail "invalid sysfs path for $nv_name" ;; esac
            case $nv_type:$nv_path in
                disk:*/3c2d0000.ufs/*/block/"$nv_parent") ;;
                partition:*/3c2d0000.ufs/*/block/"$nv_parent"/"$nv_name")
                    [ "${nv_path%/*}" = "$("$nv_bb" readlink -f "$nv_block/$nv_parent")" ] ||
                        nv_fail "parent identity mismatch for $nv_name" ;;
                *) nv_fail "unexpected UFS topology for $nv_name" ;;
            esac
            IFS= read -r nv_devnum < "$nv_entry/dev" || nv_fail "missing device number for $nv_name"
            # shellcheck disable=SC2016
            nv_label=$("$nv_bb" awk -F= -v name="$nv_name" -v type="$nv_type" -v dev="$nv_devnum" '
                { value=substr($0, index($0, "=")+1) }
                $1 == "DEVNAME" { got_name=value; names++ }
                $1 == "DEVTYPE" { got_type=value; types++ }
                $1 == "MAJOR" { major=value; majors++ }
                $1 == "MINOR" { minor=value; minors++ }
                $1 == "PARTNAME" { label=value; labels++ }
                END {
                    if (names != 1 || got_name != name || types != 1 || got_type != type ||
                        majors != 1 || minors != 1 || major !~ /^[1-9][0-9]*$/ ||
                        minor !~ /^(0|[1-9][0-9]*)$/ || major+0 > 4095 || minor+0 > 1048575 ||
                        major ":" minor != dev || labels > 1)
                        exit 1
                    print label
                }' "$nv_entry/uevent") || nv_fail "device identity mismatch for $nv_name"

            nv_holders=$nv_entry/holders
            [ -d "$nv_holders" ] && [ -r "$nv_holders" ] && [ -x "$nv_holders" ] ||
                nv_fail "holders unavailable for $nv_name"
            for nv_holder in "$nv_holders"/*; do
                if [ -e "$nv_holder" ] || [ -L "$nv_holder" ]; then
                    nv_fail "active holder for $nv_name"
                fi
            done

            nv_kind=other
            nv_sectors=0
            if [ "$nv_type" = disk ]; then
                [ -z "$nv_label" ] && [ ! -e "$nv_entry/partition" ] || nv_fail "invalid disk $nv_name"
                nv_kind=parent
            elif nv_expected=$(stock_inventory_expected_sectors "$nv_label"); then
                [ -r "$nv_entry/partition" ] || nv_fail "missing partition number for $nv_name"
                case $nv_seen in *" $nv_label "*) nv_fail "duplicate NV label $nv_label" ;; esac
                nv_seen="$nv_seen$nv_label "
                IFS= read -r nv_sectors < "$nv_entry/size" || nv_fail "size unavailable for $nv_label"
                [ "$nv_sectors" = "$nv_expected" ] || nv_fail "size mismatch for $nv_label"
                nv_kind=target
            fi
            # Other labels are never passed on to the caller or used as paths.
            [ "$nv_kind" = target ] || nv_label=-
            printf '%s %s %s %s %s %s\n' "$nv_kind" "$nv_label" "$nv_name" "$nv_devnum" "$nv_sectors" "$nv_path"
        done
        for nv_label in $nv_targets; do
            case $nv_seen in *" $nv_label "*) ;; *) nv_fail "missing NV label $nv_label" ;; esac
        done
    )

    nv_unmounted() {
        # shellcheck disable=SC2016
        "$nv_bb" awk '
            FILENAME == ARGV[1] { if (seen[$4]++) bad=1; next }
            { if (NF < 10 || $3 !~ /^[0-9]+:[0-9]+$/ || $3 in seen) bad=1; mounts++ }
            END { exit (bad || !mounts) }
        ' "$nv_tmp/topology.before" "$nv_mountinfo"
    }

    nv_guard_nodes() (
        nv_action=$1
        nv_scope=$2
        while IFS=' ' read -r nv_kind nv_label nv_name nv_devnum nv_sectors nv_path; do
            [ "$nv_kind" != other ] || continue
            [ "$nv_scope" = all ] || [ "$nv_kind" = "$nv_scope" ] || continue
            nv_entry=$nv_block/$nv_name
            if ! IFS= read -r nv_current < "$nv_entry/dev" || [ "$nv_current" != "$nv_devnum" ] ||
               [ "$("$nv_bb" readlink -f "$nv_entry")" != "$nv_path" ]; then
                nv_fail "device moved before $nv_action for $nv_name"
            fi
            nv_major=${nv_devnum%:*}
            nv_minor=${nv_devnum#*:}
            nv_node=$nv_tmp/node
            nv_hex=$(printf '%x:%x' "$nv_major" "$nv_minor") || nv_fail "invalid device number for $nv_name"
            "$nv_bb" mknod -m 0600 "$nv_node" b "$nv_major" "$nv_minor" &&
                [ -b "$nv_node" ] && [ "$("$nv_bb" stat -c '%t:%T' "$nv_node")" = "$nv_hex" ] ||
                nv_fail "temporary device mismatch for $nv_name"
            if [ "$nv_action" = apply ]; then
                "$nv_bb" blockdev --setro "$nv_node" || nv_fail "BLKROSET failed for $nv_name"
            fi
            nv_ioctl=$("$nv_bb" blockdev --getro "$nv_node") || nv_fail "BLKROGET failed for $nv_name"
            "$nv_bb" rm -f "$nv_node" || nv_fail "temporary node removal failed for $nv_name"
            if [ "$nv_ioctl" != 1 ] || ! IFS= read -r nv_sysfs < "$nv_entry/ro" || [ "$nv_sysfs" != 1 ]; then
                nv_fail "read-only verification failed for $nv_name"
            fi
            if [ "$nv_action" = verify ]; then
                stock_inventory_log "NV guard $nv_kind label=$nv_label device=$nv_name sectors=$nv_sectors ro=1"
            fi
        done < "$nv_tmp/topology.before"
    )

    nv_cleanup() {
        nv_rc=$1
        trap - 0
        if ! "$nv_bb" rm -f "$nv_tmp/node" "$nv_tmp/topology.before" "$nv_tmp/topology.after" ||
           ! "$nv_bb" rmdir "$nv_tmp"; then
            if [ "$nv_published" = yes ]; then
                "$nv_bb" rm -f "$nv_verified"
            fi
            stock_inventory_log 'NV read-only guard refused: temporary work cleanup failed'
            exit 1
        fi
        if [ "$nv_rc" = 0 ]; then
            stock_inventory_log 'NV read-only guard complete parents=5 targets=9'
        fi
        exit "$nv_rc"
    }

    nv_home=${nv_tmp%/*}
    case $nv_verified in
        ''|"$nv_home/nv-verified") ;;
        *) nv_fail 'invalid verified topology path' ;;
    esac
    case $nv_tmp in
        /dev|/dev/*|*/|*/.|*/..) nv_fail 'invalid temporary work directory' ;;
        /*) ;;
        *) nv_fail 'invalid temporary work directory' ;;
    esac
    [ -d "$nv_home" ] && [ "$("$nv_bb" readlink -f "$nv_home")" = "$nv_home" ] ||
        nv_fail 'temporary work parent must be a canonical directory'
    case $("$nv_bb" stat -f -c %T "$nv_home") in
        tmpfs|ramfs) ;;
        *) nv_fail 'temporary work parent is outside RAM' ;;
    esac
    "$nv_bb" mkdir -m 0700 "$nv_tmp" || nv_fail 'temporary work directory already exists or cannot be created'
    trap 'nv_cleanup "$?"' 0
    trap 'exit 1' HUP INT TERM

    nv_topology > "$nv_tmp/topology.before" || exit 1
    nv_unmounted || nv_fail 'UFS disk mounted, duplicate device number or mountinfo unavailable'
    nv_guard_nodes apply parent || exit 1
    nv_guard_nodes apply target || exit 1
    nv_topology > "$nv_tmp/topology.after" || exit 1
    "$nv_bb" cmp -s "$nv_tmp/topology.before" "$nv_tmp/topology.after" || nv_fail 'UFS topology changed'
    nv_unmounted || nv_fail 'UFS mount or device number changed'
    nv_guard_nodes verify all || exit 1
    if [ -n "$nv_verified" ]; then
        "$nv_bb" ln -T "$nv_tmp/topology.before" "$nv_verified" ||
            nv_fail 'cannot publish verified topology'
        nv_published=yes
    fi
    nv_cleanup 0
)
