# SPDX-License-Identifier: MIT
# shellcheck shell=sh

# Called only after the D1 storage inventory and read-only guard pass.
stock_ufs_refclk() (
    refclk_bb=$1
    refclk_sys=$2
    refclk_device=$refclk_sys/bus/platform/devices/3c2d0000.ufs
    refclk_driver=$refclk_sys/bus/platform/drivers/google-ufshcd

    if [ ! -L "$refclk_device" ] ||
       ! refclk_path=$("$refclk_bb" readlink -f "$refclk_device") ||
       [ "${refclk_path##*/}" != 3c2d0000.ufs ]; then
        stock_inventory_log 'UFS device refclk refused: controller identity unavailable'
        return 1
    fi
    case $refclk_path in
        "$refclk_sys"/devices/platform/*) ;;
        *)
            stock_inventory_log 'UFS device refclk refused: controller sysfs path mismatch'
            return 1 ;;
    esac
    if [ ! -L "$refclk_path/driver" ] ||
       [ "$("$refclk_bb" readlink -f "$refclk_path/driver")" != "$refclk_driver" ]; then
        stock_inventory_log 'UFS device refclk refused: stock driver is not bound'
        return 1
    fi

    refclk_attr=$refclk_path/attributes/reference_clock_frequency
    if [ -L "$refclk_path/attributes" ] || [ -L "$refclk_attr" ] || [ ! -f "$refclk_attr" ]; then
        stock_inventory_log 'UFS device refclk refused: stock attribute unavailable'
        return 1
    fi
    if ! refclk_value=$("$refclk_bb" timeout -k 1 8 "$refclk_bb" cat "$refclk_attr"); then
        stock_inventory_log 'UFS device refclk refused: attribute read failed or timed out'
        return 1
    fi
    case $refclk_value in
        0x????????) ;;
        *)
            stock_inventory_log 'UFS device refclk refused: malformed attribute'
            return 1 ;;
    esac
    case ${refclk_value#0x} in
        *[!0-9a-fA-F]*)
            stock_inventory_log 'UFS device refclk refused: malformed attribute'
            return 1 ;;
    esac
    case $refclk_value in
        0x00000000) refclk_hz=19200000 ;;
        0x00000001) refclk_hz=26000000 ;;
        0x00000002) refclk_hz=38400000 ;;
        0x00000003) refclk_hz=52000000 ;;
        *)
            stock_inventory_log "UFS device refclk read raw=$refclk_value encoding=unknown"
            return 1 ;;
    esac
    stock_inventory_log "UFS device refclk read raw=$refclk_value attribute_hz=$refclk_hz"
)
