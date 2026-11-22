#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs inside an aarch64 Alpine container. Only files under /out change.
set -eu

: "${KERNEL_RELEASE:?KERNEL_RELEASE must be passed in}"

apk add --no-cache cpio gcc musl-dev gzip kmod python3 dropbear

stage=/tmp/dipper-initramfs
mkdir -p "$stage"
apk --root "$stage" --initdb --no-cache \
  --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys add \
  alpine-baselayout busybox busybox-extras dropbear iproute2 util-linux \
  e2fsprogs e2fsprogs-extra kmod

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

# Keep only the watchdog module this initramfs loads, with its dependencies.
# The full tree is ~1764 modules and dominates the image: with the PHYs, UFS,
# i2c and simpledrm built in, almost none of it is reachable here, and ABL
# refuses a boot image that grows too large. Everything else belongs in the
# root filesystem, not here. The pruner reads modules.dep and fails loudly
# rather than silently emptying the tree.
python3 /input/prune-modules.py \
  "$stage/usr/lib/modules/$KERNEL_RELEASE" qcom_wdt
depmod -b "$stage" "$KERNEL_RELEASE"

# The modules the init loads must exist AND match this kernel exactly, or the
# phone boots to a black screen with no watchdog taken over.
for module in qcom_wdt; do
  path=$(modinfo -b "$stage" -k "$KERNEL_RELEASE" -n "$module")
  [ "$(modinfo -F vermagic "$path" | cut -d ' ' -f1)" = "$KERNEL_RELEASE" ] || {
    echo "module $module does not match $KERNEL_RELEASE" >&2; exit 1; }
done

cp /input/init "$stage/init"
python3 /input/patch-init.py "$stage/init"
chmod 755 "$stage/init"

echo xiaomi,dipper > "$stage/etc/omamobile-compatible"
: > "$stage/etc/omamobile-ufs-rw"
if [ -n "${OMAMOBILE_NFSROOT:-}" ]; then
  case "$OMAMOBILE_NFSROOT" in
    *[!A-Za-z0-9.:/_-]*|*..*|*//*|:*:*) echo "invalid OMAMOBILE_NFSROOT" >&2; exit 1 ;;
  esac
  case "$OMAMOBILE_NFSROOT" in *:/*) ;; *) echo "invalid OMAMOBILE_NFSROOT" >&2; exit 1 ;; esac
  printf '%s\n' "$OMAMOBILE_NFSROOT" > "$stage/etc/omamobile-nfsroot"
fi

echo 'Xiaomi Mi 8 Omarchy' > "$stage/etc/omamobile-usb-product"

gcc -Os -static -o "$stage/usr/local/bin/reboot-to" \
  /input/reboot-to.c

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
echo "dipper initramfs built for $KERNEL_RELEASE; all UFS partitions stay read-only"
