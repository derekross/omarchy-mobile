#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
patches = (
    ("hostname omamobile\n",
     """# SDM845's watchdogs keep running until a driver claims them.
modprobe qcom_wdt || echo "omamobile: qcom watchdog module failed" >/dev/kmsg
if [ -c /dev/watchdog0 ]; then
  watchdog -t 5 -T 30 /dev/watchdog0
fi
hostname omamobile
""", "hostname anchor"),
    ('dropbear -R -E -p 22 2>/dev/null && say "ssh: root@172.16.42.1"\n',
     """usb_addr=$(ip -o -4 addr show dev usb0 scope global | awk '{ sub(/\\/.*/, "", $4); print $4; exit }')
if [ -n "$usb_addr" ]; then
  dropbear -E -s -p "$usb_addr:22" -r /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null && say "ssh: root@$usb_addr"
fi
""", "dropbear anchor"),
    ("no USB host, crashing in 20 s so ABL falls back to slot A",
     "no USB host; RAM-only probe will reboot in 20 s",
     "no-USB recovery message"),
)
for old, new, name in patches:
    assert s.count(old) == 1, f"shared init changed: {name}"
    s = s.replace(old, new)
p.write_text(s)
