#!/bin/bash
# SPDX-License-Identifier: MIT
# zram/91-omamobile.conf against Omarchy 4.5's drop-in: the staged file, and,
# when zram-generator is installed (or ZRAM_GENERATOR names it), the size it
# gives /dev/zram0 in a made-up root (ZRAM_GENERATOR_ROOT) with an 8 000 000 kB
# MemTotal. Nothing on this machine's zram is read or changed.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

./install "$t/stage" >/dev/null
f=$t/stage/usr/lib/systemd/zram-generator.conf.d/91-omamobile.conf
[[ -f $f ]] || fail "zram drop-in staged"
[[ $(grep -vE '^[[:space:]]*(#|$)' "$f") == $'[zram0]\nzram-size = ram / 2' ]] \
  || fail "zram drop-in sets only zram0's size, to half the RAM"
[[ 91-omamobile.conf > 90-omarchy.conf && 91-omamobile.conf < 99-local.conf ]] \
  || fail "zram drop-in sorts after Omarchy's and before a local one"
pass "the zram drop-in is staged and sets half the RAM"

gen=${ZRAM_GENERATOR:-/usr/lib/systemd/system-generators/zram-generator}
if [[ ! -x $gen ]]; then
  pass "# SKIP zram-generator not installed: sizes not checked"
  exit 0
fi
r=$t/root; d=$r/usr/lib/systemd/zram-generator.conf.d
mkdir -p "$d" "$r/proc" "$r/etc/systemd/zram-generator.conf.d"
printf 'MemTotal:        8000000 kB\nMemFree:         4000000 kB\n' > "$r/proc/meminfo"
: > "$r/proc/cmdline"
# Omarchy 4.5's default/systemd/zram-generator.conf.d/90-omarchy.conf.
printf '[zram0]\nzram-size = ram\ncompression-algorithm = zstd\nswap-priority = 100\n' > "$d/90-omarchy.conf"
size() {
  rm -rf "$t/out"; mkdir "$t/out"
  ZRAM_GENERATOR_ROOT=$r "$gen" "$t/out" 2>&1 | sed -n 's/.*\/dev\/zram0 with \([0-9]*\)MB.*/\1/p'
}
[[ $(size) == 7812 ]] || fail "zram-generator reads the made-up root (Omarchy alone: the whole RAM)"
cp "$f" "$d/"
[[ $(size) == 3906 ]] || fail "with the drop-in, zram0 is half the RAM"
grep -qx 'Priority=100' "$t/out/dev-zram0.swap" || fail "Omarchy's swap priority still applies"
# An /etc main file left from archinstall or an older Omarchy is outranked.
printf '[zram0]\nzram-size = ram\n' > "$r/etc/systemd/zram-generator.conf"
[[ $(size) == 3906 ]] || fail "a leftover /etc/systemd/zram-generator.conf doesn't undo it"
printf '[zram0]\nzram-size = 2048\n' > "$r/etc/systemd/zram-generator.conf.d/99-local.conf"
[[ $(size) == 2048 ]] || fail "a local 99-local.conf still decides"
pass "zram-generator: half the RAM over Omarchy's, a local drop-in still wins"
