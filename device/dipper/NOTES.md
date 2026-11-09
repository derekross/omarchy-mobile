<!-- SPDX-License-Identifier: MIT -->
# dipper (Xiaomi Mi 8) — bring-up notes

Facts only, each read off the phone. Captures remain outside the repository
because they contain device identifiers and Wi-Fi keys; this file records only
the facts needed for review.

## 2026-11-09 — recovery, old-kernel observation and RAM-only image

The current `recovery` partition matches the `recovery.img` in the
checksum-verified 15-partition stock snapshot captured on 2026-10-29 at 19:01;
both have SHA-256
`7691a33e8b65d1ffcbf67b16fd4dc5c4c421420230f230db312512c73abc2221`. Its
Android boot header contains a gzip-compressed kernel that identifies as
`Linux version 4.9.337-perf-g0b3e38ef6c40`, not the 7.3 diagnostic kernel. This
confirms the current partition holds the stock recovery image. The order of the
snapshot and the two diagnostic writes remains unknown. `logdump` is not in the
15-partition backup. A separate live, file-level userdata archive was
verified off-device; it is not a raw partition image or an atomic snapshot,
and the filesystem remained mounted during the copy.

Before entering fastboot, the handset answered over USB SSH; no restart was
needed to restore SSH. Holding Power alone for 10 seconds restarted the phone
back into Android both from the installed system and under the Omarchy Mobile
RAM kernel. Volume Down + Power then entered fastboot. Read-only fastboot
variables reported product `dipper` and an unlocked bootloader.

An earlier read-only SSH observation, reported on 2026-11-09 at 08:53 UTC,
was on the dirty kernel
`7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty`. It reported `/dev/sda21`
mounted as the root filesystem read-write, with `/sys/block/sda/ro=0` and
`/sys/block/sda/sda21/ro=0`; the other partition `ro` values were `1`. Thus
`/dev/sda` existed and the whole main LUN was writable. The surviving record
does not say how that image was started, the device uptime at the check, or
whether its diagnostic init's `logdump` mirror was running. Do not boot that
old image again. Systemd reported failure to set the `qcom_wdt` timeout to one
minute, but the exact journal line was not retained and the feeder was not
checked. This old-kernel observation is not evidence for PR #505's image.

The PR #505 RAM image was built from kernel PR #220 head `b288f8e` after FTS5
PR #219 merged, then started with serial-pinned `fastboot boot`; no partition
was flashed. It reported `7.3.0-rc6-omamobile-push1`. The `boot.img` SHA-256 is
`e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e`, matching
its build manifest. The root is the initramfs (`rootfs`), not UFS. `simpledrm`
registered `/dev/fb0`; USB networking and SSH worked; and `qcom_wdt` was bound
with its userspace feeder running. The rescue exposed reboot modes `bootloader`
and `recovery`; running `/usr/local/bin/reboot-to bootloader` over SSH returned
the handset to fastboot without writing UFS.

`pm8941_pwrkey` and `pm8941_resin` registered. On the earlier final image, a
physical Volume Down press produced `KEY_VOLUMEDOWN` (code 114, value 1), and
Volume Up produced `KEY_VOLUMEUP` (code 115, value 1). The current kernel
image's button events have not yet been rechecked. The owner reported seeing
the console during the first boot.

The storage guard removed `/dev/sda`; its sysfs `ro` value remained `0` by
design. All 85 UFS partition `ro` values were `1`; the other UFS whole disks
were read-only. `/proc/iomem` reports `0x86200000–0x88efffff` as System RAM and
`0x88f00000–0x890fffff` as reserved, so the TZ range is not reserved in this
RAM boot's map. A separate EA8074 panel test used a RAM-only overlay on
2026-11-09 with kernel `7.3.0-rc6-omamobile-push1` and boot image SHA-256
`0f0ec9d62ebe57bef9ae8a4804bb23728f624daab824a0bf7dee18f63c2a3d59`. The panel
driver bound to `ae94000.dsi.0`, DRM reported `connected` at `1080x2248`, and
the owner confirmed the console was visible on the lit panel. All 85 partition
flags were `ro=1`; `/dev/sda` was absent, while `/dev/sdb` through `/dev/sdf`
remained present and had `ro=1` on this pre-#484 image. Backlight value 0 was
accepted and restored to 511 (maximum 1023). Framebuffer blanking changed
DRM `dpms` from `On` to `Off` and back to `On`. The FTS5 touch input still needs
a test on the current kernel. The panel log included a missing DSI `vdda`
supply (dummy regulator) and missing `a630_sqe.fw`; the display initialized,
but GPU rendering was not tested. The RAM image had no Arch root, and the probe
did not write UFS. The stock partition checksums were verified before boot.
After this session, a read-only backup of all 84 non-`userdata`, non-`super` GPT
partitions was captured from this guarded RAM boot. Each partition's source
SHA-256 and byte count were checked against the decompressed local copy, and
the compressed archive checksums were rechecked. The separate live userdata
archive remains file-level, non-atomic, and is not a raw partition backup.
The backup is stored outside the repository; it must not be published. This
completes the data-capture condition, but a reviewed button-by-button restore
procedure and supported single-slot writer are still required before a flash.

## 2026-10-29 — stock facts, read-only over SSH with the owner's Magisk root

- **SoC** SDM845. Live DT root: `model = "Xiaomi Technologies, Inc. Dipper new MP v2.1"`,
  `compatible = "qcom,sdm845-mtp", "qcom,sdm845", "qcom,mtp"`,
  `qcom,msm-id = <0x141 0x20001>`, `qcom,board-id = <0x37 0x00>`.
  6 GB RAM. `androidboot.cert=M1803E1A` (Mi 8 Global), `hwversion=3.13.0`.
- **Stock on the phone now** is a custom Android 14 (SDK 34) ROM with Magisk 30.7, not MIUI;
  its build fingerprint is a spoofed MIUI 8.1 string, and `ro.boot.verifiedbootstate=green`
  with `flash.locked=1` contradict the owner's unlocked bootloader. **No boot-state claim
  may be made from Android on this phone; read it in fastboot.** Running kernel 4.9.337.
- **Not A/B for the OS.** 92 entries under `/dev/block/by-name/`: a single `boot` (64 MiB),
  `recovery` (64 MiB), `dtbo` (8 MiB), `system`, `vendor`, `cache` and `userdata`
  (113 GiB). Only the bootloader chain is slotted: `xbl`, `xbl_config`, `abl`, `tz`, `hyp`,
  `aop`, `cmnlib`, `cmnlib64`, `devcfg`, `keymaster`, `qupfw`, `storsec`.
  **There is therefore no known-good OS slot to fall back to**, which the shared Pixel
  safety model assumes. A full stock backup is a precondition, not a nicety.
- **Boot image** is Android header v1, page size 4096, `second_size = 0`, and the kernel
  blob ends with **two concatenated FDTs of ~480 KB each** (`d00dfeed`, version 17): the
  base DTB is appended to the kernel and ABL selects one by msm-id/board-id. Hence
  `BOOT_METHOD=android-v1-appended-dtb`.
- **Display** Samsung **EA8074**, 1080x2248, command mode, 60 Hz, notch; physical
  68 x 142 mm. Confirmed twice: `msm_drm.dsi_display0=dsi_ss_ea8074_notch_fhd_cmd_display`
  on the kernel command line, and the live DT node `qcom,mdss_dsi_ss_notch_fhd_ea8074_cmd`
  (`qcom,mdss-dsi-panel-width = <0x438>`, `height = <0x8c8>`, `framerate = <0x3c>`).
- **Touch is STMicroelectronics, not FocalTech.** Live DT, on `i2c@a98000` (mainline
  `i2c14`): `fts@49 { compatible = "st,fts"; fts,irq-gpio = <&tlmm 31 ...>;
  fts,reset-gpio = <&tlmm 32 ...>; fts,default-fw-name = "st_fts_e1.ftb"; }`, with
  `fts,tp-vendor = <0x48>`. The running kernel's input device is `N: Name="fts"`.
  An `atmel,mxt-ts@4a` node exists as the alternate vendor and is not the active one.
  **Open:** mainline's ST driver is `st,stmfts` (`drivers/input/touchscreen/stmfts.c`),
  a different driver from Xiaomi's downstream `st_fts`; the current FTS5 driver
  has not been tested with Dipper's DTS node. No sibling board helps —
  polaris uses `syna,rmi4-i2c@20`, beryllium a FocalTech/Novatek part.
- **Audio** `sdm845-tavil-snd-card` (WCD9340). **Fingerprint** Goodix, capacitive
  (`fingerprint_goodix`, `uinput-goodix`); no mainline driver, out of scope.
  **Buttons** `qpnp_pon` plus `gpio-keys`.
- **UFS** host at `1d84000.ufshc`. Stock `system` is dm-verity over the `system` partition.

## 2026-10-29 — first light, and what the hardware said

**The phone reached a shell on an unpublished kernel tree.** `fastboot boot` of
the image used kernel release
`7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty` with its matching DTB: UFS up
(all six LUNs, ext4 mounts), USB NCM gadget, dropbear, gpio-keys, 8 CPUs and
5.7 GB RAM. This records the historical first-light tree; kernel PRs [#218](https://github.com/derekross/linux-omarchy-mobile/pull/218),
[#219](https://github.com/derekross/linux-omarchy-mobile/pull/219) and
[#220](https://github.com/derekross/linux-omarchy-mobile/pull/220) are later
successor changes and are not the code tested in that boot; FTS5 PR #219 is now
merged into linux-omarchy-mobile. The diagnostic image's guard allowed `userdata` and `logdump`
writes. A temporary init widened the allowlist to include `logdump` and used
`dd` to copy the kernel log there every two seconds during the 2026-10-29
diagnostic boot. The 2026-11-09 read-only check was on this dirty October
kernel; it found `/dev/sda21` as the read-write root and therefore `/dev/sda`
present and writable. The saved record does not establish whether the mirror
process was still running during that later check, nor the device uptime then.
Two diagnostic-image writes to stock `recovery` from rooted Android were also
made on 2026-10-29. The existing 15-partition backup did not include `logdump`;
an unverified `logdump.img` file is not evidence of a checked phone backup.
The current recovery SHA matches the verified 2026-10-29 19:01 snapshot
described above; the order of that snapshot and the two writes is unknown. The
2026-11-09 PR #505 RAM boot checked every UFS partition flag on the phone; it
did not mount or write UFS. The mount options and whether `persist` was mounted
during first light are not recorded here.

The recorded 15-partition snapshot before the radio runs was checksum-verified.
The 2026-10-30 comparison found `boot`, `recovery`, `dtbo`, `vbmeta`,
`fsc`, `devinfo`, `misc`, `logo`, `splash`, `persistbak`, `modemst2`
and `fsg` byte-identical; only `persist`, `modemst1` and `frp` changed.
All five NV partitions were read-only before and after the recorded runs. The
cause of the three differences is not established. Other recorded activity:
NFS-root Omarchy sessions on 2026-10-30, 2026-10-31 and 2026-11-02; modem
starts under `rmtfs -r`, followed by an XPU violation crash and remoteproc
recovery loops. The sequence of boots between the two snapshots (date, stock
Android or RAM image, and actions) has not been reconstructed, so the later
snapshot is not a baseline and the changes are not attributed to Android or
Omarchy. The current recovery image matches the 10-29 19:01 snapshot and its
kernel identifies as stock `4.9.337-perf-g0b3e38ef6c40`; the snapshot's order
relative to the two diagnostic writes remains unknown. The 10-29 first-light
boot is recorded as `fastboot boot` from RAM, not a recovery boot. The separate
08:53 old-kernel observation's launch method remains unknown; the surviving
record does not establish its source.

### What had to be fixed before any of that
Six defects in the recovered [sdm845-mainline MR !71](https://gitlab.com/sdm845-mainline/linux/-/merge_requests/71)
work, three of them fatal:

1. **`qcom,board-id = <69 0>` (0x45) is polaris's.** dipper reports `0x37`. ABL matches on
   it and silently refuses the whole boot image otherwise — no kernel output, no panic,
   just a reboot. Two blind diagnostic-image attempts were written to stock `recovery`
   from rooted Android before this mismatch was corrected.
2. `drm_panel_init()` no longer exists; the panel probe needed the refcounted
   `devm_drm_panel_alloc()`.
3. `panel-samsung-ea8074.ko` had no `MODULE_LICENSE()`, so modpost refused to link.
4. The touch node named `focaltech,ea8074` at `0x38`; the chip is ST at `0x49`.
5. Its Kconfig entry was copied from an SPI panel (`depends on SPI`, `select DRM_MIPI_DBI`)
   for what is a `mipi_dsi_driver`.
6. `ts_int_default` carried `bias-pull-down` from beryllium; dipper's own stock tree says
   `ts_active { pins = "gpio31", "gpio32"; drive-strength = <16>; bias-pull-up; }`.

### And two kernel-config lessons, both found on the hardware
Devices probe once, early. A driver that only appears later as a module never gets a
second chance — the device is left unbound and is not even on the deferred list. Proven
twice: the Qualcomm PHYs (so no USB and no storage: `dwc3: failed to initialize core`,
`sync_state() pending due to 88e8000.phy`), then i2c (`modprobe i2c-qcom-geni` bound to
nothing, and a hand-written `bind` failed). That is why every driver needed for first
light was built in (`=y`).

### Touch: first failed probe (historical)

The original FTS4-only driver bound and timed out. These observations describe that
kernel revision; they are not results from the current FTS5 driver:

- `i2c-14` and `i2c-5` come up; the touch device **exists as `14-0049`**, so the bus and
  address in the DTS are right.
- Both supplies are enabled and in use: `ldo28` at 2.856 V, `vreg_tp_vddio` at 1.8 V,
  one user each.
- `stmfts` binds and fails with **`-110`** from `wait_for_completion_timeout` — it sends
  its first command and never sees the reply interrupt.
- The interrupt pin bias was corrected to pull-up per the stock tree. **No change.**
- `i2cdetect` output is incoherent: in `-r` mode every even address reads as present and
  every register as `0x00`; in quick-write mode `0x49` is not detected at all, while
  `stmfts`'s own `i2c_smbus_write_byte` to `0x49` returns success.
- On i2c5 the driver logs **`geni_i2c_gpi_xfer:I2C timeout` / `GPI transfer failed: -110`**,
  so the GPI DMA path is not reliable here.
- GPI DMA cannot simply be turned off: this kernel's `geni_i2c` requires the channels and
  defers forever without them (`geni_i2c: Failed to get tx DMA ch`). There is no FIFO
  fallback to fall back to.

At the time, it was unknown whether GENI/GPI or the FTS5 protocol caused the timeout.

### FTS5: historical tap and published driver series

The live controller is FTS5. A separate historical RAM boot on 2026-10-30, using
the unpublished kernel release above, registered `stmfts` and a physical tap
produced `ABS_MT_POSITION_X`. That observation is not a test of the current
kernel PRs. The public successor series and its binding are in
[kernel PR #219](https://github.com/derekross/linux-omarchy-mobile/pull/219).
The upstream v8 cover letter states it was tested on Xiaomi Mi 8:
[FTS5 v8 cover letter](https://lists.openwall.net/linux-kernel/2026/09/25/2211),
[FTS5 driver patch](https://lists.openwall.net/linux-kernel/2026/09/25/2213),
[controller-ready fix](https://lists.openwall.net/linux-kernel/2026/09/25/2214),
[binding update](https://lists.openwall.net/linux-kernel/2026/09/25/2212).
Firmware loading, low-power touch and wake-on-touch/AP-SLPI handoff are not implemented.
