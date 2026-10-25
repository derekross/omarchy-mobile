<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge): first light and install record

Status (2026-10-29): boots native Arch / Omarchy on SM8750 from slot B's
`boot` partition. Companion kernel under review:
[linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115).
This document is the CONTRIBUTING §5 / §6 first-light **record** of how this
phone was installed. It is not a procedure for other owners: the guarded
inactive-slot installer and firmware-match helper are deferred to a later PR.

## 1. Sources

- **Kernel base:** `omamobile` on
  [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile).
- **Board series:** subsystem-split commits on `dodge/pr-kernel-v2`
  ([#115](https://github.com/derekross/linux-omarchy-mobile/pull/115)). Config
  profile: `gpu2` (`CONFIG_QCOM_IPA=m`, MSM DRM).
- **Device tree:** `arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`
  (`compatible = "oneplus,dodge", …`).
- **Userspace:** `device/dodge/` and `packages/omamobile-device-dodge` in this
  repository. Shared `initramfs/init` (storage guard + allowlist); no
  dodge-forked init. **Untested on this phone from this PR tip until a
  `tools/phone-smoke` report exists** (see §6).

## 2. Descriptor and boot image

[device.conf](device.conf): `BOOT_METHOD=qcom-abl`, `BOOT_IMAGES=boot`,
`UFS_RW="boot_b userdata"`, `OMAMOBILE_SLOT=b`, `COMPATIBLE="oneplus,dodge"`,
`FASTBOOT_PRODUCT=sun`. Omarchy runs on slot B; stock stays on slot A.

`userdata` is on LUN **sda** (`sda15`); `boot_b` is on LUN **sde** (`sde48`).
The shared init only opens allowlisted partitions when they sit on `sda`, so
`boot_b` stays read-only today — good for the guard, but day-2 `push` cannot
rewrite the kernel until a LUN-aware change (optional follow-up, not in the
smoke image). Logical block size is 4096 on both LUNs.

### Why the image is a two-stage chain

This phone's ABL:

1. **Refuses header v2** under `fastboot boot` (stays in fastboot).
2. **Starts header v4** but pairs the uploaded image with the flashed
   `init_boot` / `vendor_boot`: stock DTB from `vendor_boot`, and the
   uploaded boot ramdisk does not run.
3. The only RAM-only path to **our** DTB without flashing `vendor_boot` is
   a built-in `/omamobile/` init + `CONFIG_CMDLINE_FORCE
   rdinit=/omamobile/init`, packed as a kernel-only header v4 image, which
   then `kexec -c` into stage 2.

`bin/omamobile images` with `BOOT_METHOD=qcom-abl` builds that chain via
`tools/dodge-chain` / [chainload/](chainload/). Pixel descriptors are
unchanged.

**Stage 1** (`device/dodge/chainload/init`) runs as **PID 1**. It mounts
proc (and optionally sysfs) only and **never opens a block device**
(soft-check: if `/proc/mounts` lists a `/dev/sd*` mount, stage 1 holds and
resets instead of kexec). That is a userspace claim only: stage 1 boots the
full stage-2 kernel config on **stock's DTB**, so a mainline driver whose
compatible matches a stock node (for example UFS) may still probe before
kexec. Stage 2 is the PR kernel `Image`, the dodge DTB (live memory map
from `$LIVE_DTB`, never committed), and the shared initramfs from
`bin/omamobile initramfs`. Stage 2 carries the shared storage guard.

`bin/omamobile flash` **refuses** `BOOT_METHOD=qcom-abl` in this PR: a
fastboot `--set-active` on this ABL may clear the successful bit and refill
retries, undoing the GPT bit-54 mark that has no §3.1 entry yet. Owners
update with `push` only once that path can see `boot_b` (see LUN note
above). The installer PR can reopen flash with the rest.

## 3. How this phone was installed (record)

On 2026-10-28, from private branch `oneplus13-dodge`, OxygenOS family
CPH2653 16.0.10:

1. **Firmware match (ARB).** OxygenOS anti-rollback means booting a slot whose
   `xbl_config` / firmware is below the fuse floor can hard-brick. Before
   activating slot B, every A/B firmware pair was hashed; **27 differed**.
   A byte-exact A→B copy of abl/aop/…/xbl/modem/… was done with sha256
   read-back. Left untouched: vbmeta, qweslicstore, oplusstanvbk,
   modemst/fsg/fsc/persist/EFS/oplusdycnvbk/RPMB. A later helper RAM-boot
   reported RESULT=MATCH with no writes.
2. **Flash.** Omarchy `boot_b` and Arch on `userdata`; stock OTA `boot.img`
   left on `boot_a` only (not booted). `--set-active=b`, reboot.
3. **Boot-success (GPT bit 54).** Qualcomm ABL keeps the slot-successful flag
   in GPT attribute bit 54 of `boot_<slot>` (primary + backup, both CRCs).
   Without it, ABL burns a retry each boot, marks the slot unbootable, and
   falls back to slot A (stock over Omarchy userdata). On this phone the bit
   was set by hand after the first clean boot. Detail for Derek's §3.1 entry
   is in §7 below. A oneshot service is not shipped in this PR.

`version-bootloader` is empty on this ABL, so a Pixel-style BL string check
cannot substitute for the firmware match.

## 4. Modem (opt-in) and off-phone backups

Units under [modem/](modem/) stay inert unless
`/etc/omamobile/modem-probe.enable` exists. With the flag, each boot restores a
named good EFS *copy* under `/var/lib/omamobile/efs-good/` (read-only `dd` of
the phone's own partitions; never `-P` on the live partitions; never committed
to git). See [modem/README.md](modem/README.md).

Per CONTRIBUTING §3.3, before any modem session this phone also keeps
**off-phone**, read-only backups of `modemst1`, `modemst2`, `fsg`, `fsc`,
`persist`, and the oplus NV partitions, with a `SHA256SUMS` checked before
each session. Those backups are never in git.

## 5. Shared init assumptions (Pixel → dodge)

- Allowlisted partitions are writable only when they live on `sda`.
  `userdata` does (`sda15`); `boot_b` does not (`sde48`) — see §2.
- If `boot_arch` fails, the shared init waits ~45 s for a USB host then
  triggers `sysrq c`. **Panic behaviour on this ABL is still open:** stage 2
  carries `panic=10`, so the kernel resets after 10 s. With
  `slot-successful:b=yes` the expected path is a reboot back into slot B
  rather than falling back to A, but whether this ABL enters a dump mode
  first has not been confirmed with a deliberate `sysrq c` on a booted B.
  Do not treat "returns to fastboot" as verified until that test is run.
- Until a `tools/phone-smoke` report from images built by
  `bin/omamobile images` on this branch exists, treat the shared init path
  as **untested on dodge**.

## 6. Phone-smoke evidence

| Gate | Evidence | Result |
| --- | --- | --- |
| Firmware-match | sha256 of every `*_a`/`*_b` pair: **27 differed**. Byte-exact A→B copy (read-back verified). Left untouched: vbmeta, qweslicstore, oplusstanvbk, modemst/fsg/fsc/persist/EFS/oplusdycnvbk/RPMB | pass |
| Inactive-slot boot | Omarchy `boot_b` set active; stock OTA `boot.img` on `boot_a` only | pass |
| `version-bootloader` | empty on this ABL | noted |
| Boot-success | GPT bit 54 set by hand on `boot_b` after first clean boot | pass |
| PR-tip chain smoke (2026-10-30 ~07:46 Europe/Copenhagen) | RAM-only `fastboot boot` of chain image from this branch (no flash, no set_active). Stage-2 kernel was the private `7.3.0-rc6-dodge-gpu2` build (not the #115 head); package still `omamobile-device-dodge 20261016-1`. `tools/phone-smoke` overall **unknown**: required storage-guard/root/kernel-health/USB ok; display/GPU/touch/buttons/battery/sensors ok; required `boot` skip (forced cmdline, no slot suffix); required `session` not ok (Hyprland not up at ~40 s); sound cards none; Wi-Fi link down at that moment. A later #115-head RAM boot (~09:28) **hung** on the console (dual memory map; fixed in kernel DTS + stage2-dtb); re-smoke of the #115 tip pending slot-B recovery. | partial |

## 7. GPT bit-54 record (for §3.1)

**Shape:** by hand, once per install of slot B's boot image — never from a
service or at boot (§3.1).

| Item | Value |
| --- | --- |
| LUN | **sde** (boot_a=sde12, boot_b=sde48); userdata on **sda** (sda15) |
| Sector size | 4096 logical |
| Partition entry / bit | GPT attribute **bit 54** on the `boot_b` entry |
| Record size | At **4096-byte** logical sectors the GPT record is **8 sectors in 4 files**: primary header (LBA 1), primary entries (LBAs 2–4, 3 sectors), backup entries (LBAs 634875–634877, 3 sectors), backup header (LBA 634879). "Four sectors" would only be right at 512-byte sectors. |
| Rollback (corrupted GPT) | Off-phone restore of the 4 dump files onto the matching LBAs. sde also holds `abl`/`xbl`; if both primary and backup GPTs on sde are corrupt the phone is likely EDL-only. Whether this ABL accepts `fastboot flash partition:<lun>` has **not** been checked (read-only docs / getvar only — not tried). |
| Way back | `fastboot --set-active=a` then `fastboot -w` (wipes Omarchy `userdata`); do not boot stock A over Omarchy userdata without that wipe. |

### Morning read-only dump (2026-10-30 ~07:49 Europe/Copenhagen)

No GPT write this round. Bit 54 was already set on both `boot_a` and
`boot_b` (by hand on 2026-10-28, without a pre-write dump), so the numbers
below are the **current** state, not a before/after. The next by-hand write
must record both.

| Item | Value |
| --- | --- |
| logical sector size sde / sda | **4096** / 4096 |
| sde last LBA | 634879 |
| primary header LBA | 1 |
| primary entries LBA | 2 (96 × 128 B over 3 sectors) |
| backup entries LBA | 634875 (3 sectors) |
| backup header LBA | 634879 |
| primary header CRC32 | 0x04411e69 (matches calc) |
| backup header CRC32 | 0x15af848b (matches calc) |
| partition array CRC32 | **0x4950baae** (primary + backup match) |
| boot_a attrs / bit 54 | 0x0072000000000000 / **1** (priority 2, retry 6, successful) |
| boot_b attrs / bit 54 | 0x0077000000000000 / **1** (priority 3, active, retry 6, successful) |

Off-phone raw dumps (`sde-prim-hdr.bin`, `sde-bak-hdr.bin`,
`sde-prim-entries.bin`, `sde-bak-entries.bin`) stay on the desktop only —
never in the repo.

### Still open for §3.1

1. Deliberate panic / `sysrq c` on a booted slot B, then re-read fastboot
   slot-successful / unbootable / retry-count for both slots.
2. Concrete GPT restore path that avoids EDL if both copies on sde are bad
   (whether `fastboot flash partition:<lun>` works on this ABL).
