#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Patch the shared initramfs init for a bring-up image.

dipper has no serial header, and ABL leaves no framebuffer that mainline can
claim, so a boot with no cable attached is completely blind. This makes the
image mirror the kernel log into the `logdump` partition (33 MiB, all zero on
this phone, used by nothing), which Android can read back afterwards with root.

That needs logdump writable, so the storage guard's allowlist is widened -- for
this image only. It deliberately weakens a safety property: the result is a
diagnostic image, never an install image, and must not be written to `boot`.
"""
import sys
from pathlib import Path

MIRROR = r'''# BRING-UP: mirror the kernel log to the logdump partition every 2 s, so a
# cable-free boot can still be read back from Android afterwards.
omamobile_logdump_dev() {
  for u in /sys/block/sd*/sd*/uevent; do
    [ -r "$u" ] || continue
    if [ "$(sed -n 's/^PARTNAME=//p' "$u")" = logdump ]; then
      echo "/dev/$(sed -n 's/^DEVNAME=//p' "$u")"
      return 0
    fi
  done
  return 1
}
omamobile_logdump_loop() {
  dev=$(omamobile_logdump_dev) || { echo "omamobile: no logdump partition" >/dev/kmsg; return; }
  [ -w "$dev" ] || { echo "omamobile: $dev is read-only; the guard kept it closed" >/dev/kmsg; return; }
  n=0
  while :; do
    n=$((n + 1))
    { echo "=== omamobile bring-up log, pass $n, uptime $(cut -d" " -f1 /proc/uptime) ==="
      dmesg
      echo "=== probe results, pass $n ==="
      # One blind boot has to answer everything worth knowing, because there is
      # no shell without a cable. Keep this read-only and cheap.
      echo "-- loaded modules --";        cat /proc/modules 2>/dev/null
      echo "-- input devices --";         cat /proc/bus/input/devices 2>/dev/null
      echo "-- drm cards --";             ls -l /sys/class/drm 2>/dev/null
      echo "-- framebuffers --";          ls -l /sys/class/graphics 2>/dev/null
      echo "-- block devices --";         ls -l /sys/block 2>/dev/null
      echo "-- net interfaces --";        ls -l /sys/class/net 2>/dev/null
      echo "-- i2c buses --";             ls -l /sys/bus/i2c/devices 2>/dev/null
      echo "-- spmi / platform probe failures --"
      for d in /sys/bus/platform/devices/*/driver; do :; done
      ls -l /sys/bus/platform/devices 2>/dev/null | head -80
      echo "-- regulators --";            ls /sys/class/regulator 2>/dev/null | head -40
      echo "-- thermal --";               ls /sys/class/thermal 2>/dev/null
      echo "-- remoteproc --";            for r in /sys/class/remoteproc/*; do [ -e "$r/state" ] && echo "$r: $(cat "$r/state")"; done
      echo "-- cmdline --";               cat /proc/cmdline 2>/dev/null
      echo "-- device tree model --";     cat /proc/device-tree/model 2>/dev/null; echo
      echo "-- uptime / mem --";          cat /proc/uptime /proc/meminfo 2>/dev/null | head -5
      echo "=== end of pass $n ==="
    } | dd of="$dev" bs=4096 conv=notrunc 2>/dev/null
    sleep 2
  done
}
omamobile_logdump_loop &
echo "omamobile: bring-up log mirror started" >/dev/kmsg
'''

ALLOW = "      boot_b|init_boot_b|vendor_boot_b|vendor_kernel_boot_b|dtbo_b|userdata) ;;"
ANCHOR = "hostname omamobile\n"


def main() -> int:
    p = Path(sys.argv[1])
    s = p.read_text()
    if s.count(ALLOW) != 1:
        raise SystemExit("shared init changed: storage-guard allowlist not found")
    if s.count(ANCHOR) != 1:
        raise SystemExit("shared init changed: hostname anchor not found")
    if "omamobile_logdump_loop" in s:
        print("already patched for bring-up")
        return 0
    s = s.replace(ALLOW, ALLOW.replace("|userdata)", "|userdata|logdump)"), 1)
    s = s.replace(ANCHOR, MIRROR + ANCHOR, 1)
    p.write_text(s)
    print("init patched: logdump allowed, log mirror started before handover")
    return 0


if __name__ == "__main__":
    sys.exit(main())
