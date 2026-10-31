<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 (oriole) bring-up notes

Findings for the Pixel 6 port, newest first. The port is a community effort tracked in [issue #2](https://github.com/derekross/omarchy-mobile/issues/2); the 6 Pro (raven) and 6a (bluejay) share it. Facts are marked [V] (checked, with the source) or [I] (an inference or a recovered report still to check). The October 14–16 phone facts below came from read-only queries of a stock phone; later tests booted Linux on a Pixel 6.

Sources:

- `F/`: Google's public factory image `oriole-cp3a.261005.002.a1` ([developers.google.com/android/images](https://developers.google.com/android/images#oriole)), read with HTTP range requests; facts only, no files kept in the repository.
- `U/`: upstream Linux v7.0, `arch/arm64/boot/dts/exynos/google/gs101*.dts(i)`.
- `P/`: postmarketOS pmaports [`device/testing/device-google-oriole`](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/main/device/testing/device-google-oriole), [`soc-google-gs101`](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/main/device/testing/soc-google-gs101) and [`linux-postmarketos-gs101`](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/main/device/testing/linux-postmarketos-gs101) (7.0.6), which builds [gs101-mainline/linux @ d28cfa42](https://github.com/gs101-mainline/linux/tree/d28cfa4275b95e93f4b7a1e743de31b723bd21b8).

## 2026-10-31: build provenance and recovery limits

This describes the unpublished stack in the October 30 smoke report. It is
not a reproducible build of the public Oriole descriptor or an installer
qualification. The records and recovered artifacts were audited offline;
this audit did not reflash or inspect the phone's current partitions.

- **Kernel** [V, recovered source metadata]: the base is
  [`omamobile` commit `4bd35d34abb9`](https://github.com/derekross/linux-omarchy-mobile/commit/4bd35d34abb92a745479a2de62816b28304b4449).
  The native build used a detached worktree at that commit with unpublished
  local changes, producing
  `7.3.0-rc6-oriole-hsi1-late-dev0-g4bd35d34abb9-dirty`.
  There is no published branch containing that complete integration tree.
- **Packages** [V, recovered sources and build receipts]: the mobile source
  was local branch `pixel6-bringup`, based on
  [`1155a7c352ed`](https://github.com/derekross/omarchy-mobile/commit/1155a7c352edf6313fb4e2ff02f054c9cb1902b6),
  with unpublished changes and separate package-source snapshots. The
  `omamobile-device-oriole 0.1.9-2` source matches all 24 files in its build
  receipt; its archived package and the GPU, Wi-Fi, Bluetooth, torch,
  battery, charger, NFC and backlight packages are local builds, not
  packages from the project's published repository. The device package
  was built in an offline ARM64 package container. The smoke report
  establishes the installed versions; source receipts alone do not.
- **Shell** [V, recovered package]: local `omamobile-shell 0.2.12-1` was
  rebuilt from the installed local 0.2.10 source on
  `omamobile-oriole-canvas-budget`, preserving its phone-specific files and
  backporting the Canvas budget fix from
  [`be98c2c22e2b`](https://github.com/derekross/omarchy-mobile/commit/be98c2c22e2b260300c59787861fee200ef2ad58).
  The recovered package's `runtime.js` matches that commit byte for byte.
  This is not a claim that upstream shell 0.2.12 was installed unchanged.
- **Keyring correction** [V, recovered root image]: the local rebuild
  `omamobile-keyring 20261013.oriole1-1` retained the upstream public key
  and added a local public signing key to `omamobile.gpg` and its trusted
  list. The keyring payload matches the installed package's mtree in the
  recovered image; the additional key verifies the archived local device
  package. The local key therefore entered the packaged trust list, not
  only the build environment. The rebuilt source recipe has not yet been
  recovered; this establishes the package contents, not its exact build
  command. This does not follow the contributor-build
  policy, and that rebuilt keyring must not be distributed as the project's
  keyring. Neither the modified keyring nor signing material is included
  in this PR. The correction for the next image is the existing
  [contributor build workflow](../../docs/RELEASES.md#10-signing):
  unchanged upstream keyring, preserved published-package signatures,
  separate `keys/oriole/` and `out/oriole/`, and local-key trust confined to
  the build image. Any later on-device local trust is a separate owner
  action. No installed trust database was changed by this audit.
- **Slot B installation** [I, historical run records]: the initial root
  installation used the local `tools/install-phone` after its dry run,
  writing `boot_b`, `vendor_boot_b`, `dtbo_b` and `userdata`. Later kernel
  deployments used the local `bin/omamobile push` with B-image readback.
  The flags-3 stock-copy write to `vbmeta_b` and the B-success flag
  update at offset `0x35` in `devinfo` were done without project approval.
  The run records report the other `devinfo` bytes preserved and read-only
  protection restored. Early verification tests restored original
  `vbmeta_b`; the later native-root run records retain the B verification
  change. No further `devinfo` or `vbmeta` writes will be made without
  the maintainer's explicit approval. These are historical facts, not
  instructions or an extension of the public installer's permissions.
- **Local deployment tools** [V, recovered October 28 source snapshot]:
  `tools/install-phone` is byte-identical to the version at the mobile
  base `1155a7c352ed` above. `bin/omamobile` has local changes; its `push`
  path adds a `PUSH_MODULES_POLICY=require-match` option, follows image
  symlinks for readback length, and uses systemd's reboot on a native root.
  The complete two-file comparison against that base is in
  [PR #200](https://github.com/derekross/omarchy-mobile/pull/200).
  This is a dated source-snapshot comparison, not proof of the exact
  script bytes used for every earlier deployment, and not a comparison
  against today's main. The recovered Oriole descriptor still allows
  only `boot_b vendor_boot_b dtbo_b userdata`; the metadata writes were
  separate bring-up operations.
- **Slot A and bootloaders** [I, historical run records]: before Linux
  installation, the matching factory build and full OTA booted stock on
  B and then A, both reporting `slider-17.0-15681480`. The separate
  per-slot bootloader-version variables were unsupported, so independent
  partition-version equality was not established. The subsequent Linux
  records preserve A's images and slot record. A fresh partition audit
  has not been performed for this PR. `userdata` now contains Linux;
  returning to Android requires deliberate data restoration, not simply
  switching to slot A.

### Historical B-success write: mechanism and evidence limits

[V, recovered October 18 source and execution transcript] The separate
`mark-b-success-37.py` wrapper made `devinfo` writable with `blockdev --setrw`
on its containing boot LUN and then the partition. It restored the partition
and then the disk to read-only with an EXIT trap, backed by a 20-second
systemd undo timer and a 120-second watchdog. The wrapper did not stop the
storage watcher or change its allowlist. The recovered init's watcher skipped
nodes already marked in `/run/ufs-ro/`; it did not continuously reassert their
read-only flags. This is how the explicit opening remained possible.

The helper wrote a **128-byte header**, with only bit 1 at offset `0x35`
changed, followed by comparison of the full 8192-byte record. The gate's
2026-10-18 09:04:51 UTC execution result reports the one-bit change, unchanged
slot-A/opaque bytes, both nodes restored read-only and refreshed backups
verified. This was not a one-byte write.

The next Fastboot controller completed at 09:06:19 UTC after requiring
`current-slot=b`, `slot-successful:b=yes` and `slot-unbootable:b=no`, without
issuing set-active. The native audit at 09:11:29 UTC reported B success
persisting and A's record unchanged. These are recovered executed assertions
and results; the original Fastboot output and contemporaneous retry count
have not been recovered.

The original gate's before/after images are listed in the private backup
inventory but are not available locally, and the backup host was unreachable
during this audit. The exact bytes at `0x30`–`0x37` therefore remain unverified
for the original pair. This gap is not filled by deriving bytes from the
helper's logic or from a later backup. No new metadata write was attempted.

## 2026-10-30: native boot and RTC alarm status

- [V] A Pixel 6 booted native Linux from slot B with its root on `userdata`, using the unpublished `7.3.0-rc6-oriole-hsi1-late-dev0-g4bd35d34abb9-dirty` kernel and a separate integration package set. A read-only `phone-smoke --here --json` run passed all required checks: storage guard, root, USB and desktop session. It reported no failed units, oops, BUG or WARN, and 48 existing dmesg error lines; sound, sensors and cameras were skipped. This is a test-phone result, not an installation claim for the public images.
- [V, source] On the published kernel's `omamobile` branch, the S2MPG10 alarm callback reads `S2MPS14_REG_ST2` at offset `0x08`. On S2MPG10 that is `INT3M`; [Google's register definitions](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/include/linux/mfd/samsung/s2mpg10-register.h) place `STATUS2` at `0x0d`, and its [RTC driver](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/rtc/rtc-s2mpg10.c) reads the alarm-0 status bit there. The proposed kernel fix is S2MPG10-specific; the S2MPG12 path remains unchanged. The test phone's unpublished kernel already contains the correction.
- [I] The smoke test does not exercise a live pending alarm, alarm delivery, suspend or wake. Those paths remain to be independently verified.

## 2026-10-16: stage 0, part 2: a retail Pixel 6 (stock, bootloader locked)

Read-only queries (`adb shell getprop`, `/dev/block/by-name`, `fastboot getvar all`) of a stock phone; facts only, no serial numbers.

- **Same build as the factory image** [V]: `ro.build.id` CP3A.261005.002.A1, security patch 2026-10-05, bootloader `slider-17.0-15681480` (F/'s `android-info.txt` requires exactly that one). So the F/ facts below apply to this phone, and `OS_PATCH_LEVEL=2026-10` matches its stock build.
- **The board dtbo entry is `0x20304`/`0x10000`** [V]: `ro.boot.dtbo_idx` is 0, and entry 0 of F/'s `dtbo.img` is board_id 0x20304, board_rev 0x10000, as `device.conf` assumed. `ro.boot.hardware.revision` and `getvar hw-revision` both say MP1.0.
- **No `init_boot` or `vendor_kernel_boot` partition** [V] (`getvar all`, `/dev/block/by-name`). The A/B partitions are `boot`, `vendor_boot`, `dtbo`, `pvmfw`, `vbmeta`, `vbmeta_system`, `vbmeta_vendor`, `modem`, the bootloader images (`abl`, `bl1`, `bl2`, `bl31`, `pbl`, `tzsw`, `gsa`, `ldfw`, `dram_train`) and `dpm`, plus the dynamic partitions in `super`. `BOOT_IMAGES="boot vendor_boot dtbo"` is right.
- **Not slotted** [V]: `persist`, `efs` and `efs_backup` (ext4), `modem_userdata`, `metadata`, `misc`, `frp`, `klog`, `fips`, `devinfo`, `mfg_data`, `super` and `userdata`. `/dev/block/by-name` also lists four whole LUNs, `sda` to `sdd`.
- **Bootloader state** [V]: `product:oriole`, `secure-boot:PRODUCTION`, current slot a, `unlocked:no`. Unlocking (`fastboot flashing unlock`) wipes the phone, and comes before any slot B write.
- **`soc_id` is still unknown** [I]: `/sys/firmware/devicetree/base/soc_id` is not readable without root on stock Android.

## 2026-10-14: stage 0, part 1: facts from the factory image (no phone)

### Boot images and partitions

- **No `init_boot` and no `vendor_kernel_boot`** [V] (F/ image zip): the image ships `boot`, `vendor_boot`, `dtbo`, `pvmfw`, the vbmetas and the dynamic partitions, and `fastboot-info.txt` flashes `boot`, `dtbo`, `pvmfw` and `vendor_boot`. So `BOOT_IMAGES="boot vendor_boot dtbo"`: the DTB and our initramfs go in `vendor_boot`, and the generic (empty) ramdisk and the OS version in `boot`. `bin/omamobile images`, `flash` and `push` handle that layout, and `tests/images-layout` checks it. A retail phone confirms the partition table (2026-10-16).
- **Header v4 for `boot` and `vendor_boot`** [V] (F/): `vendor_boot` page size 0x800, two vendor ramdisks and a bootconfig section. Stock's `boot` header leaves `os_version` at 0 (GKI; the AVB footer carries it), so `OS_VERSION`/`OS_PATCH_LEVEL` in `device.conf` are the factory build's (17.0.0, 2026-10), which is also the stock build on a retail phone (2026-10-16).
- **One image for four boards** [V] (F/ `android-info.txt`): `board=slider|whitefin|oriole|raven`.

### Base DTB

- **Two base DTBs, by `soc_id`** [V] (F/ `vendor_boot`): `<0x9845000 0x00>` and `<0x9845001 0x00>`, both with root compatible `google,gs101`. They are gs101's counterparts of cheetah's `0x9855000`/`0x9855001`. Which is A0 and which is B0, and which one a retail phone has, are [I].
- **Upstream's gs101 DTs carry no `/soc_id`** [V] (U/), while `bin/omamobile images` requires the DTB to be built with the first `SOC_IDS` value. Our oriole board DTS (or a kernel commit) has to add it. postmarketOS boots the upstream DTB without one (P/), so ABL may fall back to the first DTB when nothing matches [I].
- **`/ect` and `/chosen/bootargs`** [V]: stock has both, and upstream `gs101.dtsi`/`gs101-pixel-common.dtsi` keep both ("required to be present by bootloader", "otherwise it crashes").
- **Root `#address-cells = <2>`, `#size-cells = <1>`** [V] (F/), as on gs201: each `reg` entry is 12 bytes (AGENTS.md, reserved memory).
- **Console UART at `0x10A00000`** [V] (F/ stock bootargs: `earlycon=exynos4210,mmio32,0x10A00000`), the same address as gs201's.

### Board dtbo

[V] (F/ `dtbo.img`: 18 entries, page size 4096), read from each entry's strings:

| board_id | board_rev | Panel | Touch | Board |
| --- | --- | --- | --- | --- |
| 0x20302, 0x20303, 0x20304 | 0x10000, 0x10100 (0x20303 also 0x10002) | S6E3FC3 | ST FTS | oriole |
| 0x20202, 0x20203, 0x20204 | 0x10000, 0x10100 (0x20203 also 0x10001) | S6E3HC3 | Samsung `sec_ts` | raven |
| 0x201, 0x20001 | several | S6E3HC2 | both | development boards [I] |

- **Oriole's panel is the Samsung S6E3FC3; its touch controller is an ST FTS on SPI** [V] (F/, and P/'s oriole DT: `"st,spi"` on SPI11, an out-of-tree driver). "goodix" in every entry is the under-display fingerprint sensor [I].
- **Retail board_id/board_rev**: the newest, `0x20304`/`0x10000` (cheetah's is `0x30306`/`0x10000`), as `device.conf` and `oriole-m1-overlay.dts` use. Confirmed with `ro.boot.dtbo_idx` on a retail phone (2026-10-16) [V].

### Display trigger

- **postmarketOS writes `0x3061` to DECON at `0x1c300030` at boot** "to enable framebuffer refreshing" (P/ `soc-google-gs101/00-enable-fb.sh`). That is gs101's counterpart of cheetah's `TRIG_CON` write at `0x1c240030` [I]. Read it first, on a booted phone, before any write, and never use cheetah's address on oriole. It belongs in `device.conf` as `SIMPLEFB_TRIG_CON="0xADDR 0xVALUE"` (the key from #3 and #4), not in code; oriole gets no `SIMPLEFB_TRIG_CON` until that read has been done.

### GPU

- **The Mali-G78 is a Valhall Job Manager GPU, so the kernel driver is Panfrost, not Panthor** [V] (P/: `arm,mali-valhall-jm`, `DRM_PANFROST=y`). Our Mesa package already builds the `panfrost` Gallium driver, which serves both. The GPU node and its supplies are in the gs101-mainline fork, not upstream v7.0 [V] (U/, P/).

### Still needs a phone

- the `soc_id` the phone reports (needs root, or the bootloader's own report);
- with root: the live DT (`/sys/firmware/fdt`) and `/proc/iomem`, to check every stock `reserved-memory` region.

`bin/omamobile capture` collects these into a private folder (`~/android/reference`); post facts, never the files.

And before oriole's first boot, in the tree:

- **An initramfs.** Done in the tree: oriole uses the shared `initramfs/init`, and `bin/omamobile initramfs` packs its `UFS_RW` (`boot_b vendor_boot_b dtbo_b userdata`) into `/etc/omamobile-ufs-rw`, which the init's storage guard reads. A missing or malformed list leaves every partition read-only (`tests/storage-guard`). No phone has booted it yet.
- **`/soc_id` in the board DTS** (see Base DTB).
