#!/bin/sh
# Resolve androidboot.slot_suffix the same way device/dodge/chainload/init does.
# Usage: resolve-slot-suffix.sh <bootconfig-file-or-empty> <bootargs-file-or-empty>
# Prints the bare suffix (e.g. _b) or nothing. For tests; not packed into stage 1.
set -eu
BOOTCONFIG=${1:-}
BOOTARGS=${2:-}
SLOT_SUFFIX=
if [ -n "$BOOTCONFIG" ] && [ -f "$BOOTCONFIG" ]; then
  SLOT_SUFFIX=$(awk -F= '/^androidboot\.slot_suffix/ {
    v=$2; gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit
  }' "$BOOTCONFIG")
fi
if [ -z "$SLOT_SUFFIX" ] && [ -n "$BOOTARGS" ] && [ -f "$BOOTARGS" ]; then
  # shellcheck disable=SC2046
  for tok in $(cat "$BOOTARGS"); do
    case $tok in
      androidboot.slot_suffix=*) SLOT_SUFFIX=${tok#androidboot.slot_suffix=} ;;
    esac
  done
fi
printf '%s' "$SLOT_SUFFIX"
