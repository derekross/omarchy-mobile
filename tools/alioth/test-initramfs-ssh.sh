#!/bin/bash
# SPDX-License-Identifier: MIT
# Exercise the packed ARM Dropbear and public key in a disposable container.
# Does not run /init or expose any phone/block-device mounts to the container.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
root=$PWD
image_out=$(realpath "${1:-out/alioth}")
name=omamobile-alioth-ssh-check-$$
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run --detach --name "$name" --platform linux/arm64 \
  -p 127.0.0.1::2222 --tmpfs /testroot:rw,exec \
  -v "$image_out/initramfs.cpio.gz:/initramfs.cpio.gz:ro" \
  alpine@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 \
  sh -c 'set -eu; cd /testroot; zcat /initramfs.cpio.gz | cpio -idm --quiet;
    chroot /testroot /bin/busybox sh -n /init;
    test -e dev/null || mknod -m 666 dev/null c 1 3;
    test -e dev/urandom || mknod -m 666 dev/urandom c 1 9;
    exec chroot /testroot /usr/sbin/dropbear -F -R -E -s -p 2222' >/dev/null
port=$(docker port "$name" 2222/tcp)
port=${port##*:}
passed=0
for attempt in $(seq 1 20); do
  if ssh -F /dev/null -i "$root/keys/alioth/alioth_ed25519" -p "$port" \
       -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 -o LogLevel=ERROR \
       root@127.0.0.1 /bin/busybox true 2>/dev/null; then
    passed=1; break
  fi
  sleep 1
done
if ((!passed)); then docker logs "$name"; exit 1; fi
echo 'ok - packed ARM Dropbear accepts the dedicated key and executes ARM userspace'
echo 'ok - password authentication disabled; no init, storage guard or phone command executed'
