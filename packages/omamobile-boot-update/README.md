<!-- SPDX-License-Identifier: MIT -->
# omamobile-boot-update

Turns the installed kernel package (`linux-omamobile`) into this phone's
slot-B boot images and writes them, on the phone, with the commands
`bin/omamobile images` and `push` run from the laptop. The design is
[RELEASES](../../docs/RELEASES.md) §5.3 and §5.5; the first attended test on
the Pixel 7 Pro is [KERNEL-UPDATE-PLAN](../../device/cheetah/KERNEL-UPDATE-PLAN.md).

## When it writes

The pacman hook (`90-omamobile-boot.hook`) runs after a transaction that
changes a kernel release's `vmlinuz` or DTBs, the descriptor, the dtbo, the
overlays or the initramfs. It writes slot B only when
`/etc/omamobile/boot-update.conf` says `AUTO_WRITE=yes`, which
`tools/install-phone` writes on a release install. A development phone has
no such file, and `bin/omamobile push` stays slot B's only writer there.

It writes only `<image>_b` for the descriptor's `BOOT_IMAGES`, found by GPT
name on the main UFS LUN, on the storage guard's allowlist and left writable
by the guard, and reads every image back. It never reboots.

## Commands

| Command | What it does |
| --- | --- |
| `omamobile-boot-update status` | the device, `AUTO_WRITE`, the release slot B holds, the saved set, the partitions |
| `omamobile-boot-update preflight [--json]` | read-only: would a write be allowed now? (`omamobile-update` asks before a kernel update) |
| `omamobile-boot-update write --dry-run` | builds the images in a temporary directory and prints the plan; writes nothing |
| `sudo omamobile-boot-update write` | builds, checks, saves slot B, writes and verifies (asks for the codename) |
| `omamobile-boot-update rollback --dry-run` | what a rollback would write |
| `sudo omamobile-boot-update rollback` | writes the saved previous set back and restores its modules |

## Rolling back a kernel

`sudo omamobile-boot-update rollback` writes back slot B as it was before
the last write that replaced a set that had booted, and puts that release's
modules back in `/usr/lib/modules`. Restart to boot it.

The newer `linux-omamobile` stays installed, and the next update that
changes a kernel or boot file writes it to slot B again. To hold it, add it
to `IgnorePkg` in `/etc/pacman.conf` (the tool prints this and never edits
`pacman.conf` itself; there is no `Include` in `[options]` to hang a drop-in
on):

```sh
sudo sed -i '/^\[options\]/a IgnorePkg = linux-omamobile' /etc/pacman.conf
```

Delete that line again to take kernel updates. Installing the older package
from the cache (`sudo pacman -U /var/cache/pacman/pkg/linux-omamobile-<version>-aarch64.pkg.tar.zst`)
instead writes that kernel through the hook and leaves nothing to hold.

If the phone doesn't boot the new images at all, ABL falls back to stock
Android on slot A after its tries (on a phone whose slot B is not marked
successful), or stops in fastboot: hold Volume Down + Power about 20 s and
flash the saved images in `/var/lib/omamobile/boot/previous/` with
`bin/omamobile flash`'s path, or the release bundle's installer.

## AVB footers

The footers are signed with AOSP's public RSA-4096 test key (`avb/`, its
source and checksum in `avb/SOURCE`), as `bin/omamobile images` signs them,
so the phone's images are the laptop's byte for byte (`tests/boot-update-parity`).
Every install's bootloader is unlocked, and an unlocked bootloader accepts
any key on a chained partition's footer; it refuses only a missing footer.
`AVB_KEY=/path` in the config replaces the key.

## Files

- `/usr/share/omamobile/device.conf`, `/usr/lib/omamobile/<codename>/` (dtbo,
  initramfs, overlays): from the device package (`tools/stage-boot-files`);
  only `omamobile-device-cheetah` ships them so far, and on any other phone
  the hook refuses ("does not ship its boot files yet").
- `/var/lib/omamobile/boot/`: `next/` (a build), `current/` (what was last
  written), `previous/` (the saved set: whole partitions and modules, about
  the size of slot B's partitions plus one module tree), `incomplete` (a
  write that stopped).
- `/run/omamobile/boot-update.json`: the last result, which the update
  sheet's restart step reads.
