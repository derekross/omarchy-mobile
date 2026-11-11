#!/bin/bash
# SPDX-License-Identifier: MIT
# Push a test kernel to the Pixel 9a and start the sleep series loop on it.
# A rewrite of the owner's kit launcher that the S1 runs used, with the owner's paths as arguments:
#   device/tegu/bringup/sleep-kernel-run.sh KERNEL_OUT [N] [S]
# KERNEL_OUT holds arch/arm64/boot/Image and the tegu DTB; bin/omamobile
# images is run twice and must give the same images (a reproducibility check,
# as the daily kit does), then bin/omamobile push writes slot B and reboots.
# The boot is checked (`uname -r`, the storage guard, no emergency_ro), and
# sleep-series-loop.sh starts with N sleeps of S s (defaults 300 and 60).
# Attended first: the first run of any new kernel, module or script is watched
# by a person who can press the buttons (AGENTS.md, the 9a's sleep rule);
# the loop's own recovery budget is in sleep-series-loop.sh.
set -euo pipefail
R=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${1:?Usage: sleep-kernel-run.sh KERNEL_OUT [N] [S]}; N=${2:-300}; S=${3:-60}
PS=$R/tools/phone-ssh
IMG=$OUT/arch/arm64/boot/Image; DTB=$OUT/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dtb
[[ -f $IMG && -f $DTB ]] || { echo "no Image or DTB under $OUT" >&2; exit 1; }
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
sha() { sha256sum "$1" | cut -c1-16; }
say "Image $(sha "$IMG"), DTB $(sha "$DTB")"
for i in $(seq 300); do ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; sleep 1; done
"$PS" --fresh 'systemctl is-active -q x-awake || systemd-run -q --unit=x-awake systemd-inhibit --what=sleep --who=sleep-kernel-run --why="kernel push" --mode=block sleep 10800; uname -r' || { echo "no SSH" >&2; exit 1; }
export DEVICE=tegu KERNEL_OUT=$OUT
a=$("$R/bin/omamobile" images >/dev/null 2>&1 && cat "$OUT"/images/{boot,init_boot,vendor_boot,vendor_kernel_boot,dtbo}.img | sha256sum | cut -c1-16)
b=$("$R/bin/omamobile" images >/dev/null 2>&1 && cat "$OUT"/images/{boot,init_boot,vendor_boot,vendor_kernel_boot,dtbo}.img | sha256sum | cut -c1-16)
[[ -n $a && $a == "$b" ]] || { echo "the images are not reproducible ($a vs $b)" >&2; exit 1; }
say "images $a, pushing"
"$R/bin/omamobile" push
say "pushed; waiting for the boot"
for i in $(seq 480); do ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && timeout 10 "$PS" --fresh true 2>/dev/null && break; sleep 1; done
sleep 30
"$PS" --fresh 'uname -r; uname -v; grep -c emergency_ro /proc/mounts; cat /sys/devices/platform/soc/13200000.ufs/spm_lvl; blockdev --getro /dev/sda 2>/dev/null; dmesg | grep -cE "link startup failed|Host init failed|I/O error" || true' | tee /tmp/sleep-kernel-run-boot.txt
grep -q "$(strings "$IMG" | grep -m1 -oE 'Linux version [^ ]+' | cut -d' ' -f3)" /tmp/sleep-kernel-run-boot.txt || { echo "the palmtop did not come up on this Image" >&2; exit 1; }
say "up; starting the series loop (N=$N, S=$S)"
N=$N S=$S exec "$R/device/tegu/bringup/sleep-series-loop.sh"
