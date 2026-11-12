<!-- SPDX-License-Identifier: MIT -->
# dipper (Xiaomi Mi 8) — bring-up notes

Facts only, each read off the phone. Captures remain outside the repository
because they contain device identifiers and Wi-Fi keys; this file records only
the facts needed for review.

## RAM sessions (newest first)

| Date | `boot.img` SHA-256 | Source, as recorded | `/dev/sda` and UFS partitions | Checks and gaps |
| --- | --- | --- | --- | --- |
| 2026-11-11 | `665fcbd682cd8e64b3ffec1ff7f4ab9ca33a26b9b47b11073be7a3c267abf2b1` | #505 `2d67708e07728b13b5d2a9eda299ace8a1608163`; kernel/DTS #220 `26aa77c317cd029d16e58890c532562ca275c9f0` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | `uname -r` `7.3.0-rc6-omamobile-push1`; `qcom_wdt` bound and feeder running; simpledrm fb0, USB/SSH and reserved `0x85fc0000–0x8a8fffff` passed. Physical screen, keys, touch, GPU and Wi-Fi not tested. RAM boot only; no UFS write. |
| 2026-11-10 | `540b5d31ea73a31ade9a8d8cb5152cf701dc3c2ad8256734790b0ef2db6dbdd0` | Combined #503/#505; kernel/DTS #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | Watchdog/feeder, simpledrm, USB/SSH, reserved TZ range, pinned host key and `reboot-to bootloader` passed; physical keys not captured. |
| 2026-11-10 | `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7` | Rebased #503 NFS image with #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | `/dev/sda` present, set `ro=1`; six disks and all 85 partitions read back `ro=1` | `uname`, NFS root, multi-user systemd, watchdog and SSH passed; generic Arch test root only; link-loss recovery and Omarchy desktop untested. |
| 2026-11-10 | `0ee4f11d1973085c434e741a2e9dd73af5a9cd157296c25801ed5a92a6b9e9d9` | #505 `994944d7ecbacd69444221e6951153cb329a374e`; kernel/DTS #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | Watchdog/feeder, framebuffer, USB/SSH, reserved TZ range and `reboot-to` passed; physical keys not captured. |
| 2026-11-10 | `e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` | Older rescue image; exact source commit unknown; its init differs from the shared init | Node present, disk `ro=0`; all 85 partition flags recorded `ro=1`, including `sda21` | Kernel `7.3.0-rc6-omamobile-push1`, initramfs root; no `logdump` or whole-disk removal in init, so not the October diagnostic init. SSH host key verified but key was not authorized. No UFS write. |
| 2026-11-09 | `e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` | Image was reported booted; exact build/init source unknown | `/dev/sda` reported present with `ro=0`; partition details for this session unknown | The retained 08:53 capture is a dirty-kernel writable-root observation; whether it came from this exact image is unknown. |
| 2026-11-09 | `0f0ec9d62ebe57bef9ae8a4804bb23728f624daab824a0bf7dee18f63c2a3d59` | `linux-omarchy-mobile` panel test tree with EA8074 from #218; exact combined revision unknown | `/dev/sda` absent; all 85 partitions `ro=1`; `sdb`–`sdf` present, `ro=1` | Panel/DRM, backlight 0→511, DPMS off/on passed; `vdda` used a dummy regulator, GPU rendering and touch untested. |
| 2026-11-09 | Same boot as panel test, `0f0ec9d6…` | Same as panel test | Same as panel test | Full backup of 84 non-`userdata`, non-`super` GPT partitions was read from this guarded boot and every source hash/size verified; separate userdata archive was file-level and non-atomic. |
| 2026-11-09 | Unknown; exact image hash not retained | Omarchy Mobile RAM kernel; exact build unknown | Disk and partition flags not recorded | Power-only 10-second restart passed from Android and RAM kernel; no UFS write was attempted. |
| 2026-11-09 | `2244d74aea472b0c595b2056ad8618f614e6a9161b5b264c7f898939e626f318` | Initial NFS-root image reused the earlier #505 kernel and DTB | `/dev/sda` present and set `ro=1`; all six disks and 85 partitions logged `ro=1` | NFS root and SSH worked; systemd reported `RuntimeWatchdogUSec=20s`. Direct `uname`/sysfs reads were not captured. |
| 2026-11-09 | `f2f5cb2e3da8fe992d366dba36e059c0d9106cf14a7d1c8872c61ee144a4474b` | Earlier #505 image after `qcom-pon` was built in; exact kernel/DTS heads unknown | `/dev/sda` absent, disk `ro=0`; all 85 partitions and other disks `ro=1` | PMIC keys registered and Volume Down produced `KEY_VOLUMEDOWN`; watchdog/feeder, framebuffer and USB/SSH worked. |
| 2026-11-09 | `93484a91103c294f6c73799ae6cb7161019129b9f89ab331222ae04f10ecf3e1` | First #505 image before `qcom-pon` was built in; exact kernel/DTS heads unknown | `/dev/sda` absent, disk `ro=0`; all 85 partitions and other disks `ro=1` | Console, framebuffer, USB/SSH and watchdog/feeder worked; no physical key event was captured. |

The original 10-29 count of 92 `/dev/block/by-name/` entries was not saved as a
name list. The retained backup and kernel records cover 84 non-userdata GPT
partitions plus `userdata`; the other seven names cannot be identified from the
retained artifacts and remain unknown.

## 2026-11-11 — rebuilt #505 RAM image

Built and booted `boot.img` SHA-256
`665fcbd682cd8e64b3ffec1ff7f4ab9ca33a26b9b47b11073be7a3c267abf2b1` with
`fastboot boot` from #505 `2d67708e07728b13b5d2a9eda299ace8a1608163` and
kernel/DTS #220 `26aa77c317cd029d16e58890c532562ca275c9f0`. `uname -r` was
`7.3.0-rc6-omamobile-push1`. The `/dev/sda` whole-disk node was absent; its
sysfs flag remained `ro=0`. Nodes `/dev/sdb`–`/dev/sdf` were present with
`ro=1`; all 85 partition flags were `ro=1`, and `ufs-ro` logged the guard for
each. `qcom_wdt` was bound and the watchdog feeder was running. simpledrm
registered `fb0`; authenticated USB SSH worked. `/proc/iomem` reserved
`0x85fc0000–0x8a8fffff`, including the former TZ range. The physical screen,
keys, touch, GPU rendering and Wi-Fi were not tested in this run. Only
`fastboot boot` was used; no UFS partition was written.

## 2026-11-10 — final PR #505 RAM image

Booted image SHA-256 `0ee4f11d1973085c434e741a2e9dd73af5a9cd157296c25801ed5a92a6b9e9d9` with `fastboot boot`; it was built from PR #505 head `994944d7ecbacd69444221e6951153cb329a374e` and kernel/DTS PR #220 head `055a4019998f22cc0e2a8afef7650274a6ce0657` (touch PR #219 is merged). `uname -r` was `7.3.0-rc6-omamobile-push1`; `/` was the initramfs (`rootfs`). The guard reported the UFS devices read-only. Sysfs showed six disks: `sda` had `ro=0` but its whole-disk `/dev/sda` node was absent; `sdb`–`sdf` each had `ro=1` and present nodes. All 85 partitions had `ro=1`. This matches PR #505's intended missing-node case for `sda`; no UFS write was attempted.

`qcom_wdt` loaded and `/usr/bin/watchdog -t 5 -T 30 /dev/watchdog0` was running. simpledrm registered `fb0`; USB gadget and authenticated SSH worked. `/proc/iomem` marked `0x85fc0000–0x8a8fffff` reserved, covering the former TZ range. The final image's physical button events were not captured, so the earlier Volume Down/Up observations are not evidence for this kernel. The image's `reboot-to bootloader` helper successfully returned the phone to fastboot; fastboot reported product `dipper` and unlocked `yes`. The only boot operation was `fastboot boot`; no UFS partition was written.


## 2026-11-10 — rebased #503 and combined #505 RAM runs

The rebased PR #503 init was RAM-booted with PR #505's Dipper builder and
kernel/DTS PR #220 at `055a4019998f22cc0e2a8afef7650274a6ce0657`. NFS image
SHA-256: `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7`;
`uname -r` was `7.3.0-rc6-omamobile-push1`, and `/` was NFS. The initramfs
used BusyBox `mount`; the export was a generic Arch Linux ARM test root, not an
Omarchy rootfs. Direct sysfs reads returned `ro=1` for all six UFS disks and
all 85 partitions. The guard logged each read-back, including `/dev/sda` set
read-only for NFS. Systemd reached the multi-user target with
`RuntimeWatchdogUSec=1min`; SSH remained available. `reboot-to bootloader`
returned the phone to fastboot. No UFS write was attempted. The NFS link was
not deliberately dropped, so hard-mount link-loss recovery remains untested.

The combined #503/#505 non-NFS RAM image was also booted. SHA-256:
`540b5d31ea73a31ade9a8d8cb5152cf701dc3c2ad8256734790b0ef2db6dbdd0`.
`uname -r` was `7.3.0-rc6-omamobile-push1`; `/` was the initramfs (`rootfs`).
Direct sysfs reads returned `ro=1` for all 85 partitions and disks `sdb`–`sdf`;
`sda` remained `ro=0`, while the guard removed `/dev/sda`. The `qcom_wdt`
module and feeder ran, simpledrm registered `fb0`, USB/SSH worked, and the
former TZ range was reserved in `/proc/iomem`. The rescue SSH host key matched
the build output, and `reboot-to` returned the phone to fastboot. No UFS write
was attempted. Physical input events were not captured on this exact image.

## 2026-11-09/10 — recovery and historical RAM observations

The current `recovery` partition matches the `recovery.img` in the
checksum-verified 15-partition backup of the installed system captured on
2026-10-29 at 19:01;
both have SHA-256
`7691a33e8b65d1ffcbf67b16fd4dc5c4c421420230f230db312512c73abc2221`. Its
Android boot header contains a gzip-compressed kernel that identifies as
`Linux version 4.9.337-perf-g0b3e38ef6c40`, not the 7.3 diagnostic kernel. This
confirms the current partition holds the installed ROM's recovery image. The order of the
snapshot and the two diagnostic writes remains unknown. `logdump` is not in the
15-partition backup. A separate live, file-level userdata archive was
verified off-device; it is not a raw partition image or an atomic snapshot,
and the filesystem remained mounted during the copy.

The recovery image hash is recorded from the backup, but the backup's `boot.img`
was not present among the accessible artifacts for this review. Its kernel
string and whether it matches the recovery build remain unknown.

Before entering fastboot, the handset answered over USB SSH; no restart was
needed to restore SSH. Holding Power alone for 10 seconds restarted the phone
back into Android both from the installed system and under the Omarchy Mobile
RAM kernel. Volume Down + Power then entered fastboot. Read-only fastboot
variables reported product `dipper` and an unlocked bootloader.

A separate NFS-root attempt used a RAM-only image with SHA-256
`2244d74aea472b0c595b2056ad8618f614e6a9161b5b264c7f898939e626f318`, reusing
the earlier #505 kernel and DTB and repacking its initramfs with
`OMAMOBILE_NFSROOT`. The persistent NFS-root journal recorded NFS mode and
read-only confirmations for all 85 unique UFS partitions and all six UFS
disks; the guard reads each `ro` value back as `1` before logging success. SSH
confirmed `/` was NFS, PID 1 was systemd, and the system was running with
`RuntimeWatchdogUSec=20s`. The exported root was a generic Arch Linux ARM base,
not an Omarchy rootfs. No UFS write was attempted. Direct `uname -r` and
sysfs `ro` output were not captured, and this pre-#484 image does not verify
the post-#484 whole-disk-node absence check.

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

The image with SHA-256
`e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` was
previously described here as PR #505's RAM image. On 2026-11-10, I booted that
exact file again with `fastboot boot` and read it over the USB serial shell.
It reported `7.3.0-rc6-omamobile-push1`, but `/dev/sda` existed with
`/sys/block/sda/ro=0`; `/sys/block/sda/sda21/ro=1`. Its initramfs root was
`rootfs`; no UFS write was attempted. Offline extraction found init SHA-256
`ab6db476f5cd26cb84a8346e18da5b2137530091be504c47a23b0a21934277c5`, different
from the checked-in shared init. It contains neither the October `logdump`
mirror nor whole-disk-node removal, so it is not the October diagnostic init
and does not verify PR #505's guard. Do not treat it as #505's image or boot it
again. SSH host-key verification succeeded, but the configured key was not
authorized. The separate rescue image still provides authenticated SSH
and `reboot-to bootloader` returned the phone to fastboot without writing UFS.

`pm8941_pwrkey` and `pm8941_resin` registered. On the earlier final image, a
physical Volume Down press produced `KEY_VOLUMEDOWN` (code 114, value 1), and
Volume Up produced `KEY_VOLUMEUP` (code 115, value 1). The current kernel
image's button events have not yet been rechecked. The owner reported seeing
the console during the first boot.

An earlier test record attributed removal of `/dev/sda` to the PR #505 image,
but the recorded image hash is the `e2cdb765…` artifact checked above, where
`/dev/sda` was present and writable. The earlier whole-disk-removal result
cannot be tied to this artifact. The final #505 image and its successful
disk-node check are recorded below. The `e2cdb765…` boot did report all 85 UFS
partition flags read-only; no UFS writes were made.
`/proc/iomem` reports `0x86200000–0x88efffff` as System RAM and
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
did not write UFS. The installed-system backup checksums were verified before
boot.
After this session, a read-only backup of all 84 non-`userdata`, non-`super` GPT
partitions was captured from this guarded RAM boot. Each partition's source
SHA-256 and byte count were checked against the decompressed local copy, and
the compressed archive checksums were rechecked. The separate live userdata
archive remains file-level, non-atomic, and is not a raw partition backup.
The backup is stored outside the repository; it must not be published. After
the last Android boot and before any future flash, the on-device partition
checksums must be taken again and compared with the off-device backup because
Android can rewrite modem partitions. A reviewed button-by-button restore
procedure and supported single-slot writer are still required before a flash.

## 2026-10-29 — installed-system facts, read-only over SSH with the owner's Magisk root

- **SoC** SDM845. Live DT root: `model = "Xiaomi Technologies, Inc. Dipper new MP v2.1"`,
  `compatible = "qcom,sdm845-mtp", "qcom,sdm845", "qcom,mtp"`,
  `qcom,msm-id = <0x141 0x20001>`, `qcom,board-id = <0x37 0x00>`.
  6 GB RAM. `androidboot.cert=M1803E1A` (Mi 8 Global), `hwversion=3.13.0`.
- **The installed system** is a custom Android 14 (SDK 34) ROM with Magisk 30.7, not MIUI;
  its build fingerprint is a spoofed MIUI 8.1 string, and `ro.boot.verifiedbootstate=green`
  with `flash.locked=1` contradict the owner's unlocked bootloader. **No boot-state claim
  may be made from Android on this phone; read it in fastboot.** Running kernel 4.9.337.
- **Not A/B for the OS.** 92 entries under `/dev/block/by-name/`: a single `boot` (64 MiB),
  `recovery` (64 MiB), `dtbo` (8 MiB), `system`, `vendor`, `cache` and `userdata`
  (113 GiB). Only the bootloader chain is slotted: `xbl`, `xbl_config`, `abl`, `tz`, `hyp`,
  `aop`, `cmnlib`, `cmnlib64`, `devcfg`, `keymaster`, `qupfw`, `storsec`.
  **There is therefore no known-good OS slot to fall back to**, which the shared Pixel
  safety model assumes. A full backup of the installed system is a precondition, not a nicety.
- **Boot image** uses Android header v1, page size 4096, `second_size = 0`, and the kernel
  blob ends with **two concatenated FDTs of ~480 KB each** (`d00dfeed`, version 17): the
  base DTB is appended to the kernel and ABL selects one by msm-id/board-id.
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
- **UFS** host at `1d84000.ufshc`. The installed Android `system` is dm-verity over the
  `system` partition.

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
Two diagnostic-image writes to the `recovery` partition from rooted Android were also
made on 2026-10-29. The existing 15-partition backup did not include `logdump`;
an unverified `logdump.img` file is not evidence of a checked phone backup.
The current recovery SHA matches the verified 2026-10-29 19:01 backup
described above; the order of that backup and the two writes is unknown. The
image previously attributed to PR #505 was `e2cdb765…`; its `/dev/sda` node was
present and writable, so it does not verify #505's guard. The final #505 image
and its successful check are recorded above. The mount options and whether
`persist` was mounted during first light are not recorded here.

The recorded 15-partition backup of the installed system before the radio runs
was checksum-verified.

The 2026-10-30 comparison found `boot`, `recovery`, `dtbo`, `vbmeta`,
`fsc`, `devinfo`, `misc`, `logo`, `splash`, `persistbak`, `modemst2`
and `fsg` byte-identical; only `persist`, `modemst1` and `frp` changed.
All five NV partitions were read-only before and after the recorded runs. The
cause of the three differences is not established. Other recorded activity:
NFS-root Omarchy sessions on 2026-10-30, 2026-10-31 and 2026-11-02; modem
starts under `rmtfs -r`, followed by an XPU violation crash and remoteproc
recovery loops. The sequence of boots between the two backups (date, installed
Android or RAM image, and actions) has not been reconstructed, so the later
backup is not a baseline and the changes are not attributed to Android or
Omarchy. The installed ROM's current recovery image matches the 10-29 19:01
backup and its kernel identifies as `4.9.337-perf-g0b3e38ef6c40`; the backup's order
relative to the two diagnostic writes remains unknown. The 10-29 first-light
boot is recorded as `fastboot boot` from RAM, not a recovery boot. The separate
08:53 old-kernel observation's launch method remains unknown; the surviving
record does not establish its source.

### What had to be fixed before any of that
Six defects in the recovered [sdm845-mainline MR !71](https://gitlab.com/sdm845-mainline/linux/-/merge_requests/71)
work, three of them fatal:

1. **`qcom,board-id = <69 0>` (0x45) is polaris's.** dipper reports `0x37`. ABL matches on
   it and silently refuses the whole boot image otherwise — no kernel output,
   no panic, just a reboot. Two blind diagnostic-image attempts were written to
   the `recovery` partition from rooted Android before this mismatch was
   corrected.
2. `drm_panel_init()` no longer exists; the panel probe needed the refcounted
   `devm_drm_panel_alloc()`.
3. `panel-samsung-ea8074.ko` had no `MODULE_LICENSE()`, so modpost refused to link.
4. The touch node named `focaltech,ea8074` at `0x38`; the chip is ST at `0x49`.
5. Its Kconfig entry was copied from an SPI panel (`depends on SPI`, `select DRM_MIPI_DBI`)
   for what is a `mipi_dsi_driver`.
6. `ts_int_default` carried `bias-pull-down` from beryllium; dipper's vendor tree says
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
- The interrupt pin bias was corrected to pull-up per the vendor tree. **No change.**
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
