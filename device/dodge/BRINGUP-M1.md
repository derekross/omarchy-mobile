<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge): first light and install record

Status (2026-10-28): boots native Arch / Omarchy on SM8750 from slot B's
`boot` partition. Companion kernel under review:
[linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115).
This document is the CONTRIBUTING §5 / §6 first-light **record** of how this
phone was installed. It is not a procedure for other owners: the guarded
inactive-slot installer and firmware-match helper are deferred to a later PR.

## 1. Sources

- **Kernel base:** `omamobile` on
  [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile).
- **Board series:** subsystem-split commits on `dodge/pr-kernel-v1`
  ([#115](https://github.com/derekross/linux-omarchy-mobile/pull/115)). Config
  profile: `gpu2` (`CONFIG_QCOM_IPA=m`, MSM DRM).
- **Device tree:** `arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`
  (`compatible = "oneplus,dodge", …`).
- **Userspace:** `device/dodge/` and `packages/omamobile-device-dodge` in this
  repository. Shared `initramfs/init` (storage guard + allowlist); no
  dodge-forked init.

## 2. Descriptor

[device.conf](device.conf): `BOOT_METHOD=qcom-abl`, `BOOT_IMAGES=boot`,
`UFS_RW="boot_b userdata"`, `OMAMOBILE_SLOT=b`, `COMPATIBLE="oneplus,dodge"`,
`FASTBOOT_PRODUCT=sun`. Omarchy runs on slot B; stock stays on slot A.
`boot_b` is on LUN sde (sde48), so the shared init keeps it read-only today;
day-2 `push` cannot rewrite it until a LUN-aware change. The working boot
image on this phone is the header-v4 kexec chain-loader, not a plain
qcom-abl v2 pack from `omamobile images`.

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
   was set by hand after the first clean boot — LUN/sectors/bit/CRCs,
   before-after, and the rollback (`fastboot --set-active=a` only after a
   userdata wipe plan) are recorded under
   [NOTES](NOTES.md#2026-10-28-matrix-evidence). A oneshot service is not
   shipped in this PR; see the PR discussion for the Pixel-shaped alternative.

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

## 5. Phone-smoke evidence (2026-10-28 slot-B move)

| Gate | Evidence | Result |
| --- | --- | --- |
| Firmware-match | sha256 of every `*_a`/`*_b` pair: **27 differed**. Byte-exact A→B copy (read-back verified). Left untouched: vbmeta, qweslicstore, oplusstanvbk, modemst/fsg/fsc/persist/EFS/oplusdycnvbk/RPMB | pass |
| Inactive-slot boot | Omarchy `boot_b` set active; stock OTA `boot.img` on `boot_a` only | pass |
| `version-bootloader` | empty on this ABL | noted |
| Boot-success | GPT bit 54 set by hand on `boot_b` after first clean boot | pass |

A `tools/phone-smoke` report from one boot of the build this PR describes is a
follow-up (needs a phone boot of this curated tip).
