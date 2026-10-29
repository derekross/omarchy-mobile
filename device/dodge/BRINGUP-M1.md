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
proc (and optionally sysfs) only, **touches no disk**, and never opens a
block device. Stage 2 is the PR kernel `Image`, the dodge DTB (live memory
map from `$LIVE_DTB`, never committed), and the shared initramfs from
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
  triggers `sysrq c`. On this ABL a panic has historically returned the
  phone to fastboot / a reboot rather than quietly continuing into stock
  over Omarchy userdata; still confirm on the next smoke and record here.
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
| PR-tip chain smoke | `fastboot boot` of `bin/omamobile images` output (shared initramfs) | pending morning 2026-10-30 |

## 7. GPT bit-54 record (for §3.1)

**Shape:** by hand, once per install of slot B's boot image — never from a
service or at boot (AGENTS.md).

| Item | Value |
| --- | --- |
| LUN | **sde** (boot_a=sde12, boot_b=sde48); userdata on **sda** (sda15) |
| Sector size | 4096 logical |
| Partition entry / bit | GPT attribute **bit 54** on the `boot_b` entry |
| Four sectors | LBAs **1**, **2**, last−1, last on the LUN (primary header, primary entries, backup entries, backup header) — exact last LBA from morning dump |
| Rollback | `fastboot --set-active=a` only after a userdata wipe plan; keep off-phone GPT snapshots before any rewrite |
| Way back | stock on slot A; do not boot stock over Omarchy userdata |

### Slot flags from fastboot (2026-10-29 ~21:50 Europe/Copenhagen)

Phone in fastboot after a refused v2 `fastboot boot`; product `sun`,
unlocked, `current-slot: b`:

| var | a | b |
| --- | --- | --- |
| slot-successful | yes | yes |
| slot-unbootable | no | no |
| slot-retry-count | 6 | 6 |

### Morning-only read-only steps (do not write)

Still needed for the full §3.1 entry; all are read-only on a booted Omarchy
or from a saved GPT image:

1. Dump GPT headers + entry arrays on **sde** (and sda for completeness):
   `dd` of LBAs 1, 2, last−1, last; record sizes and CRCs before/after any
   future hand edit.
2. Record the `boot_b` partition entry bytes and confirm bit 54.
3. Re-read `fastboot getvar` slot-successful / unbootable / retry-count for
   both slots after the morning chain smoke (still read-only).
4. Note panic / `sysrq c` behaviour if the shared init ever takes that path.
