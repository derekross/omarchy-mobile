#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs inside an aarch64 Alpine container. Only files under /out change.
# Adapted from tools/alioth/build-initramfs.sh: same class of device (non-A/B
# Qualcomm, appended DTB), different panel, watchdog name and descriptor values.
set -eu

: "${KERNEL_RELEASE:?KERNEL_RELEASE must be passed in}"

apk add --no-cache cpio gcc musl-dev gzip kmod python3 dropbear

stage=/tmp/dipper-initramfs
mkdir -p "$stage"
apk --root "$stage" --initdb --no-cache \
  --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys add \
  alpine-baselayout busybox busybox-extras dropbear iproute2 util-linux \
  e2fsprogs e2fsprogs-extra kmod \
  ${DIPPER_BRINGUP:+i2c-tools evtest strace pciutils usbutils}

mkdir -p "$stage/proc" "$stage/sys" "$stage/dev" "$stage/run" "$stage/root/.ssh" \
  "$stage/usr/lib/modules" "$stage/usr/lib/firmware" "$stage/etc/dropbear" "$stage/usr/local/bin"
# Alpine is not usr-merged; kmod and the kernel look below /lib.
ln -s ../usr/lib/modules "$stage/lib/modules"
ln -s ../usr/lib/firmware "$stage/lib/firmware"

cp /input/key.pub "$stage/root/.ssh/authorized_keys"
chmod 700 "$stage/root/.ssh"
chmod 600 "$stage/root/.ssh/authorized_keys"

# Keep the rescue server's host key stable across rebuilds, so the laptop's
# known_hosts does not change under us. Private key stays in local output.
hostkey=/out/dropbear_ed25519_host_key
if [ ! -s "$hostkey" ]; then
  umask 077
  dropbearkey -t ed25519 -f "$hostkey" >/dev/null 2>&1
fi
cp "$hostkey" "$stage/etc/dropbear/dropbear_ed25519_host_key"
chmod 600 "$stage/etc/dropbear/dropbear_ed25519_host_key"
chown "${OUT_UID:-0}:${OUT_GID:-0}" "$hostkey"

cp -a "/modules/lib/modules/$KERNEL_RELEASE" "$stage/usr/lib/modules/"
# The build tree symlinks point at the builder's paths; they are useless here.
rm -f "$stage/usr/lib/modules/$KERNEL_RELEASE/build" \
      "$stage/usr/lib/modules/$KERNEL_RELEASE/source"
depmod -b "$stage" "$KERNEL_RELEASE"

# Keep only the modules this initramfs actually loads, with their dependencies.
# The full tree is ~1764 modules and dominates the image: with the PHYs, UFS,
# i2c and simpledrm built in, almost none of it is reachable here, and ABL
# refuses a boot image that grows too large. Everything else belongs in the
# root filesystem, not here. The pruner reads modules.dep and fails loudly
# rather than silently emptying the tree.
modules=qcom_wdt
if grep -qF 'drivers/gpu/drm/panel/panel-samsung-ea8074.ko' \
    "$stage/usr/lib/modules/$KERNEL_RELEASE/modules.builtin"; then
  : > "$stage/etc/omamobile-panel-built-in"
else
  modules="$modules panel-samsung-ea8074"
fi
python3 /src/tools/dipper/prune-modules.py \
  "$stage/usr/lib/modules/$KERNEL_RELEASE" $modules
depmod -b "$stage" "$KERNEL_RELEASE"

# The modules the init loads must exist AND match this kernel exactly, or the
# phone boots to a black screen with no watchdog taken over.
for module in $modules; do
  path=$(modinfo -b "$stage" -k "$KERNEL_RELEASE" -n "$module")
  [ "$(modinfo -F vermagic "$path" | cut -d ' ' -f1)" = "$KERNEL_RELEASE" ] || {
    echo "module $module does not match $KERNEL_RELEASE" >&2; exit 1; }
done

cp /src/initramfs/init "$stage/init"
python3 - "$stage/init" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()

# SDM845 leaves the cluster watchdogs running; take them over early.
needle = 'hostname omamobile\n'
assert s.count(needle) == 1, "shared init changed: hostname anchor"
s = s.replace(needle, '''# SDM845's watchdogs keep running until a driver claims them.
modprobe qcom_wdt || echo "omamobile: qcom watchdog module failed" >/dev/kmsg
if [ -c /dev/watchdog0 ]; then
  watchdog -t 5 -T 30 /dev/watchdog0
fi
if [ ! -e /etc/omamobile-panel-built-in ]; then
  modprobe panel-samsung-ea8074 || echo "omamobile: panel module failed" >/dev/kmsg
fi
hostname omamobile
''')

# Bind the rescue sshd to the USB link only, never to every interface.
needle = 'dropbear -R -E -p 22'
assert s.count(needle) == 1, "shared init changed: dropbear anchor"
s = s.replace(needle, 'dropbear -R -E -s -p 172.16.42.1:22')
p.write_text(s)
PY
chmod 755 "$stage/init"

echo xiaomi,dipper > "$stage/etc/omamobile-compatible"
echo userdata > "$stage/etc/omamobile-ufs-rw"

# A diagnostic image, for a first boot with no cable attached: it mirrors the
# kernel log into the unused `logdump` partition so Android can read it back.
# See tools/dipper/bringup-patch-init.py. Never write this one to `boot`.
if [ "${DIPPER_BRINGUP:-0}" = 1 ]; then
  echo "userdata logdump" > "$stage/etc/omamobile-ufs-rw"
  python3 /src/tools/dipper/bringup-patch-init.py "$stage/init"
  echo 'BRING-UP IMAGE: logdump mirror on, storage guard widened' > "$stage/etc/omamobile-bringup"
fi
# Bring-up only: boot the Arch root from NFS over the USB link instead of the
# UFS, so a root filesystem can be tried without writing to the phone at all.
if [ -n "${DIPPER_NFSROOT:-}" ]; then
  echo "$DIPPER_NFSROOT" > "$stage/etc/omamobile-nfsroot"
  echo "NFS ROOT IMAGE: the Arch root comes from $DIPPER_NFSROOT, not the UFS" \
    > "$stage/etc/omamobile-nfsroot-note"
fi
echo 'Xiaomi Mi 8 Omarchy' > "$stage/etc/omamobile-usb-product"

gcc -Os -static -o "$stage/usr/local/bin/reboot-to" \
  /src/packages/omamobile-device-cheetah/src/reboot-to.c

# Prove the packaged userspace actually runs on ARM before shipping it.
chroot "$stage" /bin/busybox true
chroot "$stage" /usr/sbin/dropbear -h >/tmp/dropbear-help 2>&1 || [ "$?" = 1 ]
grep -q 'Dropbear' /tmp/dropbear-help

# Reproducible archive: fixed mtimes, sorted, no owners.
python3 - "$stage" <<'PY'
import os, sys
from pathlib import Path
root = Path(sys.argv[1])
for path in list(root.rglob('*')) + [root]:
    os.utime(path, (1790636353, 1790636353), follow_symlinks=False)
PY
(cd "$stage" && find . -print0 | sort -z | cpio --null --quiet -o -H newc --owner=0:0 --reproducible) \
  | gzip -n -9 > /out/initramfs.cpio.gz
cp /tmp/dropbear-help /out/dropbear-help.txt
chown "${OUT_UID:-0}:${OUT_GID:-0}" /out/initramfs.cpio.gz /out/dropbear-help.txt
echo "dipper initramfs built for $KERNEL_RELEASE; storage guard permits userdata only"
