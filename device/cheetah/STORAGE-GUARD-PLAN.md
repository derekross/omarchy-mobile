<!-- SPDX-License-Identifier: MIT -->
# The storage guard on the boot LUNs

Status (2026-11-07): **written, never booted.** Branch `guard-boot-luns` in this repository (no kernel change, no kernel branch). It needs the runbook below on the reference Pixel 7 Pro before it merges, and blocks #483.

## 1. What changes, and why

[#252](https://github.com/derekross/omarchy-mobile/issues/252), the maintainer's ruling of 2026-11-07: guard the boot LUNs the way the main LUN is already guarded.

The kernel counts a partition read-only when its own flag or its disk's flag is set (`bdev_read_only()`). Until now the guard in `initramfs/init` removed `/dev/sda` and left `sda`'s own flag clear, but set the boot LUNs' (`sdb`, `sdc`, `sdd`) **disk** flags and kept their whole-disk nodes. So a partition on a boot LUN could only be written with its disk's flag cleared too, and while it was clear, `/dev/sdd` reached every partition on that LUN (`pinfo`, `blenv`, `mfg_data` beside `devinfo`). #483 found this while writing the 8 Pro and 9a marking tool.

Now every LUN is guarded the same way:

- every whole-disk node is removed (`/dev/sda` to `/dev/sdd`), and the disks' own flags are never set;
- every partition gets its own flag, except the allowlist (`UFS_RW`), which still opens partitions of `sda` only;
- a node that won't go is retried and warned about, and the hand-over check (`ufs_unguarded`) now also refuses Arch while any whole-disk node is there, as it already did for a writable partition outside the allowlist.

Nothing becomes writable that wasn't: the boot LUNs' partitions are read-only by their own flags instead of their disks'. A tool that must write one of them clears that partition's own flag alone.

**`omamobile-boot-success` changes with it** (device-cheetah 0.1.45, raven 0.1.33, lynx 0.2.3). The marker ran `blockdev --setrw` on the whole bootloader LUN (`/dev/sdd`), then on `devinfo`. Under the new guard `/dev/sdd` is gone, so that first call fails and the marker fails (`packages/omamobile-device-cheetah/test/boot-success` shows it against the old script). It runs at every boot but writes only when slot B isn't marked yet, so a marked phone wouldn't notice until the next `flash` or `--set-active=b`. The new marker reads the disk's own flag: clear (the new guard) means it clears `devinfo`'s own flag alone and sets it again after; set (an initramfs from before this change) means it opens the disk and `devinfo` as it always did, so a fastboot rollback to an older image set still gets slot B marked.

`bin/omamobile push`, `omamobile-boot-update`, `tools/nv-backup`, `tools/phone-provision`, `omamobile-fp` and `tools/phone-smoke` work on partitions found by `PARTNAME` (and `push` and `boot-update` on `sda` alone) and never open a whole-disk node; none changes.

## 2. Runbook

Read-only steps first. Each step: commands, Expect, Pass, **Stop**, Rollback, risk. Laptop steps run in this branch's worktree; phone steps over `tools/phone-ssh` (root). Record results in §3 with the date and `uname -r`. Announce to Derek before every step marked "affects the phone".

This runbook uses `bin/omamobile push` and keeps the running kernel: only the initramfs changes. If the phone runs a packaged kernel (`uname -r` without `-push1`), stop and ask: the images then come from the device package's boot files instead.

### R1. The guard and the marker as they are (read-only; risk none)

```sh
tools/phone-ssh 'uname -r; grep slot_suffix /proc/bootconfig; pacman -Q omamobile-device-cheetah
  for d in /sys/block/sd*; do n=${d##*/}; echo "$n disk-ro=$(cat $d/ro) node=$([ -e /dev/$n ] && echo present || echo gone)"; done
  for s in /sys/block/sd*/sd*; do [ "$(cat $s/ro)" = 0 ] && echo "writable: ${s##*/} $(sed -n s/^PARTNAME=//p $s/uevent)"; done
  d=$(grep -lx PARTNAME=devinfo /sys/block/sd*/sd*/uevent); d=${d%/uevent}; echo "devinfo ${d##*/}"
  omamobile-bootctl dump /dev/${d##*/} | sed -n "/^slot b /,/retry-count/p"
  journalctl -b -u omamobile-boot-success --no-pager | tail -2'
```

- Expect: a push1 release, slot `_b`; `sda disk-ro=0 node=gone`, `sdb`, `sdc`, `sdd` `disk-ro=1 node=present` (the old guard); writable exactly `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`, `userdata`; slot b `successful:  yes`.
- Pass: all of it. **Stop:** anything else writable, slot b not marked (find out why first), a packaged kernel (see above).
- Rollback: none.

### R2. The laptop's known-good copy of slot B (read-only on the phone; risk none)

As [KERNEL-UPDATE-PLAN](KERNEL-UPDATE-PLAN.md) R2, with `OUT` the output directory the running push1 kernel came from and `KG=~/omamobile-kernel/known-good/<date>`: copy `$OUT/images/{boot,init_boot,vendor_boot,vendor_kernel_boot,dtbo}.img` and `DEVICE` into `$KG/images`, and compare each with slot B on the phone.

- Pass: five equal pairs. **Stop:** any difference (there is no known-good set to go back to).
- Rollback: none.

### L1. This branch's initramfs and images on the running kernel (laptop, no phone; risk none)

```sh
KERNEL_OUT=$OUT bin/omamobile initramfs
KERNEL_OUT=$OUT bin/omamobile images
lz4 -dc $OUT/initramfs.cpio.lz4 | grep -ac 'ufs_is_disk'
```

- Expect: the images build; the last line is 3 or more (the new guard is in the image); the kernel and modules are the running ones, so `push` skips `modules-push`.
- Pass: both. **Stop:** a build error, or 0.
- Rollback: copy `$KG/images/*.img` back into `$OUT/images/`.

### P1. The new marker, under the old initramfs (affects the phone: root file system only; risk low)

```sh
tools/phone-install-package packages/omamobile-device-cheetah      # 0.1.45
tools/phone-ssh 'pacman -Q omamobile-device-cheetah; omamobile-boot-success; echo exit $?'
```

- Expect: `0.1.45`; `slot b already marked successful`, `exit 0`; no flag touched.
- Pass: both. **Stop:** anything else.
- Rollback: reinstall 0.1.44 from the previous checkout.

### P2. Push the images (affects the phone: reboot; risk medium)

```sh
OMAMOBILE_SSH_SHARE=1 KERNEL_OUT=$OUT bin/omamobile push
```

- Expect: five `_b` writes, each verified; the phone reboots into the same `uname -r` within about a minute.
- **Stop:** the phone doesn't come back over USB in 3 minutes, or stays in the initramfs (`ssh` answers but `/proc/1/comm` is not `systemd`): read `dmesg | grep ufs-ro` from the initramfs shell first, then roll back.
- Rollback: `cp $KG/images/*.img $OUT/images/ && KERNEL_OUT=$OUT bin/omamobile push`. If nothing answers: Power held about 30 s, then Volume Down + Power about 20 s for fastboot, and `KERNEL_OUT=$KG bin/omamobile flash` (it clears slot B's mark; the old initramfs's guard sets the disk flag, and the 0.1.45 marker's old-guard path marks B again at that boot).

### R3. The guard after the boot (read-only; risk none)

```sh
tools/phone-ssh 'uname -r
  for d in /sys/block/sd*; do n=${d##*/}; echo "$n disk-ro=$(cat $d/ro) node=$([ -e /dev/$n ] && echo present || echo gone)"; done
  for s in /sys/block/sd*/sd*; do [ "$(cat $s/ro)" = 0 ] && echo "writable: ${s##*/} $(sed -n s/^PARTNAME=//p $s/uevent)"; done
  echo "partitions: $(ls -d /sys/block/sd*/sd* | wc -l), read-only: $(cat /sys/block/sd*/sd*/ro | grep -c 1)"
  dmesg | grep -c "ufs-ro: /dev/sd[a-z]*: whole-disk node removed"; dmesg | grep "ufs-ro: FAILED"
  journalctl -b -u omamobile-boot-success --no-pager | tail -2
  d=$(grep -lx PARTNAME=devinfo /sys/block/sd*/sd*/uevent); d=${d%/uevent}
  omamobile-bootctl dump /dev/${d##*/} | sed -n "/^slot b /,/retry-count/p"'
tools/phone-smoke
```

- Expect: the same release; every disk `disk-ro=0 node=gone`; writable exactly the six names of R1; read-only equals the partition count minus six; `4` removal lines and no FAILED line; the marker's `slot b already marked successful`; slot b `successful:  yes`; `phone-smoke`'s required checks ok (its storage guard check among them).
- Pass: all of it. **Stop:** a whole-disk node present, a disk flag set, anything else writable, a FAILED line, the marker failed, a smoke failure: roll back as in P2.
- Rollback: as in P2.

### R4. The window #483 needs, without a write (affects nothing written; risk low)

Clears `devinfo`'s own flag for a moment, as the marker does at a boot with slot B unmarked, and sets it again. Nothing is written. Derek's call.

```sh
tools/phone-ssh 'set -e; d=$(grep -lx PARTNAME=devinfo /sys/block/sd*/sd*/uevent); d=${d%/uevent}; p=${d##*/}; k=$(basename ${d%/*})
  trap "blockdev --setro /dev/$p" EXIT
  blockdev --setrw /dev/$p
  echo "devinfo $p ro=$(cat $d/ro); disk $k ro=$(cat /sys/block/$k/ro); siblings read-only: $(for s in /sys/block/$k/$k*; do [ $s = $d ] || cat $s/ro; done | tr -d "\n")"
  blockdev --setro /dev/$p; echo "devinfo ro=$(cat $d/ro)"'
```

- Expect: `devinfo ro=0`, `disk ro=0`, every sibling `1`; then `devinfo ro=1`.
- Pass: both lines. **Stop:** a sibling at 0, or `devinfo` still 0 at the end (set it with `blockdev --setro` by hand, then stop).
- Rollback: `blockdev --setro` on the `devinfo` partition (the trap does it).

A real mark under the new guard needs slot B unmarked, which only `flash` or `--set-active=b` does; it is not part of this runbook. Its first occasion (the next `flash` of the 7 Pro) checks `journalctl -b -u omamobile-boot-success` for `slot b marked successful`.

### After the merge

Restage the boot files for every device (`tools/stage-boot-files`) and release their device packages, so each phone's next boot image carries the new guard; and install device-cheetah, raven and lynx's new markers with or before them. Then #483 rebases onto it, its window `devinfo` alone.

## 3. Results

None yet.
