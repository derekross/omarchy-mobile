<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a (bluejay) bring-up notes

## 2026-11-09: review split and slot-success audit (offline)

The development source remains inspectable in [#543](https://github.com/derekross/omarchy-mobile/pull/543).
As of 2026-11-10, it is closed unmerged in favour of documentation
[#561](https://github.com/derekross/omarchy-mobile/pull/561), initramfs
[#562](https://github.com/derekross/omarchy-mobile/pull/562), installer
[#563](https://github.com/derekross/omarchy-mobile/pull/563) and bring-up
[#565](https://github.com/derekross/omarchy-mobile/pull/565).
The exact tested kernel is `c934e316b` in the contributor's
`bringup/bluejay-tested-20261108` branch; the revised [kernel topics #225 through #231](UPSTREAM.md#kernel-topics-in-review) are not a new hardware-qualified stack. This documentation submission
changes no package, descriptor, initramfs, startup service or phone.

The 2026-11-08 saved dry-run and write logs identify the existing project's
`omamobile-bootctl mark-successful` helper, invoked through
`omamobile-boot-success`. They record devinfo layout 3.15's slot bytes:

| State | Slot A, offsets 0x30–0x33 | Slot B, offsets 0x34–0x37 |
| --- | --- | --- |
| Before the write | `02 0a 00 00` | `01 04 00 00` |
| After the write | `02 0a 00 00` | `01 06 00 00` |

Only offset `0x35` changed, `04` to `06`; the helper reported that all 8192
bytes were read back and compared. A subsequent read-only check recorded the
partition and its whole disk read-only again. The automatic boot-success unit
was masked. A read-only devinfo backup made earlier that day is retained; its
slot bytes match the write log's before-state exactly.
The saved command output does not record a hash of the actual boot-control
executable, so the precise binary provenance is not established by those logs.

This was an actual protected-data write and is not covered by the statement
that no radio NV/calibration was changed. Further gs101 slot marking is on
hold under [#252](https://github.com/derekross/omarchy-mobile/issues/252).
No slot write, reboot, hardware probe or fresh device backup was performed for
this offline revision. A fresh read-only backup and independent validation
remain required before further hardware work; do not restore the old devinfo
image or repeat the marking command.

## 2026-11-08: persistent accelerated desktop and station Wi-Fi

The Pixel 6a now boots Arch Linux ARM on userdata with systemd, USB SSH,
SDDM, Hyprland and Omarchy's Quickshell. Normal reboots automatically start
ALIX touch, retained simpledrm display refresh, BCM4389 station Wi-Fi and
Mali-G78/Panfrost rendering. The owner confirmed unlocking, opening apps and
scrolling normally. Kernel: `7.3.0-rc6-omamobile-bluejay-input-gated0`.

| Subsystem | Verified result | Limit |
| --- | --- | --- |
| Boot/storage | Slot B, persistent ext4 root, 49-partition read-only guard, root expanded to 109 GiB | Development overlay; not a release installer |
| USB | NCM SSH and ACM; aggregation timer retries a full TX request pool | Replug/suspend not qualified |
| Touch | ALIX 36:48, one/two-finger motion and release, all four edge zones; zero SPI errors/timeouts | Polling; no firmware or calibration writes |
| Display | 1080x2400 retained simpledrm, approximately 60 Hz, actual desktop frames | No native DSI/panel modesetting |
| GPU | Mali-G78 MC20, GLES 3.1, Panfrost render node, correct clear/solid/blended pixels through 1024x1024 | 151 MHz shader point; no Vulkan/full DVFS qualification |
| Wi-Fi | BCM4389/3, NetworkManager association/reconnect, wireless-bound HTTPS with TLS verification | Station only; P2P, hotspot, roaming and suspend untested |
| Keys | Both volume press/release pairs | Power release remains unresolved |

The platform changes are still development source. They are not in a
published release kernel, and the installed root contains manually staged
matching modules, privately extracted firmware and a patched Aquamarine
library. Do not treat this PR as a downloadable ready-to-flash distribution.
See [UPSTREAM.md](UPSTREAM.md) for source dependencies and reproduction gaps,
[PERSISTENCE-PLAN](PERSISTENCE-PLAN.md) for recovery/startup, and
[GPU-PLAN](GPU-PLAN.md) for GPU qualification.

The initial GPU probe deferred because `clk_acpm` was missing; its bounded
service requested an orderly reboot. Adding the exact matching module and
holding the unrelated `cpufreq-dt` consumer allowed the probe and rendering
tests to pass. Startup now has durable failure markers, deadlines and a
software-rendering fallback. No automatic boot-image or boot-success writer
is enabled. Existing backups were retained; no bootloader, radio NV or
calibration data was modified by the Linux bring-up.

A later submission smoke test found the development root lacked its FUSE
module. Adding the matching module repaired `xdg-document-portal`. The smoke
report still discloses the inherited early trace-format warning and the
expected `-ECANCELED` USI hold before manual initialization. Audio, modem,
Bluetooth, battery/charging, sensors, cameras and suspend are not qualified.


The Pixel 6a's tracking thread is [#348](https://github.com/derekross/omarchy-mobile/issues/348).
The earlier shared GS101 effort is [#2](https://github.com/derekross/omarchy-mobile/issues/2).
Facts are marked [V] (checked, with a source) or [I] (inferred).
The dated stage-0 entries below predate the first phone boot and describe
what was known from public GPL sources and the factory image at that time.

Sources:

- `G/`: Google's GPL device tree for bluejay, [kernel/devices/google/bluejay](https://android.googlesource.com/kernel/devices/google/bluejay/+/refs/tags/android-16.0.0_r0.9/dts/) at tag `android-16.0.0_r0.9`.
- `S/`: Google's GPL gs101 SoC device tree, [kernel/devices/google/gs101](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/) at the same tag.
- `R/`: Google's GPL device tree for oriole and raven, [kernel/devices/google/raviole](https://android.googlesource.com/kernel/devices/google/raviole/+/refs/tags/android-16.0.0_r0.9/dts/) at the same tag, as the control: what it says about oriole is checked against [oriole's notes](../oriole/NOTES.md).
- `U/`: upstream Linux, `arch/arm64/boot/dts/exynos/google/gs101*.dts(i)` and `Documentation/devicetree/bindings/arm/google.yaml`.
- `O/`: [oriole's notes](../oriole/NOTES.md), for the facts a 6a shares with a Pixel 6 (the factory image layout, the retail phone's partitions). Each is [I] for bluejay until its own image or phone confirms it.
- `F/`: Google's public factory image `bluejay-cp3a.261005.002.a1` (SHA-256 `79d88414…`, the newest bluejay build on [developers.google.com/android/images](https://developers.google.com/android/images#bluejay) on 2026-11-02), read with HTTP range requests on the laptop: the outer zip's central directory, the stored image zip's, then only `android-info.txt`, `fastboot-info.txt`, `vbmeta.img`, `boot.img`, `vendor_boot.img` and `dtbo.img`, about 42 MB in all. Facts only, no files kept in the repository. The footers were read with the pinned avbtool 1.4.0 (`tools/toolchain.lock`), the headers and the dtbo table with a short parser of their documented layouts, the DTBs with `fdtget`.

## 2026-11-02: stage 0, part 2: the factory image settles AVB (no phone)

The question the notes left open, and that the maintainer wants settled before anyone flashes (issue #2): does a 6a's stock `vbmeta` chain `boot` and `vendor_boot`? F/ answers it. Everything here is [V] from F/ unless marked.

### Verified boot

- **`vbmeta` chains `boot`, `vbmeta_system` and `vbmeta_vendor`, and nothing else** (`avbtool info_image vbmeta.img`): three chain partition descriptors, `boot` at rollback index location 2, `vbmeta_system` at 1, `vbmeta_vendor` at 3, flags 0 on each; the vbmeta itself is SHA256_RSA4096, rollback index 1791158400, flags 0, location 0, release string `avbtool 1.4.0`. `vendor_boot` (32,421,888 bytes) and `dtbo` (978,260 bytes) are hash descriptors inside `vbmeta`, next to the bootloader images (`abl`, `bl1`, `bl2`, `bl31`, `gsa`, `ldfw`, `pbl`, `tzsw`); there is no `init_boot`, as expected. Its props carry the build fingerprint `google/bluejay/bluejay:17/CP3A.261005.002.A1/16269273:user/release-keys` for `dtbo`, `vendor_boot` and `vendor_dlkm`.
- **`boot` carries a signed footer**: SHA256_RSA4096, rollback index 1791158400, padded to 67,108,864 bytes (0x4000000) from 16,658,432, with `com.android.build.boot.os_version` 17, `com.android.build.boot.security_patch` 2026-10-05 and the fingerprint above. `vendor_boot` and `dtbo` carry unsigned footers (algorithm NONE, rollback index 0, a hash descriptor and the fingerprint only), padded to 64 MiB and 16 MiB.
- **So slot B's `boot` needs an AVB footer, and `vendor_boot` and `dtbo` don't.** libavb reads a chained partition with no footer as invalid metadata, which an unlocked bootloader never lets through, while a hash descriptor's mismatch is a verification error it does let through ([cheetah's notes, 2026-10-28](../cheetah/NOTES.md), [RELEASES](../../docs/RELEASES.md) §3.1). `device.conf` now has `AVB_FOOTERS="boot:0x4000000"`, `AVB_ROLLBACK_INDEX=1791158400` and `AVB_SECURITY_PATCH=2026-10-05`: the partition size is the one stock's footer pads to, the index and the patch are stock's own, never higher (a stored higher index would lock stock out of slot A). A one-image `AVB_FOOTERS` is a layout `bin/omamobile images`, `push` and `install-phone` already handle (`tests/images-layout`, `tests/build-rootfs`). `boot_b`'s size on a retail 6a (`getvar partition-size:boot_b`) is [I] 0x4000000; `push` and `install-phone` refuse the image if it isn't, so a wrong guess costs a message, not a boot. Whether a 6a's unlocked ABL would in fact stop on a footer-less `boot`, as the 7a's does and the 7 Pro's does with a stock `vbmeta_b`, is not tested and need not be: with the footer the question doesn't arise.
- **Oriole's descriptor has no `AVB_FOOTERS`**; its F/ is the same build id, so its `vbmeta` most likely chains `boot` the same way [I], a point for oriole's own notes.

### The rest of the factory image

- **Build** `CP3A.261005.002.A1`, Android 17, security patch 2026-10-05 (the zip name, the fingerprint, the `boot` footer): `OS_VERSION=17.0.0` and `OS_PATCH_LEVEL=2026-10` are the 6a's own now, not oriole's. `android-info.txt`: `require board=bluejay`, `require version-bootloader=bluejay-17.0-15681480`, `require version-baseband=g5123b-145971-260721-B-15910359`.
- **No `init_boot`, no `vendor_kernel_boot`** (`fastboot-info.txt` flashes `boot`, `dtbo`, `pvmfw`, `vendor_boot`, `vbmeta` with `--apply-vbmeta`, `vbmeta_system` and `vbmeta_vendor`, then the super partitions; the image zip has no other boot image): `BOOT_IMAGES="boot vendor_boot dtbo"` and `UFS_RW` stand.
- **`boot` header v4**: the kernel only (16,637,222 bytes), no ramdisk, `os_version` 0, an empty command line, as O/ said the GKI `boot` would be.
- **`vendor_boot` header v4, page size 0x800**, two vendor ramdisk entries, a 107-byte bootconfig, and 536,176 bytes of DTBs: two, `soc_id` `<0x9845000 0x0>` and `<0x9845001 0x0>`, root compatible `google,gs101` with no `model`, `#address-cells` 2 and `#size-cells` 1. Both carry stock's `/chosen/bootargs`: `earlycon=exynos4210,mmio32,0x10A00000 console=ttySAC0,115200n8 clocksource=arch_sys_counter root=/dev/ram0 androidboot.boot_devices=14700000.ufs androidboot.hardware.platform=gs101 androidboot.debug_level=0x4948 firmware_class.path=/vendor/firmware reserve-fimc=0xffffff90f9fe0000 clk_ignore_unused loop.max_part=7 coherent_pool=4M no_console_suspend softlockup_panic=1`, oriole's line. The header's own vendor command line is the module `load_sequential` list plus `bootconfig`. `VENDOR_CMDLINE` and `VENDOR_PAGESIZE` are confirmed.
- **`dtbo.img` has exactly the ten entries G/ predicted, in G/'s order** (table version 0, page size 4096): index 0 is 0x20501/0x10000, 1 and 2 are 0x20502 at 0x10000 and 0x10100, 3 to 5 are 0x20503 at 0x10000, 0x10100 and 0x10200, 6 and 7 are 0x20504 at 0x10000 and 0x10100, 8 is 0x20505/0x10000, and **index 9 is 0x20506/0x10000**, the MP 1.0 entry `device.conf` uses. Which entry a retail 6a boots (`ro.boot.dtbo_idx`) stays [I] until a phone says so; if it is 9, the descriptor is right as it stands.

### What is left before a flash

From a retail 6a, read-only, before anything is written (CONTRIBUTING §5.1 first): `getvar all` (product, slot state, the partition list and sizes, `hw-revision`), `ro.boot.dtbo_idx`, the build id and security patch; with root or `bin/omamobile capture`, the live DT (which `soc_id`, `/chosen/bootargs`, every `reserved-memory` region against `/proc/iomem`). Post facts, never the files. Then the board DTS's DTB in a kernel build (`DEVICE=bluejay bin/omamobile images`, which now adds `boot`'s footer), the oriole initramfs path, and a human at the phone with the way back to slot A.

## 2026-11-01: stage 0, part 1: facts from Google's GPL device trees (no phone, no factory image)

### Base DTB and `soc_id`

- **Bluejay boots the same two base DTBs as oriole and raven** [V] (G/ `Makefile`, `gs101_dtbs`): `gs101/gs101-a0.dtb` and `gs101/gs101-b0.dtb`, with the board as a dtbo overlay on top. So, as on oriole, our board DTS is the base DTB and ABL picks it by `soc_id`.
- **`soc_id` A0 is `<0x09845000 0x0>`, B0 is `<0x09845001 0x0>`** [V] (S/ `gs101-a0.dts`, `gs101-b0.dts`, line 12 of each). This settles the label that O/ left [I]: `0x...001` is B0, as cheetah's `0x9855001` is. Which of the two a retail 6a has is still [I]; `bin/omamobile images` ships both.
- **The first-light board DTS** (`gs101-bluejay.dts`, [kernel #179](https://github.com/derekross/linux-omarchy-mobile/pull/179), merged 2026-11-02 without a boot, as oriole's first board was) is oriole's file with bluejay's model and compatible (`google,gs101-bluejay`, `google,gs101`), `soc_id` set to B0, `/chosen/bootargs` with `panic=10`, the 1080x2400 framebuffer and splash carve-out, and without the two LDOs described next. U/ `master` has no bluejay binding or DTS; the binding entry goes in the same pull request.

### Board dtbo

[V] (G/ `gs101-bluejay-*.dts`, read from each overlay's `board_id`/`board_rev`):

| Overlay | board_id | board_rev |
| --- | --- | --- |
| `dev` | 0x20501 | 0x10000 |
| `proto1_0`, `proto1_1` | 0x20502 | 0x10000, 0x10100 |
| `evt1_0`, `evt1_1`, `evt1_2` | 0x20503 | 0x10000, 0x10100, 0x10200 |
| `dvt1_0`, `dvt1_1` | 0x20504 | 0x10000, 0x10100 |
| `pvt1_0` | 0x20505 | 0x10000 |
| `mp1_0` | 0x20506 | 0x10000 |

- **The overlay's model and compatible** [V]: `GS101 BLUEJAY MP 1.0 based on GS101`, `google,GS101 BLUEJAY` (G/ `gs101-bluejay-mp1_0.dts`).
- **`device.conf` uses the MP 1.0 entry, 0x20506/0x10000.** That a retail 6a boots it is [I]: oriole, lynx and panther boot their MP entry, but raven boots its DVT entry (0x20204, `ro.boot.dtbo_idx` 6, [raven's descriptor](../raven/device.conf)), so only a stock `dtbo.img` or `ro.boot.dtbo_idx` on a retail phone settles it (O/ did that for oriole on 2026-10-16). The entry's index is never its board id: the board id and revision are fields of the entry.
- **Oriole's control** [V]: R/ `gs101-oriole.dts` is 0x20304/0x10000, what O/ records from the factory image and the phone, so reading Google's overlays gives the right retail entry for a sibling.

### Panel and touch

- **The panel is a Samsung S6E3FC3, bluejay variant** [V] (G/ `gs101-bluejay-display.dtsi`): `samsung,s6e3fc3_6a`, DSI channel 0, reset on `gpp24-1`, VCI from `m_ldo22_reg` at 3.025 V, `vddi-supply` deleted; 1080x2400; DSIM PLL p/m/s/k `0x2 0xDF 0x3 0xA800`, HS clock 684 MHz, escape clock 20 MHz. The second DSIM (`drmdsim1`) is disabled. Oriole's panel driver lead (the S6E3FC3 on kernel #116's gs-decon) applies, with a 6a panel entry still to write.
- **Touch is an ST FTS on SPI** [V] (G/ `gs101-bluejay-touch.dtsi` including S/ `gs101-fts-touch.dtsi`): 10 MHz, chip id `0x36 0x48`, maximum coordinates 1079x2399, the under-display fingerprint area at (540, 1717), firmware `ftm5_fw_b3.ftb`, the same controller family as oriole's. The driver is out of tree; nothing in `omamobile` yet.

### Regulators the board file leaves out

- **Upstream's oriole DTS describes two LDOs on the main PMIC (`ldo14m`, `ldo31m`) under `acpm_ipc`; raven's does not, and bluejay's doesn't either.** The reason [V]: both come from the shared S/ `gs101-pmic.dtsi`, `regulator-always-on` (LDO14M `L14M_AVDD_TCXO`, 1.6-1.95 V; LDO31M `L31M_NFC`, 1.6-1.95 V), and S/ `gs101-whitefin2-pmic.dtsi`, which both bluejay and oriole include, renames LDO31M to `L31M_DISP_VDDI`. Bluejay's own G/ `gs101-bluejay-pmic.dtsi` touches neither; neither does R/ `gs101-oriole-pmic.dtsi`. So the upstream block is a description of the shared values, not an oriole-only fact, and a rail Linux doesn't describe stays as the bootloader left it (the regulator core only turns off rails it knows about, AGENTS.md). If a first boot shows the display's VDDI or the TCXO dropping, the block is the first thing to add, with that boot as the evidence.
- **Bluejay's include list** [V] (G/ `gs101-bluejay.dtsi`): `gs101-common`, the raviole battery, bluejay's camera-pmic, battery, charging, usecases, camera, display, thermal, pmic, sbbm, the whitefin modem (`whitefin-cp-s5200-sit-common`, `whitefin2-cp-s5200-sit`), NFC, `slider-gsa-gsc`, `slider2-gps`, `whitefin2-pmic`, `common-bcl` and bluejay's Type-C; the MP overlay adds audio, fingerprint, touch, the eSE and USB. The modem, GNSS, GSA and PMIC leads from raven's plans therefore apply.

### What `device.conf` rests on

The descriptor carries no comments; this table is its provenance.

| Key | Value | Mark | Source |
| --- | --- | --- | --- |
| `CODENAME`, `NAME`, `SOC` | bluejay, Pixel 6a, gs101 | [V] | G/, the kernel binding |
| `COMPATIBLE` | `google,gs101-bluejay` | [V] | the first-light DTS and its binding entry |
| `PACKAGE` | `omamobile-device-bluejay` | the package doesn't exist yet; `bin/omamobile initramfs` falls back when its `omamobile-bootctl.c` is missing, as for oriole | |
| `DTB` | `exynos/google/gs101-bluejay.dtb` | [V] | the Makefile line in [kernel #179](https://github.com/derekross/linux-omarchy-mobile/pull/179), merged; `DEVICE=bluejay bin/omamobile images` builds from a kernel after it |
| `SOC_IDS` | `b0:0x9845001 a0:0x9845000` | [V] | S/ `gs101-b0.dts`, `gs101-a0.dts` |
| `DTBO_SOURCE`, `DTBO_BOARD_ID`, `DTBO_BOARD_REV` | the empty overlay, 0x20506, 0x10000 | [V] for the MP 1.0 entry (index 9 of stock's `dtbo.img`), [I] that retail boots it | G/ `gs101-bluejay-mp1_0.dts`; F/ `dtbo.img` (2026-11-02) |
| `VENDOR_CMDLINE` | oriole's line: `earlycon` at `0x10A00000`, the gs101 UART | [V] | F/ `vendor_boot`'s DTBs, `/chosen/bootargs` (2026-11-02); O/ |
| `VENDOR_PAGESIZE` | 0x800 | [V] | F/ `vendor_boot` header v4 (2026-11-02); O/ |
| `OS_VERSION`, `OS_PATCH_LEVEL` | 17.0.0, 2026-10 | [V] | F/ build `CP3A.261005.002.A1`, the `boot` footer's `os_version` 17 and `security_patch` 2026-10-05 (2026-11-02). Stock's GKI `boot` header leaves `os_version` at 0 and the AVB footer carries the version, so these header fields are informational; the rollback index is the AVB one below |
| `BOOT_IMAGES`, `UFS_RW` | `boot vendor_boot dtbo`; `boot_b vendor_boot_b dtbo_b userdata` | [V] | F/ `fastboot-info.txt` and the image zip (no `init_boot`, no `vendor_kernel_boot`, 2026-11-02); O/; `getvar all` on a retail 6a confirms the partition table |
| `INITRAMFS_INIT` | the shared init | [V] | as oriole |
| `PANEL_SIZE` | 1080x2400 | [V] | G/ `gs101-bluejay-display.dtsi` |
| `AVB_FOOTERS`, `AVB_ROLLBACK_INDEX`, `AVB_SECURITY_PATCH` | `boot:0x4000000`, 1791158400, 2026-10-05 | [V] | F/ `vbmeta.img` chains `boot` (and the two vbmetas) and holds `vendor_boot` and `dtbo` as hash descriptors; the `boot` footer's rollback index, security patch and padded size (2026-11-02, above). `boot_b`'s size on a retail phone is [I]: `push` and `install-phone` refuse a mismatch |
| `SIMPLEFB_TRIG_CON`, `BRINGUP_PROBE` | unset | | gs101's DECON trigger register (`0x1c300030`, [V] on raven) is read on a booted 6a before it is written anywhere; a descriptor carries only its own phone's register |

### Still needs the factory image or a phone

From the current `bluejay-*-factory-*.zip` (HTTP range reads, facts only, as O/ did for oriole): `android-info.txt` (`board=`, the required bootloader), `fastboot-info.txt` (the partitions flashed), the `vendor_boot` header (version, page size, the two DTBs' `soc_id`, stock `/chosen/bootargs`), the `boot` header, the `dtbo.img` table (expect the six board ids above; which entry is 0x20506), the build id for `OS_PATCH_LEVEL`, and `vbmeta.img`'s chain partition descriptors with the `boot` and `vendor_boot` footers' rollback index and security patch, which decide whether slot B needs `AVB_FOOTERS`. Done on 2026-11-02 (the entry above): `vbmeta` chains `boot` only, and the descriptor carries the footer.

From a retail 6a, read-only, before anything is written: `getvar all` (product, slot, partition list, `hw-revision`), `ro.boot.dtbo_idx`, the build id and security patch; with root or `bin/omamobile capture`, the live DT (`soc_id`, `/chosen/bootargs`, every `reserved-memory` region against `/proc/iomem`). Post facts, never the files. A retail 6a has a locked bootloader, and unlocking wipes it; the stock capture (CONTRIBUTING §5.1) comes first.

Before the first boot of slot B: the AVB answer (settled 2026-11-02), the board DTS's DTB in a kernel build (`DEVICE=bluejay bin/omamobile images`), the oriole initramfs path (`UFS_RW` packed into `/etc/omamobile-ufs-rw`, `tests/storage-guard`), and a human at the phone with the way back to slot A.
