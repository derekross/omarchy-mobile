# SPDX-License-Identifier: MIT

stage_grizzly_m1() {
  local img=$1 version=$2 serial vars cur
  [[ $DEVICE == grizzly ]] || die "--stage-only is for the Grizzly M1 diagnostic"
  [[ -n ${FASTBOOT_SERIAL:-} ]] || die "--stage-only requires FASTBOOT_SERIAL"
  [[ $version =~ ^[a-zA-Z0-9.-]+$ ]] || die "--bootloader-slots-match needs a verified bootloader version"
  images_for_device "$img"
  serial=$(fastboot_serial) || exit 1
  vars=$(timeout 10 fastboot -s "$serial" getvar all 2>&1) \
    || die "could not read the phone's Fastboot variables"
  # D1 reports the executing bootloader version. Include the independently
  # verified version from the operator, checking for conflicts if both exist.
  python3 "$ROOT/device/grizzly/bringup/check-slot-b.py" "$img" "$img/SHA256SUMS" \
    --fastboot-vars /dev/stdin --require-healthy-a <<< "$vars"$'\n'"version-bootloader:b: $version" \
    || die "Grizzly preflight failed; no images were written"
  flash_slot_b "$serial" "$img" boot init_boot vendor_boot vendor_kernel_boot dtbo
  cur=$(timeout 10 fastboot -s "$serial" getvar current-slot 2>&1) \
    || die "slot B was staged, but Fastboot did not confirm the active slot; resolve before booting"
  [[ $(sed -n 's/^current-slot: *_\{0,1\}\([ab]\)$/\1/p' <<< "$cur") == a ]] \
    || die "slot B was staged, but Fastboot did not confirm slot A active; resolve before booting"
  say "Grizzly M1 staged to slot B. Fastboot confirms slot A active"
}
