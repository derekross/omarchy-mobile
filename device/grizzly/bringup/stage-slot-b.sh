#!/bin/bash
# SPDX-License-Identifier: MIT
# Stage the five reviewed Grizzly images while stock A remains selected.
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }

[[ ( $# == 3 || ( $# == 5 && ${4:-} == --before-rescue ) ) && $2 == --bootloader-slots-match ]] ||
  die "usage: FASTBOOT_SERIAL=SERIAL $0 IMAGES --bootloader-slots-match VERSION [--before-rescue CAPTURE]"
images=$1
version=$3
shift 3
serial=${FASTBOOT_SERIAL:-}
[[ -n $serial ]] || die "FASTBOOT_SERIAL is required"
[[ $version =~ ^[a-zA-Z0-9.-]+$ ]] || die "an independently verified slot B bootloader version is required"
[[ $(cat "$images/DEVICE" 2>/dev/null) == grizzly ]] ||
  die "the image bundle must identify Grizzly"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
devices=$(timeout 3 fastboot devices) || die "could not list Fastboot devices"
awk -v serial="$serial" '$1 == serial && $2 == "fastboot" { count++ } END { exit count != 1 }' <<<"$devices" ||
  die "FASTBOOT_SERIAL is not a phone in Fastboot"
vars=$(timeout 10 fastboot -s "$serial" getvar all 2>&1) ||
  die "could not read the phone's Fastboot variables"

# D1 reports the running bootloader. The operator supplies the verified B version.
python3 "$here/check-slot-b.py" "$images" "$images/SHA256SUMS" \
  --fastboot-vars /dev/stdin --require-healthy-a "$@" \
  <<< "$vars"$'\n'"version-bootloader:b: $version" ||
  die "Grizzly preflight failed. No images were written."

for image in boot init_boot vendor_boot vendor_kernel_boot dtbo; do
  if ! output=$(timeout 60 fastboot -s "$serial" flash "${image}_b" "$images/$image.img" 2>&1); then
    die "flashing ${image}_b failed. Leave B inactive until staging passes. $output"
  fi
  printf '%s\n' "$image: staged"
done

slot=$(timeout 10 fastboot -s "$serial" getvar current-slot 2>&1) ||
  die "slot B was staged, but Fastboot did not confirm the active slot"
[[ $(sed -n 's/^current-slot: *_\{0,1\}\([ab]\)$/\1/p' <<<"$slot") == a ]] ||
  die "slot B was staged, but Fastboot did not confirm slot A active"
printf '%s\n' "Grizzly M1 staged to slot B. Fastboot confirms slot A active."
