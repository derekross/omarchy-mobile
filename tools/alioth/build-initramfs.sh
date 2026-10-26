#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs in the recorded aarch64 Alpine container. Only local image files change.
set -eu
apk add --no-cache cpio gcc musl-dev gzip kmod python3 dropbear
stage=/tmp/alioth-initramfs
mkdir -p "$stage"
apk --root "$stage" --initdb --no-cache \
  --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys add \
  alpine-baselayout busybox busybox-extras dropbear iproute2 util-linux \
  e2fsprogs e2fsprogs-extra kmod
mkdir -p "$stage/proc" "$stage/sys" "$stage/dev" "$stage/run" "$stage/root/.ssh" \
  "$stage/usr/lib/modules" "$stage/usr/lib/firmware" "$stage/etc/dropbear" "$stage/usr/local/bin"
# Alpine is not usr-merged. kmod and the kernel look below /lib.
ln -s ../usr/lib/modules "$stage/lib/modules"
ln -s ../usr/lib/firmware "$stage/lib/firmware"
cp /input/key.pub "$stage/root/.ssh/authorized_keys"
chmod 700 "$stage/root/.ssh"
chmod 600 "$stage/root/.ssh/authorized_keys"
# Keep the rescue server's identity stable across boots of this owner's
# images. This private key remains in ignored local output, never in git.
hostkey=/out/dropbear_ed25519_host_key
if [ ! -s "$hostkey" ]; then
  umask 077
  dropbearkey -t ed25519 -f "$hostkey" >/dev/null 2>&1
fi
cp "$hostkey" "$stage/etc/dropbear/dropbear_ed25519_host_key"
chmod 600 "$stage/etc/dropbear/dropbear_ed25519_host_key"
chown "${OUT_UID:-0}:${OUT_GID:-0}" "$hostkey"
release=$(cat /reference/include/config/kernel.release)
case "$release" in 6.15.1-sm8250) ;; *) echo 'Unreviewed kernel release' >&2; exit 1 ;; esac
cp -a /reference/modules/modules/"$release" "$stage/usr/lib/modules/"
cp -a /reference/boot-firmware/. "$stage/usr/lib/firmware/"
depmod -b "$stage" "$release"
for module in qcom-wdt panel-samsung-ams667xx01; do
  path=$(modinfo -b "$stage" -k "$release" -n "$module")
  [ "$(modinfo -F vermagic "$path" | cut -d ' ' -f1)" = "$release" ] || exit 1
done
cp /src/initramfs/init "$stage/init"
python3 - "$stage/init" "$release" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = 'hostname omamobile\n'
assert s.count(needle) == 1
s = s.replace(needle, '''# Matching Qualcomm watchdog and panel modules are required before Arch.
modprobe qcom-wdt || echo "omamobile: qcom watchdog module failed" >/dev/kmsg
if [ -c /dev/watchdog0 ]; then
  watchdog -t 5 -T 30 /dev/watchdog0
fi
modprobe panel-samsung-ams667xx01 || echo "omamobile: panel module failed" >/dev/kmsg
hostname omamobile
''')
needle = 'mkdir -p $g/functions/ncm.usb0 $g/functions/acm.GS0\n'
assert s.count(needle) == 1
s = s.replace(needle, needle + '''# Locally administered addresses, unrelated to the phone's factory identity.
echo 02:10:42:00:00:01 > $g/functions/ncm.usb0/dev_addr
echo 02:10:42:00:00:02 > $g/functions/ncm.usb0/host_addr
''')
needle = 'dropbear -R -E -p 22'
assert s.count(needle) == 1
s = s.replace(needle, 'dropbear -R -E -s -p 172.16.42.1:22')
p.write_text(s)
PY
chmod 755 "$stage/init"
echo xiaomi,alioth > "$stage/etc/omamobile-compatible"
echo userdata > "$stage/etc/omamobile-ufs-rw"
echo 'POCO F3 Omarchy' > "$stage/etc/omamobile-usb-product"
gcc -Os -static -o "$stage/usr/local/bin/reboot-to" \
  /src/packages/omamobile-device-cheetah/src/reboot-to.c
# Verify userspace actually executes under ARM emulation before packaging.
chroot "$stage" /bin/busybox true
chroot "$stage" /usr/sbin/dropbear -h >/tmp/dropbear-help 2>&1 || [ "$?" = 1 ]
grep -q 'Dropbear' /tmp/dropbear-help
python3 - "$stage" <<'PY'
import os
from pathlib import Path
import sys
root = Path(sys.argv[1])
for path in list(root.rglob('*')) + [root]:
    os.utime(path, (1790636353, 1790636353), follow_symlinks=False)
PY
(cd "$stage" && find . -print0 | sort -z | cpio --null --quiet -o -H newc --owner=0:0 --reproducible) \
  | gzip -n -9 > /out/initramfs.cpio.gz
cp /tmp/dropbear-help /out/dropbear-help.txt
chown "${OUT_UID:-0}:${OUT_GID:-0}" /out/initramfs.cpio.gz /out/dropbear-help.txt
echo "ARM initramfs built; UFS guard permits userdata only"
