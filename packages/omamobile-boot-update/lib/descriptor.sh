# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# The device descriptor (docs/RELEASES.md §3), read on the phone the way
# bin/omamobile's load_device reads it on the laptop: line by line, never
# sourced, with the same two line forms and the same checks. Sourced by
# omamobile-boot-update and omamobile-boot-images; the caller defines die.
#
# Only BOOT_METHOD=android-v4 (the default) is accepted: the Qualcomm chain,
# the RAM-only probe and anything else have no slot-B update path here.
# tests/boot-update-descriptor checks that every descriptor in device/ gets
# the same verdict from this file as from bin/omamobile.

# Every name a descriptor's UFS_RW may hold (bin/omamobile UFS_RW_ALLOWED,
# initramfs/init ufs_rw_load).
BU_UFS_RW_ALLOWED="boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata"
# Every image a phone writes. The partition is always <image>_b.
BU_IMAGES_ALLOWED="boot init_boot vendor_boot vendor_kernel_boot dtbo"

# bu_load_descriptor FILE: set DEV_* from FILE, or die.
bu_load_descriptor() {
  local file=$1 line n=0 key p
  local quoted='^([A-Z][A-Z0-9_]*)="([^"$`\\]*)"$' bare='^([A-Z][A-Z0-9_]*)=([^"$`\\'"'"'[:space:]]*)$'
  # Forget whatever an earlier descriptor set
  for key in $(compgen -v DEV_ || true); do unset "$key"; done
  DEV_BOOT_METHOD=android-v4
  [[ -f $file ]] || die "no device descriptor $file (the device package installs it)"
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ $line =~ $quoted || $line =~ $bare ]]; then
      printf -v "DEV_${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    else
      die "$file:$n: not a KEY=value line"
    fi
  done < "$file"
  [[ $DEV_BOOT_METHOD == android-v4 ]] \
    || die "$file: BOOT_METHOD=$DEV_BOOT_METHOD has no slot-B update path on the phone (android-v4 only)"
  [[ ${DEV_CODENAME:-} =~ ^[a-z0-9]+$ ]] || die "$file: CODENAME must be a bare codename"
  local rw_chars='^[a-z0-9_ ]+$' seen_rw=" "
  [[ -n ${DEV_UFS_RW:-} ]] || die "$file: UFS_RW is missing"
  [[ $DEV_UFS_RW =~ $rw_chars ]] || die "$file: UFS_RW may hold only partition names ([a-z0-9_]) separated by spaces"
  for p in $DEV_UFS_RW; do
    [[ $p == *_b || $p == userdata ]] || die "$file: UFS_RW may hold only *_b partitions and userdata, not $p"
    [[ " $BU_UFS_RW_ALLOWED " == *" $p "* ]] \
      || die "$file: UFS_RW may hold only slot B boot images ($BU_UFS_RW_ALLOWED), not $p"
    [[ $seen_rw != *" $p "* ]] || die "$file: UFS_RW names $p twice"
    seen_rw+="$p "
  done
  [[ $seen_rw == *" userdata "* ]] || die "$file: UFS_RW must include userdata"
  for key in CODENAME SOC PACKAGE DTB DTBO_SOURCE DTBO_BOARD_ID DTBO_BOARD_REV VENDOR_CMDLINE \
      VENDOR_PAGESIZE OS_VERSION OS_PATCH_LEVEL BOOT_IMAGES UFS_RW INITRAMFS_INIT PANEL_SIZE COMPATIBLE; do
    p="DEV_$key"
    [[ -n ${!p:-} ]] || die "$file: $key is missing"
  done
  if [[ -n ${DEV_SOC_IDS:-} && -n ${DEV_SOC_COMPATIBLE:-} ]]; then
    die "$file: SOC_IDS and SOC_COMPATIBLE are exclusive; name the one this bootloader matches on"
  elif [[ -z ${DEV_SOC_IDS:-} && -z ${DEV_SOC_COMPATIBLE:-} ]]; then
    die "$file: SOC_IDS is missing (or SOC_COMPATIBLE, for a bootloader that matches /soc_compatible)"
  fi
  local sc='^[a-z0-9]+(-[a-z0-9]+)*:0x[0-9a-f]+:[0-9]+:[0-9]+:[0-9]+$' labels=" "
  for p in ${DEV_SOC_COMPATIBLE:-}; do
    [[ $p =~ $sc ]] || die "$file: SOC_COMPATIBLE entries are label:product_id:major:minor:pkg_mode, not $p"
    [[ $labels != *" ${p%%:*} "* ]] || die "$file: SOC_COMPATIBLE names ${p%%:*} twice"
    labels+="${p%%:*} "
  done
  # The phone builds these from the descriptor's values, so they are held to
  # the forms bin/omamobile's commands accept
  for p in ${DEV_SOC_IDS:-}; do
    [[ $p =~ ^[a-z0-9]+:0x[0-9a-f]+$ ]] || die "$file: SOC_IDS entries are label:0xsoc_id, not $p"
  done
  [[ $DEV_DTB =~ ^[a-z0-9_/.-]+\.dtb$ && $DEV_DTB != *..* ]] || die "$file: DTB must be a relative .dtb path"
  [[ $DEV_VENDOR_PAGESIZE =~ ^0x[0-9a-fA-F]+$|^[0-9]+$ ]] || die "$file: VENDOR_PAGESIZE must be a number"
  [[ $DEV_OS_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$file: OS_VERSION must be A.B.C"
  [[ $DEV_OS_PATCH_LEVEL =~ ^[0-9]{4}-[0-9]{2}$ ]] || die "$file: OS_PATCH_LEVEL must be YYYY-MM"
  for p in ${DEV_DTB_OVERLAYS:-}; do
    [[ $p =~ ^[a-z0-9-]+$ ]] || die "$file: DTB_OVERLAYS: bad overlay name '$p'"
  done
  if [[ -n ${DEV_MAIN_LUN:-} ]]; then
    [[ $DEV_MAIN_LUN =~ ^sd[a-z]$ ]] || die "$file: MAIN_LUN must be a UFS LUN such as sda"
  fi
  for p in $DEV_BOOT_IMAGES; do
    [[ " $DEV_UFS_RW " == *" ${p}_b "* ]] || die "$file: ${p}_b is not in UFS_RW"
  done
  local seen=" "
  for p in $DEV_BOOT_IMAGES; do
    [[ " $BU_IMAGES_ALLOWED " == *" $p "* ]] \
      || die "$file: BOOT_IMAGES may hold only boot, init_boot, vendor_boot, vendor_kernel_boot and dtbo, not $p"
    [[ $seen != *" $p "* ]] || die "$file: BOOT_IMAGES names $p twice"
    seen+="$p "
  done
  for p in boot vendor_boot dtbo; do
    [[ $seen == *" $p "* ]] || die "$file: BOOT_IMAGES must include $p"
  done
  local avb=" "
  for p in ${DEV_AVB_FOOTERS:-}; do
    [[ $p =~ ^([a-z_]+):(0x[0-9a-f]{1,10}|[1-9][0-9]{0,11})$ ]] \
      || die "$file: AVB_FOOTERS entries are image:partition_size, not $p"
    [[ $seen == *" ${BASH_REMATCH[1]} "* ]] || die "$file: AVB_FOOTERS names ${BASH_REMATCH[1]}, which is not in BOOT_IMAGES"
    [[ $avb != *" ${BASH_REMATCH[1]} "* ]] || die "$file: AVB_FOOTERS names ${BASH_REMATCH[1]} twice"
    (( BASH_REMATCH[2] > 0 && BASH_REMATCH[2] % 4096 == 0 )) \
      || die "$file: AVB_FOOTERS: ${BASH_REMATCH[1]}'s partition size must be a positive multiple of 4096"
    avb+="${BASH_REMATCH[1]} "
  done
  if [[ -n ${DEV_AVB_FOOTERS:-} ]]; then
    [[ ${DEV_AVB_ROLLBACK_INDEX:-} =~ ^[0-9]+$ ]] || die "$file: AVB_FOOTERS needs AVB_ROLLBACK_INDEX (a number)"
    [[ ${DEV_AVB_SECURITY_PATCH:-} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
      || die "$file: AVB_FOOTERS needs AVB_SECURITY_PATCH (YYYY-MM-DD)"
  elif [[ -n ${DEV_AVB_ROLLBACK_INDEX:-}${DEV_AVB_SECURITY_PATCH:-} ]]; then
    die "$file: AVB_ROLLBACK_INDEX and AVB_SECURITY_PATCH belong with AVB_FOOTERS"
  fi
  # A device whose initramfs carries modules gets them from the release
  # being written (omamobile-boot-images appends them), so their names are
  # checked here as bin/omamobile initramfs checks them
  for p in ${DEV_INITRAMFS_MODULES:-}; do
    [[ $p =~ ^[a-z0-9_-]+$ ]] || die "$file: INITRAMFS_MODULES: bad module name '$p'"
  done
  DEV_MAIN_LUN=${DEV_MAIN_LUN:-sda}
}

# bu_has_image NAME: is NAME in the descriptor's BOOT_IMAGES?
bu_has_image() { [[ " $DEV_BOOT_IMAGES " == *" $1 "* ]]; }

# bu_avb_size NAME: the AVB_FOOTERS partition size of NAME in bytes, or nothing.
bu_avb_size() {
  local e
  for e in ${DEV_AVB_FOOTERS:-}; do
    [[ ${e%%:*} == "$1" ]] && { echo $((${e#*:})); return 0; }
  done
  return 0
}
