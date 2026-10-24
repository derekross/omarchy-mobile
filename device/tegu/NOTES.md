<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a (tegu): first light

2026-10-22: verified on one retail Pixel 9a, Tensor G4 (`zumapro`).
This is an experimental integration, not a supported release or installer
qualification. Kernel, image-tool and package changes need separate PRs.
The descriptor here intentionally fails closed with current public tools.

Tested kernel: `7.3.0-rc6-omamobile-tegu-tn3-g1cb4bd36f3be-dirty`, private
branch `omamobile-tegu-touch-power`, worktree/output `wt-touch-power` /
`out-touch-power`. Diagnostic Images are additionally distinguished by
hash/build ID; this dirty release is not a published kernel package.
`[V]` marks verified observations; `[I]` marks an inference still to test.
Raw captures, recordings, backups and vendor files remain off repository.

## Local curated candidate, 2026-10-24

[V] A later candidate, `7.3.0-rc6-omamobile-tegu-g7e457a96fc45`, reaches
native Arch on internal userdata and starts Panthor, the G715 Omarchy
session and the read-only fuel gauge locally. The test sends no host GO,
driver load or confirmation before the recorded local startup completes.
Matching modules, storage guard, watchdog and protected-partition/image
checks pass. Physical gestures and unplugged cold boot were not requalified
by this test. The staged startup policy remains; this is not an installable public
kernel or device-package release.

[V] The same Image with board source `79288b2a3574` also registers the
ALIVE GPIO provider and native gpio-keys while preserving inherited pulls.
Input keycodes, IRQ ownership and shell bindings pass metadata/state checks;
physical presses, display wake and suspend remain unqualified. A later
boot removes both temporary reboot helpers. Ordinary `systemctl reboot`
with no reason returns to the native desktop automatically; explicit
bootloader reboot reaches Fastboot and the verified five-B image cycle
returns to the same native profile. Fresh root, protected-data and image
checks pass after each. Unplugged cold boot and production packaging remain
open; these results do not qualify those gates.

The selected subsystem source and disabled board resources are being
curated for separate kernel reviews in [tracking #28](https://github.com/derekross/omarchy-mobile/issues/28).
Public main still lacks the complete board integration and install recipe.
Do not enable the staged descriptor or infer Wi-Fi, charging/thermal,
Bluetooth, haptics, sensors, audio, cameras or fingerprint support from this
local desktop result. Earlier prototype observations below remain attributed
to their original diagnostic kernel.

## Read-only gauge review: temperature deferred, 2026-10-24

[V] Kernel PR38 driver blob `1e113081a07f0fc629842b31e3fb86b4f7c4fcdf`
(`drivers/power/supply/max77779_battery.c`) excludes TEMP reporting. Google's GPL driver substitutes 22 C for firmware
revision 1 with subrevision below 15; this gate does not establish the
retail gauge firmware revision or a stock-temperature comparison.

The exact signed C source is compiled as an ARM64 W=1 module against the
running curated `7.3.0-rc6-omamobile-tegu-g7e457a96fc45` kernel. It uses
that integration's qualified USI6/HSI2C6 bus, not an installable public
kernel. The unchanged board node is:

```dts
fuel-gauge@36 {
    compatible = "maxim,max77779-fg";
    reg = <0x36>;
    shunt-resistor-micro-ohms = <2000>;
    status = "okay";
};
```

[V] Load by hand, read twice 31.11 seconds apart, unload and restore the
installed module all pass on one boot. Both snapshots report present,
Li-ion, MAX77779, status Unknown, 93%, voltage/average 4.340390 V, charge
4720 mAh, full 5045 mAh and design 5120 mAh. TEMP is absent. Relevant
kernel lines, excluding the laptop log nonce:

```text
[  442.171460] max77779_battery: loading out-of-tree module taints kernel.
[  442.174098] max77779-battery 0-0036: Read-only fuel gauge; firmware model retained
[  473.361184] tegu-gauge-clean-review: two read-only snapshots complete; unloading test module
[  473.419985] max77779-battery 0-0036: Read-only fuel gauge; firmware model retained
[  473.432595] tegu-gauge-clean-review: installed gauge restored
```

[V] Laptop kmsg, PID1 hardware watchdog and independent recovery cover the
test. Fresh root/guard, six protected checksums and five B payloads pass;
both recovery timers are canceled and confirmed inactive on a fresh login.
An earlier attempt also read and restored the module, but host cleanup
failed on a collected timer, leaving the emergency reset armed. It fired;
the owner confirmed the recovered desktop and full checks passed before
this clean repeat. This was a test-controller failure, not a demonstrated
gauge fault. No model, NVM, charging, current-direction, rail or voltage
setting is written. The original driver remains installed; production
package migration, thermal control and suspend remain separate.

## Sources and firmware gate

- `R0/`: private retail capture `tegu-20261020-1349`, before unlocking:
  selected `getprop` fields and `fastboot-getvar-all.txt`, 2026-10-20.
- `R1/`: guarded native Linux partition enumeration and off-repository
  protected backups, `tegu-protected-20261021T021535Z`.
- `R2/`: 2026-10-22 guarded read-only AVB and slot-A image reads;
  `avbtool` signature checks and comparison with the verified official OTA.
- `F/`: the user's stock `tegu-bp3a.250905.014` factory boot images,
  including `dtbo.img`; facts below are offline parses, not installed-build
  attestations. The later bring-up bundle is a different artifact.
- `G/`: Google's GPL manifest branch
  [`android-gs-tegu-6.1-android16`](https://android.googlesource.com/kernel/manifest/+/refs/heads/android-gs-tegu-6.1-android16),
  manifest revision `893fbfd2192bc1c4a921f5daf23ea8543c09670d`.
- `P/`: the prototype's private kernel, guarded captures and per-gate
  results; the kernel release is above. No raw captures or binaries ship here.

### Slot history and official OTA maintenance

| Slot | Observed bootloader | Stock Android build evidence | Evidence |
| --- | --- | --- | --- |
| A | `tegu-16.3-13642544` | `BP3A.250905.014` (Android 16, patch 2025-09-05) | R0/getprop: `_a`, `ro.bootloader`, `ro.build.id` |
| B | `tegu-16.0-13541477` | `BP2A.250805.005`, patch 2025-08-05, in signed AVB metadata; no successful stock-B boot attestation | P/ resident-B fastboot controls; R2/vbmeta_b and vbmeta_system_b |

[V] The numeric loader build identifiers are 13642544 and 13541477.
A factory archive or the firmware suffix does not establish B's Android
build ID. R2 instead identifies it from valid signatures on vbmeta_b and
vbmeta_system_b, whose keys match the official stock images. This verifies
those metadata declarations, not our modified B boot images, dynamic
snapshot contents or a successful stock-B boot. The slot mismatch should have stopped bring-up under
CONTRIBUTING §3.1. The prototype result does not waive that rule or show
that a zumapro-specific HCRX workaround is needed.

[V] On 2026-10-22 the official full OTA for `BP3A.250905.014` was
sideloaded through stock recovery twice; both passes completed with status
0. After the first pass the resident B loader reported
`tegu-16.3-13642544`; after the second, resident A reported the same
version. Stock A then booted successfully. Ordinary authorised ADB
confirmed `_a`, `BP3A.250905.014`, Android 16, patch `2025-09-05`,
`tegu-16.3-13642544` and `dtbo_idx=9`. This is not a stock-B boot
attestation. Live DT selector reads were unavailable without rooting;
artifact-derived selectors remain distinct from observed silicon.

[V] Guarded post-OTA readback verifies valid top-level and system AVB
signatures on both slots, flags 0, and declared image prefixes exactly
matching the official BP3A images. Fresh protected backups were taken
before peripheral startup. The first ordinary installed-B control boot
reached internal Arch/systemd root with normal HCRX initialization, KVM
enabled and CPU0-7 online, without a laptop RAM boot. A bounded real ARM64
KVM guest executed and trapped the expected virtual MMIO write of 42;
no host-device passthrough was used. Native guard and watchdog checks
passed, with no runtime kernel fault detected. Control GNU build ID:
`bd787a42658c58ed023e7bb6c203d46844e294b9` (same diagnostic release string).

This control needs no HCRX workaround. The earlier failure is specific to
the mismatched-firmware prototype evidence; it does not justify a
zumapro-wide kernel workaround. Two normal control boots have passed;
cold starts and desktop/peripheral requalification remain separate gates.
[BRINGUP-M1](BRINGUP-M1.md) records those gates; the workaround is not
proposed for upstream.

### Sanitised stock facts

[V] R0/getvar: `product:tegu`, `hw-revision:MP1.0`,
`secure-boot:PRODUCTION`, `current-slot:a`,
`version-bootloader:tegu-16.3-13642544`. This was a **pre-unlock** snapshot:
`unlocked:no`; both slots reported successful with retry count 2, A
unbootable=no and B unbootable=yes. These are historical values, not the
prototype's current flags. A single resident-loader version is not proof
of equal firmware on both slots.

[V] Each slot has `boot`, `vendor_boot`, `vendor_kernel_boot` at 64 MiB,
`init_boot` at 8 MiB and `dtbo` at 16 MiB; `devinfo` is 8192 bytes
(R0/getvar). R1 enumerates 62 named partitions across four LUNs, sda–sdd:

- Five slotted boot images: `boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, `dtbo`.
- Other slotted names: `bl1`, `ldfw`, `dpm`, `gcf`, `pbl`, `bl2`,
  `dram_train`, `abl`, `bl31`, `tzsw`, `gsa`, `gsa_bl1`, `vbmeta`,
  `vbmeta_system`, `vbmeta_vendor`, `pvmfw`, `modem`.
- Unslotted: `persist`, `metadata`, `fips`, `ufs_internal`, `klog`,
  `misc`, `super`, `userdata`, `frp`, `efs`, `efs_backup`,
  `modem_userdata`, `trusty_persist`, `trusty_userdata`, `devinfo`,
  `pinfo`, `blenv`, `mfg_data`.

Only the five B boot images and userdata are writable under the guard;
listing a partition here grants no write permission.

[V] F/dtbo has **10 entries**. Retail Android reported `dtbo_idx=9`
(R0/getprop); entry 9 has board ID `0x60b06`, revision `0x10000`.
The stock vendor-kernel boot base-DTB candidates carry these
`/soc_compatible` tuples (product_id, major, minor, pkg_mode):

| Base DTB | Candidates |
| --- | --- |
| 0, A0 FOPLP | `(0x9875, 0, 0, 0)` |
| 1, A0 IPOP | `(0x9875, 0, 0, 1)` |
| 2, A0/A1 FOPLP | `(0x9875, 0, 0, 0)`, `(0x9875, 0, 1, 0)` |
| 3, A0/A1 IPOP | `(0x9875, 0, 0, 1)`, `(0x9875, 0, 1, 1)` |

The prototype's IPOP pair matches base 3. This does not distinguish this
unit's A0 versus A1 silicon, nor replace an equalised-stock live-DT capture.
The descriptor keeps that pair **commented out**, using #27's syntax:
`a0-ipop:0x9875:0:0:1 a1-ipop:0x9875:0:1:1`. This device PR supplies
selector data only. Shared SOC_COMPATIBLE tooling and its images-layout
tests remain in the separate tooling PR, alongside zuma's requirements.
Both SOC_IDS and SOC_COMPATIBLE stay unset, so this descriptor remains
refused even when #27 accepts either selector. Activation belongs with the
public DTB and required AVB footer values in a later PR.

**Header values verified:** the descriptor uses OS_VERSION=16.0.0 and
OS_PATCH_LEVEL=2025-09 from this stock build’s init_boot header.
The full OTA for BP3A.250905.014 (matching captured A) is downloaded and
matches Google's published SHA-256. All five F/ stock boot-image sizes and
digests match its payload manifest. AOSP unpack_bootimg parses that stock
init_boot as Android 16.0.0 / patch 2025-09. These are verified candidate
header values, now backed by both OTA completions, both-slot signed AVB
metadata for BP3A and the successful stock-A build-property check. A
stock-B Android boot is not claimed.

## Verified before firmware equalisation (old B, HCRX bypass, KVM off)

| Area | Observation [V] |
| --- | --- |
| Boot | Ordinary installed B boot and subsequent phone-initiated Linux-to-Linux reboot; no laptop kernel download, module load, storage-enable approval token (the bring-up script called it `GO`) or root confirmation. Tests kept USB connected. |
| Root and CPUs | Arch on internal ext4 userdata, systemd/SDDM/UWSM/logind, CPU0-7 online. KVM disabled. |
| Protection | Whole main-LUN node absent; only five B boot partitions and userdata writable; protected partitions read-only; per-boot guard and watchdog checks pass. |
| USB | NCM, ACM and root SSH over the connected cable. |
| Display | Bootloader framebuffer through simpledrm, 1080x2424, scale 2. Reported 60 Hz is not an independently measured panel rate. |
| Touch | Synaptics S3908 TouchComm v1: taps, long press, launcher, quick settings and all four swipe directions physically exercised by the owner. |
| GPU | Mali-G715 MC7: Panthor initialization, system Mesa GLES3.1 color readback, actual Hyprland/shell GPU rendering and automatic startup after local reboot. |

[V] Touch/GPU startup uses local prototype policy with matching pinned
modules, hang markers and timed recovery. No public tegu release package
provides it yet. The matrix remains **WIP** until the kernel and prerequisites are public.

[V] Horizontal swipes remain clunky and the clock card briefly shows a
jagged tail. Native display KMS, brightness, DPMS and GPU DVFS are not
qualified. Shader/top rates inherited from firmware are approximately
150/160 MHz, derived from qualified clock registers. A separate small
quick-settings first-frame flash was removed by selecting its screen
before showing the window, confirmed in recordings and physical swipes.

[V] Moving G4 UFS clock-stop register programming before host-clock disable
resolved a shutdown stall. The retained trace now completes both callbacks
and reaches `Restarting system`. An ordinary reboot without the extra
logging returns the native root/touch/GPU desktop: USB disconnects in
3.7 seconds and Linux USB returns in 28.9, versus 85/111 before the fix.
The prototype still has a 45-second storage qualification delay. Cold
power-on, unplug/replug, buttons, battery/charging/thermal policy, suspend
and the other phone peripherals are not qualified.

### Exact private restoration path

The post-OTA restore used a private checkout at
`/tmp/tegu-maintenance-tools`, based on this repository's main plus the
proposed #27 selector support and the previously qualified development
`flash` function. This was not the unchanged public `bin/omamobile`.
The command was `bin/omamobile flash --no-reboot --rootfs <verified-image>
--rootfs-sha256 <verified-sha256>`, with DEVICE=tegu and the pinned image
output selected. The regular ext4 image was 32 GiB, labelled
`omamobile-root`, reconstructed from the verified Linux file backup with
matching modules and checked ownership, ACLs, xattrs and special files.
It was flashed to shared `userdata`; no Android partition was mounted
read-write and no main-LUN device was recreated.

The retained flash log names exactly `boot_b`, `init_boot_b`,
`vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`, plus `userdata`.
The private flash function did **not** pass an explicit `-s <serial>`;
it relied on the connected-device/product check. I cannot confirm serial
binding for those historical writes. Future Fastboot operations will use
an explicit serial selection. No additional flash is needed to correct
this record. Slot selection and boot were separately performed by ABL's
Fastboot commands, not by a devinfo set-active write.

## Bring-up findings and descriptor facts

- [V] Initial malformed embedded AVB metadata failed before handoff.
  Stock-style child boot metadata passed an offline six-image load check;
  that repair alone did not resolve the older-firmware entry failure.
- [V] Entry recorders localized the older B firmware's failure to
  HCRX_EL2 access. Omitting that access permitted full Linux with all eight
  CPUs and KVM disabled. [I] Missing permission in the older firmware is
  the leading explanation; EL3's control register was not read. The
  completed equalised-firmware control passes normal HCRX and a real KVM
  guest, so the old bypass is not proposed for kernel review.
- [V] Both touch rails were off at handoff. The qualified ACPM/S2MPG14
  path, LDO4M/LDO25M and AVDD-before-VDD sequencing enabled v1 identification
  and the existing S3908 driver; this did not need a v2 protocol port.
- [V] G715 startup needed Google's GPL ASN/L2 hash values through Panthor's
  existing SoC-data mechanism (source below), plus the full upstream Mesa architecture 11
  backports. Tested system Mesa: `1:26.2.4-1.4`. No GPU protection-permission
  change was used.
- [V] Prototype container metadata: Android v4, five boot images,
  2048-byte vendor page size. Android 16 / 2025-09 are historical bring-up
  bundle header values only, not descriptor evidence. Retail
  MP1.0 board dtbo entry 9 selects ID `0x60b06`, revision `0x10000`.
  These are board values, not per-phone IDs.
- [V] Base-DTB selection uses soc_compatible, not the public packer's
  soc_id rewrite path. SOC_IDS is deliberately absent. The shared init is
  retained; no gs201 display probe or trigger write is requested.

The unit began with different slot firmware versions. Recorded prototype
image writes targeted B; no stock-firmware update or downgrade is recorded
in those tests. This does not establish that A was factory-identical.

[V] Before the OTA, R2 found A's vbmeta flags at 3, versus factory 0. In the declared
factory image prefix, only byte 123 differs. That captured header signature
did not verify as-is; resetting that byte in an **offline copy** exactly
matches the official factory image. No such change was written to the
phone during this audit; the history of the flag change is not established.
At that audit, all five actual A boot images separately matched the official BP3A OTA's
stock images. A's vbmeta_system signature was valid and its declared image
matched the official OTA. The two subsequent official OTA passes restored
flags 0 on both slots; the post-OTA signature/build checks are recorded
above. This does not imply the custom B images are verified by stock AVB.

An earlier private bring-up note from 2026-10-20 records that
`fastboot oem disable-verity` and `fastboot oem disable-verification`
returned OKAY after unlocking. This is a historical note, not a retained
before/after vbmeta comparison; it does not establish which command
changed A's header flags. It must not be omitted from the account of the
earlier verification changes. No such command is part of this maintenance.

This observation does not override CONTRIBUTING section 3.1: another
mismatched unit must stop for maintainer guidance before flashing.
Protected backups were kept off repository and checked against live
read-only partitions.

### devinfo write disclosure and stop

[V] `omamobile-bootctl` **wrote devinfo** to mark slot B successful.
Its `dump` reported layout version **3.15**. A fresh full 8192-byte backup
was checked before the write; host simulation and live readback verified
that byte `0x35` alone changed by setting B's successful bit (`OR 0x02`).
The full 8192-byte comparison verified slot A and every other byte unchanged;
devinfo was restored read-only and the storage guard checked over a fresh
SSH connection. The generic boot-success service remains masked.
After that earlier write, `fastboot getvar slot-successful:b` returned
`yes`: ABL read the same successful bit the marker had set. The retained
Fastboot captures confirm this independently of the Linux parser.
This was evidence of the bounded operation; further writes were held
while the maintainer reviewed the paired layout evidence below. On
2026-10-22 the maintainer agreed **mark-successful for B only**, after a
fresh backup and checksum immediately before the write. No set-active
or other devinfo write is agreed. Keep the generic service masked.

### Read-only layout evidence after official OTA maintenance

[V] Layout remains 3.15. Guarded Linux dumps followed by graceful returns
to Fastboot give these matching requested ABL observations, without an
intervening marking, slot selection or flash:

| Record | Bytes 0x30–0x37 | A successful / unbootable / retry | B successful / unbootable / retry |
| --- | --- | --- | --- |
| First normal B boot | `02 1a 00 00 02 14 00 00` | yes / no / 2 | no / no / 2 |
| One further normal B boot | `02 1a 00 00 01 1c 00 00` | yes / no / 2 | no / no / 1 |

The intervening boot used ordinary fastboot reboot, with no set-active or
retry refresh. Byte 0x34 decreased by one; successful/unbootable stayed
clear for B. This was not the only change: 0x35 XOR 0x08 matches the parser's
fastboot_ok field, and two opaque header offsets also changed. Their
values remain private and uninterpreted. No direct devinfo write was made.
The two pairs and these additional changes were posted to the maintainer
for layout agreement. The maintainer subsequently confirmed the retry
and fastboot_ok decoding and approved only B mark-successful, subject to
the fresh backup and before/after checks described above.

### Approved B-success operation after layout review, 2026-10-22

The maintainer approved only `omamobile-bootctl mark-successful` for B in
[review 5622088453](https://github.com/derekross/omarchy-mobile/pull/24#pullrequestreview-5622088453).
A further ordinary B boot used explicit Fastboot serial selection and no
slot reselection, flash or retry refresh. On the guarded native root, a
fresh full devinfo backup was saved privately and its checksum matched
live storage immediately before the write. The unchanged existing tool
performed the operation under a proven laptop log, watchdog and timed
read-only restoration.

| Moment | Layout | Bytes 0x30–0x37 |
| --- | --- | --- |
| Fresh backup immediately before mark-successful | 3.15 | `02 1a 00 00 00 1c 00 00` |
| Immediately after mark-successful | 3.15 | `02 1a 00 00 00 1e 00 00` |

All 8192 bytes were compared: only byte 0x35 changed, setting bit 0x02;
slot A and every other byte stayed unchanged. The devinfo partition and
its parent were temporarily writable for that tool operation, then
restored read-only; all original sibling read-only flags and the storage
guard passed a fresh SSH check. The generic boot-success service remains
masked. No set-active or other devinfo write was performed.

After graceful return to Fastboot, explicit serial-bound
`fastboot getvar slot-successful:b` returned **yes** and
`slot-unbootable:b` returned **no**. A remained successful and bootable.
This confirms ABL reads the same successful bit the marker writes.

### GPL source of the G715 cache-hash data

[V] G/ [`kernel/devices/google/zuma`, revision
`42395e8adcb880aa336f0da6bb2a19ed53929c40`, dts/zuma-gpu.dtsi](https://android.googlesource.com/kernel/devices/google/zuma/+/42395e8adcb880aa336f0da6bb2a19ed53929c40/dts/zuma-gpu.dtsi)
supplies `l2-hash-values = <0x0036db6d 0x005b6db6 0>`.
[`kernel/devices/google/zumapro`, revision
`8831630eee2ad095b85ed452944e6353940966a5`, dts/zumapro-gpu.dtsi](https://android.googlesource.com/kernel/devices/google/zumapro/+/8831630eee2ad095b85ed452944e6353940966a5/dts/zumapro-gpu.dtsi)
includes that zuma GPU description. Both are from branch
`android-gs-tegu-6.1-android16`. The same manifest's
[`kernel/google-modules/gpu`, revision
`696fc0246c17ba4270c11f88ab742ad4040938de`](https://android.googlesource.com/kernel/google-modules/gpu/+/696fc0246c17ba4270c11f88ab742ad4040938de/)
contains the GPL kbase property reader and L2 programming sequence.
The separate Panthor submission should cite these immutable sources;
no vendor binaries or GPU-permission changes belong in it.

## Meaning of the bring-up terms

**Qualified** means one named gate passed its stated checks on the tested
prototype/kernel; it does not mean release support, independent replication
or that unrelated peripherals work. **GO** was a temporary script's explicit
operator approval token before enabling storage; it is not required for
ordinary installed boot and is not a waiver of the safety model.

## Submission gates and follow-ups

[V] Offline: images/initramfs/flash/push each refuse the descriptor for
missing SOC_IDS before mocked hardware tools are called or images written.
The empty overlay passes strict checkpatch and dtc, its ID/revision read
back correctly, and applying it leaves a synthetic base unchanged.
These are low-risk checks with no phone rollback; stop if tooling proceeds.

Next: kernel drivers/bindings/DTS in linux-omarchy-mobile, one subsystem per
branch, with strict checkpatch, W=1 and binding/DT validation; generic DTB
selection/packing and a qualified device package here. Each hardware gate
needs protected backups, fresh logs, watchdog/dead-man recovery, a stop
condition and a known-good B rollback. Preserve stock A and the storage
guard. This entry is not an installation or diagnostic-flashing runbook.

The gated retest and required evidence are in [BRINGUP-M1](BRINGUP-M1.md).
