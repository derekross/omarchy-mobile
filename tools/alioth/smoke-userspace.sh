#!/bin/bash
# SPDX-License-Identifier: MIT
# Read-only local-image smoke, under ARM emulation. Never connects to the phone.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
root=$PWD
image=$(readlink -f "${1:-out/alioth/images/rootfs.img}")
source tools/lib/alarm.sh
alarm_fetch
builder=$(alarm_build_image "$root")
[[ -f $image ]] || { echo 'Personalized root image missing' >&2; exit 1; }
docker run --rm -i --privileged --network none --platform linux/arm64 \
  -v "$image:/input.img:ro" \
  "$builder" bash -s <<'INNER'
set -euo pipefail
mkdir -p /image-root
# Create device nodes only in this disposable container's /dev. The loop is
# allocated from the kernel's free list and bound read-only to our local file.
[[ -e /dev/loop-control ]] || mknod /dev/loop-control c 10 237
number=$(python - <<'PY'
import fcntl, os
fd = os.open('/dev/loop-control', os.O_RDWR)
try:
    print(fcntl.ioctl(fd, 0x4c82))
finally:
    os.close(fd)
PY
)
loop=/dev/loop$number
[[ -e $loop ]] || mknod "$loop" b 7 "$number"
losetup --read-only "$loop" /input.img
cleanup() {
  umount -R /image-root 2>/dev/null || true
  losetup -d "$loop"
}
trap cleanup EXIT
mount -t ext4 -o ro,noload "$loop" /image-root
mount -t tmpfs tmpfs /image-root/run
mount -t proc proc /image-root/proc
mount -t tmpfs tmpfs /image-root/dev
for spec in "null 1 3" "random 1 8" "urandom 1 9"; do
  read -r name major minor <<<"$spec"
  mknod -m 666 "/image-root/dev/$name" c "$major" "$minor"
done
ln -s /proc/self/fd /image-root/dev/fd
mkdir -p /image-root/run/alioth-check /image-root/run/sshd
chmod 700 /image-root/run/alioth-check
run() { chroot /image-root /usr/bin/env XDG_RUNTIME_DIR=/run/alioth-check "$@"; }
run /usr/bin/omamobile-firstboot --check
echo 'ok - firstboot parses the actual personalized image'
run /usr/lib/systemd/systemd --version | head -2
run /usr/bin/Hyprland --version
run /usr/bin/env QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=/run/alioth-check /usr/bin/quickshell --version
for binary in /usr/bin/Hyprland /usr/bin/quickshell /usr/bin/wayvnc /usr/bin/omacam /usr/bin/squeekboard; do
  deps=$(run /usr/bin/ldd "$binary")
  [[ $deps != *'not found'* ]] || { printf '%s\n' "$deps"; exit 1; }
  echo "ok - ARM shared libraries resolve: $binary"
done
run /usr/bin/ssh-keygen -q -t ed25519 -N '' -f /run/alioth-check/host-key
run /usr/bin/sshd -t -h /run/alioth-check/host-key
echo 'ok - actual OpenSSH configuration validates'
# QEMU user emulation cannot install OpenSSH's seccomp filter. Do not
# disable its sandbox or claim this configuration check proves a real login.
echo 'ok - OpenSSH configuration checked; full sandboxed login needs a real ARM kernel'
echo 'ok - all writes stayed in container tmpfs; image was mounted read-only without journal replay'
INNER
