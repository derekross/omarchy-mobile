# SPDX-License-Identifier: MIT
# shellcheck shell=sh
# Only read partition metadata. Linux reports sysfs size in 512-byte sectors.

stock_inventory_partname() (
    name=
    found=0
    while IFS= read -r line; do
        case $line in
            PARTNAME=*) name=${line#PARTNAME=}; found=$((found + 1)) ;;
        esac
    done < "$1"
    [ "$found" -eq 1 ] && printf '%s\n' "$name"
)

stock_inventory_slot_b() (
    set -f
    provided=0
    if [ -r "$1" ]; then
        while IFS= read -r line; do
            case $line in
                'androidboot.slot_suffix = "_b"'|androidboot.slot_suffix=_b)
                    [ "$provided" -eq 0 ] || return 1
                    provided=1 ;;
                androidboot.slot_suffix[[:space:]=]*) return 1 ;;
            esac
        done < "$1"
    fi
    count=0
    [ -r "$2" ] && IFS= read -r line < "$2" || return 1
    for arg in $line; do
        case $arg in
            androidboot.slot_suffix=_b|'androidboot.slot_suffix="_b"')
                count=$((count + 1)) ;;
            androidboot.slot_suffix=*) return 1 ;;
        esac
    done
    [ "$count" -le 1 ] && [ "$((provided + count))" -ge 1 ]
)

stock_inventory_no_scsi_disks() (
    set +f
    [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] || return 1
    for disk in "$1"/sd*; do
        [ ! -e "$disk" ] || return 1
    done
)

stock_inventory_handoff() (
    [ -r "$1" ] || return 1
    if IFS= read -r loaded < "$1" || [ -n "$loaded" ]; then
        return 1
    fi
    stock_inventory_no_scsi_disks "$2"
)

stock_inventory_preloads() (
    busybox=$1
    manifest=$2
    proc_modules=$3
    if [ ! -f "$manifest" ] || [ -L "$manifest" ] || [ ! -r "$manifest" ] ||
       [ ! -r "$proc_modules" ]; then
        printf '%s\n' 'preload manifest or proc modules unavailable'
        return 1
    fi
    # shellcheck disable=SC2016
    "$busybox" awk '
        function fail(message) {
            print message
            failed = 1
            exit 1
        }
        FILENAME == ARGV[1] {
            if ($0 !~ /^[A-Za-z0-9][A-Za-z0-9_]*$/)
                fail("invalid preload manifest entry")
            if ($0 in expected)
                fail("duplicate preload manifest entry: " $0)
            expected[$0] = 1
            names[++count] = $0
            next
        }
        {
            if (NF < 6 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9_]*$/)
                fail("invalid proc modules entry")
            if (!($1 in expected))
                fail("unexpected preload: " $1)
            if ($1 in loaded)
                fail("duplicate preload: " $1)
            if ($5 != "Live")
                fail("preload is not live: " $1)
            loaded[$1] = 1
        }
        END {
            if (failed)
                exit 1
            if (!count)
                fail("empty preload manifest")
            for (i = 1; i <= count; i++)
                if (!(names[i] in loaded))
                    fail("missing preload: " names[i])
            for (i = 1; i <= count; i++)
                printf "%s%s", i == 1 ? "" : " ", names[i]
            print ""
        }
    ' "$manifest" "$proc_modules"
)

stock_inventory_pkvm_ready() (
    busybox=$1
    platform=$2
    amb_link=$platform/devices/4190000.amb_smmu/driver
    expected_driver=$platform/drivers/kvm-arm-smmu-v3
    if [ ! -L "$amb_link" ] || [ ! -d "$amb_link" ] ||
       ! driver=$("$busybox" readlink -f "$amb_link") || [ "$driver" != "$expected_driver" ]; then
        printf '%s\n' 'expected AMB driver binding not found'
        return 1
    fi
    if ! boot_log=$("$busybox" dmesg); then
        printf '%s\n' 'boot kernel log unavailable'
        return 1
    fi
    printf '%s\n' "$boot_log" | "$busybox" awk '
        /Protected hVHE mode initialized successfully/ { protected = 1 }
        /Failed to load pkvm module|Failed to init KVM IOMMU driver|pKVM enabled without an IOMMU driver/ {
            failed = 1
        }
        END {
            if (failed) {
                print "protected module or IOMMU init failure in boot kernel log"
                exit 1
            }
            if (!protected) {
                print "protected hVHE init marker missing from boot kernel log"
                exit 1
            }
        }
    '
)

stock_inventory_targets() {
    printf '%s\n' 'persist nvdata nvram protect_f protect_s modemdp modem_a modem_b devinfo'
}

stock_inventory_expected_sectors() {
    case $1 in
        persist) printf '%s\n' 262144 ;;
        nvdata) printf '%s\n' 409600 ;;
        nvram) printf '%s\n' 188416 ;;
        protect_f|protect_s) printf '%s\n' 40960 ;;
        modemdp) printf '%s\n' 2048 ;;
        modem_a|modem_b) printf '%s\n' 2840576 ;;
        devinfo) printf '%s\n' 16 ;;
        *) return 1 ;;
    esac
}

stock_inventory_scan() (
    set +f
    block_class=$1
    report=$2
    targets=$(stock_inventory_targets)
    seen=
    duplicate=
    valid=
    other=0
    for disk in "$block_class"/sd*; do
        [ -r "$disk/partition" ] && [ -r "$disk/uevent" ] || continue
        label=$(stock_inventory_partname "$disk/uevent") || label=
        if ! sectors_expected=$(stock_inventory_expected_sectors "$label"); then
            other=$((other + 1))
            continue
        fi
        case " $seen " in
            *" $label "*) duplicate="$duplicate $label"; continue ;;
        esac
        seen="$seen $label"
        IFS= read -r sectors < "$disk/size" || sectors=
        IFS= read -r ro < "$disk/ro" || ro=
        case $sectors in ''|*[!0-9]*) sectors=unknown ;; esac
        case $ro in 0|1) ;; *) ro=unknown ;; esac
        if [ "$sectors" = "$sectors_expected" ]; then
            valid="$valid $label"
            status=match
        else
            status=mismatch
        fi
        if [ "$report" = yes ]; then
            stock_inventory_log "label=$label sectors=$sectors expected=$sectors_expected ro=$ro status=$status"
        fi
    done

    result=0
    for label in $targets; do
        case " $duplicate " in
            *" $label "*)
                result=1
                if [ "$report" = yes ]; then stock_inventory_log "label=$label status=duplicate"; fi
                continue ;;
        esac
        case " $valid " in
            *" $label "*) continue ;;
        esac
        result=1
        case " $seen " in
            *" $label "*) ;;
            *)
                if [ "$report" = yes ]; then stock_inventory_log "label=$label status=missing"; fi ;;
        esac
    done
    if [ "$report" = yes ]; then
        stock_inventory_log "other_partitions=$other"
    fi
    return "$result"
)
