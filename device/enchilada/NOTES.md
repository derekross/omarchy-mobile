<!-- SPDX-License-Identifier: MIT -->
# OnePlus 6 (enchilada) bring-up notes

Findings from one retail OnePlus 6 (`ONEPLUS A6000`, `oneplus,enchilada`,
Qualcomm SDM845 / Snapdragon 845), newest first. Claim and discussion:
[#432](https://github.com/derekross/omarchy-mobile/issues/432). Captures
(`fastboot getvar all`, the partition map, command lines) stay off the
repository; facts from them are quoted here. Dates and times are US Eastern
(UTC−5).

Every entry says how the phone was booted (`fastboot boot` into RAM, or
the image on `boot_b`) and where its root was (the shared initramfs, or
the Arch root on `userdata`). Two builds of one kernel were used, both
Linux `7.1.0-rc1-sdm845` from the
[sdm845-mainline tree at tag `sdm845-7.1-rc1-r0`][sdm845-tag]
(`85f1df2a4ec7`) with the qcom-sdm845 kernel configuration that tree is
distributed with, and the upstream `qcom/sdm845-oneplus-enchilada.dtb`:

- **the first-light kernel**: exactly that;
- **the netfilter kernel**: the same, plus the six netfilter matches in
  the 2026-11-05 firewall entry.

linux-omarchy-mobile, which carries the same upstream DTS, has not been
tried yet; it is next.

[sdm845-tag]: https://gitlab.com/sdm845-mainline/linux/-/tree/sdm845-7.1-rc1-r0

## Slots and what is on them (CONTRIBUTING.md §3.1)

**Slot A does not hold stock Android.** This is a §3.1 event, recorded
here as the maintainer asked on #432. Putting stock back on slot A is
outside the project ([the maintainer's decision on #432](https://github.com/derekross/omarchy-mobile/issues/432#issuecomment-6708103355)):
this tree only writes slot B and `userdata`, and never `vbmeta`. If it is done, it is the owner's own step, with
OnePlus's own images, and it is recorded on #432 (slot flags before
and after, what was flashed and from which image, then a fresh
read-only radio backup). The owner has decided not to restore it, so
slot A keeps the rescue. This port stays RAM-only (`fastboot boot`)
until the slot-B install and its CONTRIBUTING.md §3.1 entry are agreed.

| Where | What is there now | How it got there | Storage guard? |
| --- | --- | --- | --- |
| `boot_a`, `system_a` | a small Arch Linux ARM rescue root and its kernel | `fastboot flash boot_a` and `fastboot flash system_a`, 2026-11-04, after a third-party Android build had replaced stock OxygenOS | its own, not the shared init: see below |
| `boot_b` | a header-v0 boot image of this port, netfilter kernel; its command line has no `omamobile.initramfs`, so the shared init hands off to the Arch root on `userdata` | `fastboot flash boot_b`, 2026-11-04 (first-light kernel); again 2026-11-05 16:15 (netfilter kernel) | yes: the shared `initramfs/init`, which leaves `boot_b` read-only (LUN `sde`, see first light) |
| `dtbo_b` | erased | `fastboot erase dtbo_b`, 2026-11-04: the third-party build's downstream overlays would not apply to a mainline DTB | - |
| `vendor_a`, `vendor_b`, `odm_a`, `odm_b`, `system_b` | leftovers of the third-party Android build | that build's installer | - |
| `userdata` | an Arch root built by `bin/omamobile`, with packages added from the rescue (below) | `fastboot flash userdata`, 2026-11-04 | - |
| bootloader firmware (`xbl`, `abl`, `tz`, `modem`, ...) | OxygenOS firmware, identical on `_a` and `_b` | never written by this port | - |

**Writes made by hand.** Every write below was typed by hand, outside
`tools/install-phone` and `bin/omamobile` (whose installer path refuses
`android-v0`), and none will be repeated:

- `fastboot`: `flash boot_a` and `flash system_a` (the rescue),
  `erase dtbo_b`, `flash userdata`, `flash boot_b` twice, and
  `--set-active`, which writes the GPT slot flags, to move between A and B.
- From the rescue, into `userdata`: on the night of 2026-11-04 the
  image's first 24 KiB were rewritten and the partition's last 1 MiB
  zeroed, because a nested GPT left from the third-party build kept
  overwriting the flashed image's head; on 2026-11-05 linux-firmware
  (`whence`, `atheros`, `qcom`), the device package and a kernel module
  tree were installed into the Arch root, and ufw enabled there. On
  `system_a`, the rescue's own root, `systemd-pstore` was enabled.

All of it happened before the maintainer's reply on #432 except the last
three steps of 2026-11-05: that reply was posted at 16:13 (21:13 UTC),
and `flash boot_b` (netfilter kernel), `--set-active=a` and the package
install into `userdata` ran from 16:15 to about 16:20, before I had read
it. Since then the only commands sent to the phone have been the read-only
backup, one `fastboot boot` (2026-11-05 16:35), `getvar` and one rescue
boot to read the slot flags again (below). No
slot flag is written again until this phone has a per-device entry in
CONTRIBUTING.md.

**Slot flags** (read-only; `fastboot getvar all`, except the last row):

| Read | `current-slot` | A: successful / unbootable / retry-count | B: successful / unbootable / retry-count |
| --- | --- | --- | --- |
| 2026-11-04, before any write of this port | a | no / no / 6 | yes / no / 7 |
| 2026-11-07 | a | no / no / 5 | no / no / 7 |
| 2026-11-07, after one more rescue boot, read in the rescue from `sde`'s GPT attributes (`sfdisk --dump`) | a | no / no / 5 | no / no / 7 |

Between the two reads, B lost its successful mark (left by the third-party
build; `--set-active=b` clears it and nothing of this port marks a slot)
and A's retry count went from 6 to 5. Neither slot is marked unbootable.

Slot A is not marked successful, but a rescue boot does not spend one of
its tries here: after one more rescue boot A was still at 5 and B at 7
([#432](https://github.com/derekross/omarchy-mobile/issues/432#issuecomment-6716747930)). What took A from 6 to 5 between the first two reads is not
known. Neither slot is near 0.

**The slot-A rescue.** It is not the shared init and has no initramfs (an
empty ramdisk): the kernel mounts `system_a` from the `root=` that ABL
appends, and `system_a` is mounted read-write. Its own udev rule
(`60-rescue-ufs-guard`) sets `ro=1` on every UFS partition except four
allowed writable ones, `system_a`, `userdata`, `boot_b` and `dtbo_b`, and
makes read-only every disk holding none of them; it keeps the whole-disk
nodes. That protects against accidents only. It replaces nothing in this
tree and goes away if stock is restored.

**With no USB host**, a `fastboot boot` of the shared init gives up after
20 s and panics, and `panic=10` reboots the phone. ABL then starts the
active slot, A, which is the rescue.

## 2026-11-11: `sde`'s GPT, and what marking `boot_b` would reach

Groundwork for this phone's [CONTRIBUTING](../../CONTRIBUTING.md) §3.1
entry, which the maintainer writes. `tools/mark-slot-b` exists, but the
descriptor sets neither `UFS_RW_LUNS` nor `SLOT_B_MARK` yet, so it refuses
this phone. Nothing here has written to the phone.

**`sde`'s GPT**, read on 2026-11-09 from the slot-A rescue (`sfdisk --dump`
and the raw sectors of both copies, read-only):

- 4096-byte sectors, 786432 of them (last LBA 786431); 96 entries of 128
  bytes. The primary header is at LBA 1 with entries in LBA 2-4; the backup
  entries are in LBA 786427-786429, with its header at 786431.
- `boot_b` is `sde39`, entry 38, at byte 768 of LBA 3 and of LBA 786428. So
  setting its bit 54 changes LBA 1, 3, 786428 and 786431, not the
  first entry sector.
- Before any install its attributes read `0x003a000000000000`: priority 2,
  not active, 7 tries, not successful, not unbootable. The CRCs then were
  entries `0x0a9fe94a`, primary header `0xb62ccea8`, backup header
  `0x619c2dc8`. `set-active b` rewrites all three, so the tool checks the
  live values, not these.

**What `sde` holds** (`PARTNAME`, 72 partitions), so what a whole-disk node
for it reaches:

- for each slot, `_a` and `_b`: `aop`, `tz`, `hyp`, `modem`, `bluetooth`,
  `mdtpsecapp`, `mdtp`, `abl`, `dsp`, `keymaster`, `boot`, `cmnlib`,
  `cmnlib64`, `devcfg`, `qupfw`, `vendor`, `vbmeta`, `dtbo`, `storsec`,
  `LOGO`, `fw_4j1ed`, `fw_4u1ea`, `fw_ufs3` to `fw_ufs8`;
- unslotted: `minidump`, `aging`, `op1`, `sec`, `devinfo`, `dip`, `apdp`,
  `msadp`, `spunvm`, `splash`, `limits`, `toolsfv`, `logfs`, `sti`,
  `logdump`, `ImageFv`.

`xbl` and `xbl_config` are not on `sde`. Which LUN holds them has not been
read yet.

**If both GPT copies on `sde` became invalid**, the phone could not load
`abl` from either slot, because `abl_a` and `abl_b` are on `sde`. Then there
is no fastboot, no `fastboot boot` and no slot-A rescue. The buttons would
not help either. The only way in would be Qualcomm's emergency download mode
(EDL, USB `05c6:9008`), with a programmer that matches this phone, to write
back the two read-only copies. A copy of `sde`'s LBA 0-5 and 786426-786431
(both GPT copies whole) and its `sfdisk --dump` were taken read-only on
2026-11-09, and their SHA-256 matched the phone's. They are kept off the
repository because they hold the disk's GUIDs. `tools/mark-slot-b` writes
the primary pair and reads it back before it touches the backup pair, so a
valid copy exists at every moment. It saves the four old sectors on the
laptop first (`~/android/reference/enchilada/mark-slot-b-sde/`), so after a
cut cable the next run sees the half-written table and offers to finish the
write or put the old sectors back. The owner's acceptance on #432 has to
cover the EDL case in so many words before anything writes this table.

**The bit layout** is Qualcomm's ABL (`QcomModulePkg/Include/Library/PartitionTableUpdate.h`
in the `abl/tianocore/edk2` tree): `PART_ATT_PRIORITY_BIT` 48 (two bits),
`PART_ATT_ACTIVE_BIT` 50, `PART_ATT_MAX_RETRY_CNT_BIT` 51 (three bits),
`PART_ATT_SUCCESS_BIT` 54, `PART_ATT_UNBOOTABLE_BIT` 55. This phone's `abl`
is OnePlus's build of it, and bits 54 and 55 have never been seen set
here. Only `fastboot getvar slot-successful:b` reading `yes` after a write
would prove that bit 54 means "successful" to this bootloader.

## 2026-11-08: the LUN-aware guard, booted RAM-only

`fastboot boot` of an initramfs built from commit 2331a85 (the
`UFS_RW_LUNS` pull request, with `UFS_RW_LUNS=sde` in this descriptor),
the first-light kernel (`7.1.0-rc1-sdm845`); nothing written. From the
init's log and `/sys/block`:

- allowlist `boot_b userdata`; LUNs with allowlisted partitions `sda sde`;
- `/dev/sda` and `/dev/sde` removed;
- only `sda17` (`userdata`) and `sde39` (`boot_b`) writable; the other
  71 `sde` partitions `ro=1`;
- `sdb`, `sdc`, `sdd` and `sdf` read-only at the disk level;
- no UFS errors in the kernel log.

## 2026-11-05: complete backup

Taken from the slot-A rescue (`boot_a`, `system_a`), read-only. Every
partition by GPT label except `userdata` (this phone has no `super`),
both slots: 100 images, with `persist`, `modemst1`, `modemst2` and `fsg`
never mounted. The sha256 of each raw partition was taken on the phone
before the copy and checked again after transfer and after decompression;
99/100 match all three ways. The exception is `system_a`, which was the
running rescue root, so that copy is live; the image it was flashed from
is kept beside it. The backup is kept off the repository.

Every firmware partition is byte-identical between `_a` and `_b` (`xbl`,
`xbl_config`, `abl`, `aop`, `tz`, `hyp`, `devcfg`, `keymaster`,
`cmnlib`, `cmnlib64`, `qupfw`, `storsec`, `modem`, `dsp`, `bluetooth`,
`LOGO`), so the two slots' bootloader versions match.

## 2026-11-05: the firewall needs six netfilter matches

**Failure, booted from `boot_b`** (`--set-active=b`, first-light kernel,
root on `userdata`; 2026-11-04 and again 2026-11-05 15:41): the
first-light kernel configuration leaves out the xtables matches that
ufw's rules load through `nft_compat`. Without them `ufw-init` stops at
`before6.rules` (`-m rt`, `-m hl`) and `before.rules` (`-m limit`),
firstboot's "services and firewall" step never completes, and the
half-loaded ruleset blocks new SSH connections on `usb0`.

**Fix, booted with `fastboot boot`** (2026-11-05 16:35, the netfilter
kernel's `boot_b` image sent to RAM, slot A still active, root on
`userdata`; no `--set-active`): with the matches built as modules
(`NETFILTER_XT_MATCH_LIMIT`, `_HL`, `_STATE`, `_OWNER`, `_RECENT` and
`IP6_NF_MATCH_RT`), firstboot completed, `ufw status` was active with
`22/tcp on usb0 ALLOW IN` (IPv4 and IPv6), and fresh SSH sessions
worked. `kernel/configs/omamobile.config` already enables the same
matches, so linux-omarchy-mobile should not need this.

On the very first boot only, SSH on `usb0` was blocked for about 100 s:
`ufw.service` starts default-deny about 5 s into boot, and the `usb0`
rule arrives only when firstboot reaches its firewall step. Later boots
load the saved rule at once.

## 2026-11-05: Adreno 630 needs this phone's zap shader

Same boot as the firewall fix (`fastboot boot`, netfilter kernel, root on
`userdata`). With `linux-firmware-qcom`, `qcom/a630_sqe.fw` and
`qcom/a630_gmu.bin` load. The zap shader the DTB names,
`qcom/sdm845/OnePlus/enchilada/a630_zap.mbn`, is signed for this phone
and is not in linux-firmware, so `adreno_load_gpu` fails with `-2` and
the compositor cannot start. Like the modem's firmware, it has to come
from the phone's own partitions at install time and is never committed;
the modem/rmtfs plan will say how, before any radio step.

## 2026-11-04: RAM-only first light

A header-v0 boot image (first-light kernel, gzip `Image` with the DTB
appended, the shared `initramfs/init` with `omamobile.initramfs`), booted
with `fastboot boot`. It stayed in the initramfs, mounted nothing, and
wrote nothing.

- The USB gadget came up about 4 s after `fastboot boot`, and
  `ssh root@172.16.42.1` worked.
- The storage guard held: allowlist `boot_b userdata`, every `sd*`
  partition `ro=1` except `userdata` (`sda17`), `/dev/sda` removed,
  nothing mounted.
- **`boot_b` is on LUN `sde`, not `sda`.** The shared guard's `UFS_RW`
  only looks at `sda`, so `boot_b` and `dtbo_b` stay read-only (seen
  live). This is the same split as dodge. The guard can now open a second
  LUN (`UFS_RW_LUNS`, #530); enchilada's `UFS_RW_LUNS=sde` comes with the
  slot-B install, which gives `boot_b` on `sde` a writer.
- msm DRM came up (`fb0` is `msmdrmfb`).
- ABL appends `root=PARTUUID=<system_a> skip_initramfs ro init=/init` to
  the command line even on `fastboot boot`. The shared init runs as PID 1
  regardless, so it needs no change.

## Stock facts (2026-11-04, before the port)

- Model `ONEPLUS A6000`; fastboot `product` `sdm845`, `variant` `SDM UFS`;
  `slot-count` 2; `max-download-size` 805306368 (768 MiB).
  `FASTBOOT_PRODUCT=sdm845` is the SoC name, not the phone's: any SDM845
  phone may report it, so it never identifies this phone by itself.
- Bootloader unlocked, EDK2-based ABL; `qcom,msm-id` 0x141
  (`androidboot.platform_id=321`).
- Boot images: Android boot image header v0, page size 4096, gzip kernel
  with the DTB appended; no `vendor_boot`, no `init_boot`. The header
  offsets are in `device.conf`.
- UFS: `userdata` is `sda17` (fastboot reports it as f2fs); `boot_*`, `dtbo_*`
  and `vbmeta_*` are on LUN `sde`.
- Panel: Samsung `sofef00` command-mode DSI, 1080x2280.
