<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a (bluejay) bring-up notes

Findings for the Pixel 6a port, newest first. The port shares the Pixel 6 (oriole) and 6 Pro (raven) effort tracked in [issue #2](https://github.com/derekross/omarchy-mobile/issues/2). Facts are marked [V] (checked, with the source) or [I] (an inference to check on a phone or in the factory image). Nothing has been flashed or booted yet, and no 6a has been queried: every fact below comes from public GPL sources on the laptop.

Sources:

- `G/`: Google's GPL device tree for bluejay, [kernel/devices/google/bluejay](https://android.googlesource.com/kernel/devices/google/bluejay/+/refs/tags/android-16.0.0_r0.9/dts/) at tag `android-16.0.0_r0.9`.
- `S/`: Google's GPL gs101 SoC device tree, [kernel/devices/google/gs101](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/) at the same tag.
- `R/`: Google's GPL device tree for oriole and raven, [kernel/devices/google/raviole](https://android.googlesource.com/kernel/devices/google/raviole/+/refs/tags/android-16.0.0_r0.9/dts/) at the same tag, as the control: what it says about oriole is checked against [oriole's notes](../oriole/NOTES.md).
- `U/`: upstream Linux, `arch/arm64/boot/dts/exynos/google/gs101*.dts(i)` and `Documentation/devicetree/bindings/arm/google.yaml`.
- `O/`: [oriole's notes](../oriole/NOTES.md), for the facts a 6a shares with a Pixel 6 (the factory image layout, the retail phone's partitions). Each is [I] for bluejay until its own image or phone confirms it.

## 2026-11-01: stage 0, part 1: facts from Google's GPL device trees (no phone, no factory image)

### Base DTB and `soc_id`

- **Bluejay boots the same two base DTBs as oriole and raven** [V] (G/ `Makefile`, `gs101_dtbs`): `gs101/gs101-a0.dtb` and `gs101/gs101-b0.dtb`, with the board as a dtbo overlay on top. So, as on oriole, our board DTS is the base DTB and ABL picks it by `soc_id`.
- **`soc_id` A0 is `<0x09845000 0x0>`, B0 is `<0x09845001 0x0>`** [V] (S/ `gs101-a0.dts`, `gs101-b0.dts`, line 12 of each). This settles the label that O/ left [I]: `0x...001` is B0, as cheetah's `0x9855001` is. Which of the two a retail 6a has is still [I]; `bin/omamobile images` ships both.
- **The first-light board DTS** (`gs101-bluejay.dts`, [kernel #179](https://github.com/derekross/linux-omarchy-mobile/pull/179), in review) is oriole's file with bluejay's model and compatible (`google,gs101-bluejay`, `google,gs101`), `soc_id` set to B0, `/chosen/bootargs` with `panic=10`, the 1080x2400 framebuffer and splash carve-out, and without the two LDOs described next. U/ `master` has no bluejay binding or DTS; the binding entry goes in the same pull request.

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
| `DTB` | `exynos/google/gs101-bluejay.dtb` | [V] | the Makefile line in [kernel #179](https://github.com/derekross/linux-omarchy-mobile/pull/179), in review; in no published kernel yet, so `DEVICE=bluejay bin/omamobile images` waits for it |
| `SOC_IDS` | `b0:0x9845001 a0:0x9845000` | [V] | S/ `gs101-b0.dts`, `gs101-a0.dts` |
| `DTBO_SOURCE`, `DTBO_BOARD_ID`, `DTBO_BOARD_REV` | the empty overlay, 0x20506, 0x10000 | [V] for the MP 1.0 entry, [I] that retail boots it | G/ `gs101-bluejay-mp1_0.dts` |
| `VENDOR_CMDLINE` | oriole's line: `earlycon` at `0x10A00000`, the gs101 UART | [I] | O/ (stock oriole's bootargs); the 6a's stock `vendor_boot` confirms |
| `VENDOR_PAGESIZE` | 0x800 | [I] | O/ (oriole's v4 header); the 6a's stock `vendor_boot` header confirms |
| `OS_VERSION`, `OS_PATCH_LEVEL` | 17.0.0, 2026-10 | [I] | O/ (oriole's factory build); the current bluejay factory build id replaces them. Stock's GKI `boot` header leaves `os_version` at 0 and the AVB footer carries the version (O/), so these header fields are informational; the rollback question is the AVB one below |
| `BOOT_IMAGES`, `UFS_RW` | `boot vendor_boot dtbo`; `boot_b vendor_boot_b dtbo_b userdata` | [I] | O/ (no `init_boot`, no `vendor_kernel_boot` on a Pixel 6); the 6a's `fastboot-info.txt` or `getvar all` confirms |
| `INITRAMFS_INIT` | the shared init | [V] | as oriole |
| `PANEL_SIZE` | 1080x2400 | [V] | G/ `gs101-bluejay-display.dtsi` |
| `AVB_FOOTERS`, `AVB_ROLLBACK_INDEX`, `AVB_SECURITY_PATCH` | unset | open | whether the 6a's `vbmeta_b` chains `boot` and `vendor_boot` as stock's does is not known: the factory `vbmeta.img` (`avbtool info_image`, chain partition descriptors) and the stock images' footers (rollback index, `com.android.build.*.security_patch`) decide it ([RELEASES](../../docs/RELEASES.md) §3.1). Oriole's native boot records a `vbmeta_b` change made without approval (O/), so footer-less images on slot B are not known to boot on a gs101 Pixel; no flash until this is settled |
| `SIMPLEFB_TRIG_CON`, `BRINGUP_PROBE` | unset | | gs101's DECON trigger register (`0x1c300030`, [V] on raven) is read on a booted 6a before it is written anywhere; a descriptor carries only its own phone's register |

### Still needs the factory image or a phone

From the current `bluejay-*-factory-*.zip` (HTTP range reads, facts only, as O/ did for oriole): `android-info.txt` (`board=`, the required bootloader), `fastboot-info.txt` (the partitions flashed), the `vendor_boot` header (version, page size, the two DTBs' `soc_id`, stock `/chosen/bootargs`), the `boot` header, the `dtbo.img` table (expect the six board ids above; which entry is 0x20506), the build id for `OS_PATCH_LEVEL`, and `vbmeta.img`'s chain partition descriptors with the `boot` and `vendor_boot` footers' rollback index and security patch, which decide whether slot B needs `AVB_FOOTERS`.

From a retail 6a, read-only, before anything is written: `getvar all` (product, slot, partition list, `hw-revision`), `ro.boot.dtbo_idx`, the build id and security patch; with root or `bin/omamobile capture`, the live DT (`soc_id`, `/chosen/bootargs`, every `reserved-memory` region against `/proc/iomem`). Post facts, never the files. A retail 6a has a locked bootloader, and unlocking wipes it; the stock capture (CONTRIBUTING §5.1) comes first.

Before the first boot of slot B: the AVB answer above, the board DTS's DTB in a kernel build (`DEVICE=bluejay bin/omamobile images`), the oriole initramfs path (`UFS_RW` packed into `/etc/omamobile-ufs-rw`, `tests/storage-guard`), and a human at the phone with the way back to slot A.
