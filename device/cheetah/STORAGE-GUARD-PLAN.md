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

After the guard's first pass, nothing is writable that wasn't before: the boot LUNs' partitions are read-only by their own flags instead of their disks'. A tool that must write one of them clears that partition's own flag alone. Inside the initramfs there is one narrow difference. The kernel creates a disk's node before it scans the disk's partitions, and each partition starts with its own flag clear. So a boot-LUN partition can be writable from its birth until the guard's next pass, about 0.2 s, where before the disk flag could cover it from birth. Nothing in the initramfs writes a boot-LUN partition, and `sda`'s partitions (`efs` and `persist` among them) have always had the same window. The hand-over check reads the live state before Arch starts.

**`omamobile-boot-success` changes with it** (device-cheetah 0.1.45, raven 0.1.33, lynx 0.2.3). The marker ran `blockdev --setrw` on the whole bootloader LUN (`/dev/sdd`), then on `devinfo`. Under the new guard `/dev/sdd` is gone, so that first call fails and the marker fails (`packages/omamobile-device-cheetah/test/boot-success` shows it against the old script). It runs at every boot but writes only when slot B isn't marked yet, so a marked phone wouldn't notice until the next `flash` or `--set-active=b`. The new marker reads the disk's own flag:
- clear (the new guard): it clears `devinfo`'s own flag alone and sets it again after;
- set (an initramfs from before this change): it opens the disk and `devinfo` as it always did, so a fastboot rollback to an older image set still gets slot B marked.

The new marker carries the line `# guard: partition flags (#252)`. On a phone whose device package ships the marker (cheetah, raven, lynx), `bin/omamobile push` reads `/usr/bin/omamobile-boot-success` over SSH and refuses images with the new guard unless that line is there. `flash` can't read the phone, so for those phones it refuses images with the new guard unless `OMAMOBILE_MARKER_CHECKED=1` says the owner checked. A warning would scroll by, and a wrong marker shows only three boots later, as a fallback to slot A. Images whose initramfs reads as the old guard skip the check; an initramfs that is missing or can't be read doesn't.

`bin/omamobile push`, `omamobile-boot-update`, `tools/nv-backup`, `tools/phone-provision`, `omamobile-fp` and `tools/phone-smoke` work on partitions found by `PARTNAME` (and `push` and `boot-update` on `sda` alone) and never open a whole-disk node; none changes.

## 2. Runbook

Read-only steps first. Each step: commands, Expect, Pass, **Stop**, Rollback, risk. Laptop steps run in this branch's worktree; phone steps over `tools/phone-ssh` (root). Record results in §4 with the date and `uname -r`. Announce to Derek before every step marked "affects the phone".

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

- Expect: `push` reads the 0.1.45 marker and goes on (a refusal naming the marker means P1 didn't take: stop); five `_b` writes, each verified; the phone reboots into the same `uname -r` within about a minute.
- **Stop:** the phone doesn't come back over USB in 3 minutes, or stays in the initramfs (`ssh` answers but `/proc/1/comm` is not `systemd`): read `dmesg | grep ufs-ro` from the initramfs shell first, then roll back.
- Rollback: `cp $KG/images/*.img $OUT/images/ && KERNEL_OUT=$OUT bin/omamobile push`. If nothing answers: Power held about 30 s, then Volume Down + Power about 20 s for fastboot, and `OMAMOBILE_MARKER_CHECKED=1 KERNEL_OUT=$KG bin/omamobile flash`. `$KG` holds no initramfs file, so `flash` can't tell which guard its images carry and asks for the override; P1 installed 0.1.45. The flash clears slot B's mark, the old initramfs's guard sets the disk flag, and the 0.1.45 marker's old-guard path marks B again at that boot.

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

Clears `devinfo`'s own flag for a moment, as the marker does at a boot with slot B unmarked, and sets it again. Nothing is written. Derek's call. A detached timer sets the flag again after 30 s even if the SSH session drops before its trap runs.

```sh
tools/phone-ssh 'set -e; d=$(grep -lx PARTNAME=devinfo /sys/block/sd*/sd*/uevent); d=${d%/uevent}; p=${d##*/}; k=$(basename ${d%/*})
  systemd-run --unit=x-devinfo-relock --on-active=30 /usr/bin/blockdev --setro /dev/$p
  trap "blockdev --setro /dev/$p" EXIT
  blockdev --setrw /dev/$p
  echo "devinfo $p ro=$(cat $d/ro); disk $k ro=$(cat /sys/block/$k/ro); siblings read-only: $(for s in /sys/block/$k/$k*; do [ $s = $d ] || cat $s/ro; done | tr -d "\n")"
  blockdev --setro /dev/$p; echo "devinfo ro=$(cat $d/ro)"
  systemctl stop x-devinfo-relock.timer'
```

- Expect: `devinfo ro=0`, `disk ro=0`, every sibling `1`; then `devinfo ro=1`.
- Pass: both lines. **Stop:** a sibling at 0, or `devinfo` still 0 at the end (set it with `blockdev --setro` by hand, then stop).
- Rollback: `blockdev --setro` on the `devinfo` partition (the trap does it, and the timer 30 s later if the session dropped).

### R5. The marker's new write path: a real mark under the new guard (affects the phone: fastboot, flash, reboot; slot B unmarked until the marker runs; risk medium)

R3 only sees `slot b already marked successful`, which is the early exit and unchanged code. This step unmarks slot B on purpose, so the new branch (clear `devinfo`'s own flag, check it, write, set it again) runs once on the phone. Otherwise its first real run would come during a recovery `flash`. It is attended and Derek's call. Announce the reboot into fastboot, the flash and the boot. From the flash until the marker runs, every boot spends one of slot B's three tries: count the boots.

```sh
# 1. A read-only copy of devinfo, off the repository (never commit it), and its slot bytes now
d=$(tools/phone-ssh 'd=$(grep -lx PARTNAME=devinfo /sys/block/sd*/sd*/uevent); d=${d%/uevent}; echo ${d##*/}')
tools/phone-ssh "cat /dev/$d" > ~/android/reference/cheetah-devinfo-r5-before.img
tools/phone-ssh "sha256sum < /dev/$d"; sha256sum < ~/android/reference/cheetah-devinfo-r5-before.img
tools/phone-ssh "omamobile-bootctl dump /dev/$d" | sed -n '/^slot b /,/retry-count/p'
# 2. Fastboot, then flash the images R3 just checked (the new initramfs; P1's 0.1.45 marker is installed)
tools/phone-ssh 'reboot-to bootloader'      # or: bin/omamobile fastboot
fastboot getvar slot-successful:b 2>&1 | head -1
OMAMOBILE_MARKER_CHECKED=1 KERNEL_OUT=$OUT bin/omamobile flash
# 3. After the boot (flash waits for SSH)
tools/phone-ssh "journalctl -b -u omamobile-boot-success --no-pager | tail -3
  omamobile-bootctl dump /dev/$d | sed -n '/^slot b /,/retry-count/p'
  cat > /tmp/devinfo-r5-after.img < /dev/$d"
tools/phone-ssh 'cat /tmp/devinfo-r5-after.img' > ~/android/reference/cheetah-devinfo-r5-after.img
cmp -l ~/android/reference/cheetah-devinfo-r5-before.img ~/android/reference/cheetah-devinfo-r5-after.img
```

Then R3's commands again.

- Expect:
  - step 1: the two checksums are equal, and slot b reads `successful:  yes`;
  - step 2: `slot-successful:b: yes` before the flash; five flashes, `--set-active=b`, and SSH back within about 90 s;
  - step 3: the journal shows `slot b marked successful` (not `already marked`); slot b reads `successful:  yes` (record its retry count: it shows the tries this boot spent); `cmp -l` lists only offsets 49-56 (bytes 0x30-0x37, which `cmp` numbers from 1; the flash's `--set-active` and the mark both change only those);
  - R3 as before: every disk `disk-ro=0 node=gone`, only the six names writable.
- Pass: all of it.
- **Stop:** the marker failed or says anything else, slot b not `successful: yes`, or any R3 failure: count the boots since the flash and go to the rollback before the next reboot. A `cmp` difference outside 49-56 with slot b marked is ABL's or someone else's: stop, keep both copies and read them before anything else, but there is no try clock running.
- Rollback, in order, each within slot B's remaining tries:
  1. If the marker failed but the phone is up: read `journalctl -b -u omamobile-boot-success` and run `omamobile-boot-success` once by hand. That is the same write, so only if the log shows nothing new was tried (for example, a timing problem).
  2. `tools/phone-ssh 'reboot-to bootloader'`, then `OMAMOBILE_MARKER_CHECKED=1 KERNEL_OUT=$KG bin/omamobile flash`: the set with the old initramfs. Its guard sets the disk flag, and the 0.1.45 marker's old-guard path marks B at that boot (`slot b marked successful` in the journal).
  3. If that fails too: reinstall 0.1.44 from the previous checkout under the `$KG` images (the state before this PR) and run `omamobile-boot-success` by hand.
  4. At zero tries ABL boots stock on slot A. On the 7 Pro that is recoverable: on stock's recovery screen choose neither option, hold Volume Down + Power about 20 s for fastboot, flash `$KG`, and take a fresh read-only NV backup (AGENTS §4).

## 3. Merging this

- **Versions:** device-cheetah 0.1.45 is also claimed by #423 and #403, and device-lynx 0.2.3 by #438. Whichever merges later takes the next free version at merge, and the squash title is written from the `version` files then. raven 0.1.33 is free.
- **Order:**
  1. The 7 Pro run above passes.
  2. The device packages are published to the development channel, with their new markers: device-cheetah, device-raven and device-lynx.
  3. The raven and lynx owners get the notice below.
  4. Only then does the init change reach `main`. `push` and `flash` built from `main` check the marker from then on.
- **Notice to the raven and lynx owners** (raven: robotosaith; lynx: cx3301J, FlorencioJP, latentoperator): before your next `push` or `flash` from `main`, install the new device package (`tools/phone-install-package packages/omamobile-device-<codename>`, or `omarchy update` on the development channel). The new initramfs removes the boot LUN's whole-disk node, and the old `omamobile-boot-success` opens that node first. With the old marker, slot B is never marked after a `flash`, and ABL falls back to slot A after three boots. `push` now refuses in that state. If you have already flashed: install the package within B's remaining tries, then run `omamobile-boot-success` once by hand.
- **After the merge:** restage the boot files for every device (`tools/stage-boot-files`) and release their device packages, so each phone's next boot image carries the new guard. Then #483 rebases onto this, with its window `devinfo` alone. The 8 Pro owner offered on #252 to boot the guard on a Kioxia UFS 4.0 part, a second vendor and LUN layout: worth taking before #483.

## 4. Results

None yet.
