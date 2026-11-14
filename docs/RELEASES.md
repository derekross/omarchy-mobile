<!-- SPDX-License-Identifier: MIT -->
# Builds and releases for many devices

How Omarchy Mobile goes from one hand-built Pixel 7 Pro to a project that builds and releases for several Pixels with the same tools. This is the design; the order of the work is the "Multi-device builds and releases" track in [ROADMAP.md](ROADMAP.md) §3.8. Status (2026-10-13): step 1 (the device descriptor and `DEVICE=` in `bin/omamobile`) is done for cheetah, and so is most of §6: the root image (`tools/build-rootfs`), the installer (`tools/install-phone`, the bundle's `install`), the first-boot setup (`omamobile-firstboot`), the bundle (`tools/make-bundle`), aarch64 package builds without a phone (`tools/build-packages`) and per-phone provisioning (`tools/phone-provision`). They are tested offline (`tests/all`) and not yet run on a phone: [REINSTALL-RUNBOOK](../device/cheetah/REINSTALL-RUNBOOK.md) is their first use. The kernel package (§4) and the package hook (§5) are built and tested offline (2026-11-01: `packages/linux-omamobile`, `packages/omamobile-boot-update`, `tools/stage-boot-files`; §4.1 and §5.5 say what exists) and not yet run on a phone; signed releases (§7-§11) are still design.

The safety model in [CONTRIBUTING.md](../CONTRIBUTING.md) §3 and [AGENTS.md](../AGENTS.md) §1 is not up for redesign here. Every tool, hook and installer below keeps it:

- Omarchy Mobile lives on **slot B and `userdata` only**. Slot A keeps stock Android as the way back.
- Nothing ever writes `bootloader`, `abl`, `radio`/`modem`, `devinfo` (apart from the existing boot-success marker), `persist`, `efs*`, `modem_userdata` or `vbmeta`. Nothing runs an unsuffixed `fastboot flash`, `fastboot -w`, `--slot=all` or `flashing lock`.
- The initramfs storage guard runs before anything else, and its allowlist works by GPT name.
- Google's firmware and binaries are extracted on the user's own machine from the user's own factory image, and never redistributed: not in packages, not in bundles, not in CI artifacts.
- Signing keys never enter a repository or a CI system.

## 1. The model

- **One kernel for every device.** One arm64 `Image` and one set of modules, built from `linux-omarchy-mobile`, with every board's DTB side by side in the kernel tree: `gs201-cheetah.dts` today, `gs201-panther.dts`, `gs201-lynx.dts`, `gs101-oriole.dts`, `gs101-raven.dts` later. A board needs its own DTB, not its own kernel.
- **Per device, five things:**
  1. the board DTB (in the kernel);
  2. bootloader glue: the `soc_id` copies of the DTB, the board `dtbo` with its `board_id`/`board_rev`, the boot image set and header values;
  3. initramfs quirks: the storage-guard allowlist, the display trigger write, the USB gadget's name;
  4. firmware, extracted from the user's factory image by a per-device map;
  5. `omamobile-device-<codename>`, the userspace support package.
- **One descriptor per device**, `device/<codename>/device.conf`, holds the values of 2 and 3 and points at 4 and 5, so no tool carries a codename in its code.
- **One kernel source.** Releases are built from a tag on `linux-omarchy-mobile`'s published `omamobile` branch (§8).
- **Releases** ship through the signed `[omamobile]` pacman repository: a `linux-omamobile` kernel package (`Image`, modules, all DTBs), device packages that pick their DTB and write slot B through a pacman hook, and, for first installs, per-device flashable bundles.

## 2. What is cheetah-specific today

The audit behind this design (2026-10-13). "Step" names the roadmap step that removes it.

| Where | What is hard-coded | Step |
| --- | --- | --- |
| `bin/omamobile images` | DTB path `gs201-cheetah.dtb`; `soc_id` 0x9855001 and the 0x9855000 rewrite; the `cheetah-m1-overlay.dts` dtbo and `--id=0x30306 --rev=0x10000`; the vendor cmdline (`earlycon` at gs201's UART); `--os_version`/`--os_patch_level`; the vendor page size | 1 (done) |
| `bin/omamobile initramfs` | the splash size comes from `PANEL_SIZE`; C sources from the device package when it has them. The init path and the trigger write come from the descriptor | 1 (done) |
| `bin/omamobile capture` | the default capture name `cheetah-<date>` | 1 (done) |
| `bin/omamobile push`, `flash` | the partition lookup assumes the main LUN is `sda` | 1 (allowlist check and `BOOT_IMAGES` layouts done; the Pixel 6 has no `init_boot` or `vendor_kernel_boot`, [oriole NOTES](../device/oriole/NOTES.md)), 3 |
| `initramfs/init` | `probe()` when `BRINGUP_PROBE=1` and the board matches `COMPATIBLE` (watchdog and DPP reads); the main LUN `sda`. The TRIG_CON write is `SIMPLEFB_TRIG_CON`, the storage-guard allowlist `UFS_RW` (and `UFS_RW_LUNS`) and the USB product string `USB_PRODUCT`, all packed from the descriptor into that device's initramfs only | 2 (trigger, allowlist and USB name done; the rest still step 2) |
| `bin/omamobile initramfs` | the developer's `~/.ssh/*.pub` baked in as `authorized_keys` (fine for development, never for a release); `--release` leaves them out, and `tools/make-bundle` refuses to sign an initramfs that has them | 2 (done) |
| `tools/extract-vendor-firmware` | `BOARD="google,gs201-cheetah"`, `DEVICE="cheetah"`, the firmware `MAP` | 4 |
| `tools/extract-vendor-chroot`, `extract-fingerprint-vendor` | `DEVICE="cheetah"`, cheetah's file lists | 4 |
| `tools/aoc-stage` | the AoC firmware path under `vendor/google/cheetah` | bring-up tool, per plan |
| `tools/display-hz` | DECON register addresses (gs201) | bring-up tool, per plan |
| `tools/repo-build` | the default package list names `omamobile-device-cheetah` | 3 |
| `CONTRIBUTING.md` §4 `ov` helper | `gs201-cheetah.dtb`, `device/cheetah/overlays` | 2 (`bin/omamobile overlay`) |
| `packages/omamobile-modem` | `depends=(… omamobile-modem-policy)`, the virtual each device package with a modem provides (cheetah, raven, tegu, #363); only cheetah's image installs it (`ROOTFS_PACKAGES`) | 3 (done in #363 for the dependency; the images still to follow) |
| `packages/omamobile-gnss`, `-modem` | `ro.hardware=cheetah` in the chroot props | per device, with its chroot map |
| `packages/omamobile-audio` | the UCM profile `Google/cheetah/HiFi.conf`, the speaker stages | per device (audio is board tuning) |
| `packages/omamobile-device-cheetah` | `gs201_aoc_rails`, `pcie_gs201`, modprobe and udev policy | stays per device: this is what the package is for |

Bring-up tools (`*-stage`, `display-hz`, `usbc-deadman`) stay per plan: they poke one SoC's registers on purpose, and a second device gets its own copy only after its own read-only probes.

## 3. The device descriptor

`device/<codename>/device.conf`, one per device. [cheetah's](../device/cheetah/device.conf) is the reference.

**Format.** `KEY=value` or `KEY="value"` lines, comments and blank lines. No `$`, backticks, backslashes or single quotes, so it is data, not shell: `bin/omamobile` parses it line by line (it never sources it) and refuses anything else, and Python tools, the pacman hook and the initramfs can read it the same way. Lists are space-separated inside quotes.

### 3.1 Keys in use (step 1)

| Key | cheetah | Meaning |
| --- | --- | --- |
| `CODENAME` | `cheetah` | Must equal the directory name and `DEVICE` |
| `NAME` | `Pixel 7 Pro` | Marketing name, for messages and bundle READMEs, and the USB product string when `USB_PRODUCT` is unset |
| `USB_PRODUCT` | `Pixel 7 Pro (M1)` | Optional. The USB gadget's product string, packed into the initramfs as `/etc/omamobile-usb-product`; defaults to `NAME`. Printable ASCII, at most 126 characters. With neither key the init says `Omarchy Mobile` |
| `SOC` | `gs201` | SoC family |
| `COMPATIBLE` | `google,gs201-cheetah` | First DT root compatible; firmware names and the device check at install time use it |
| `PACKAGE` | `omamobile-device-cheetah` | The device's package (and, for now, where the initramfs C helpers' sources live) |
| `ROOTFS_PACKAGES` | `omamobile-audio omamobile-sensors omamobile-gnss omamobile-fingerprint omamobile-modem omamobile-modem-sit omamobile-mmd` | Optional. The board's own packages that `tools/build-rootfs` installs on top of the shared `rootfs/packages.omamobile`: ones tuned to this phone, which another device's image must not pull in. The modem stack (the runtime, the radio service and the ModemManager bridge) rides here, never in the shared list: it comes with the device that runs it |
| `INSTALL_LINK` | (unset) | Optional. `yes`: the device may be offered the install link ([INSTALL-LINK-PLAN](INSTALL-LINK-PLAN.md) §10), so `tools/build-rootfs --install-link` puts its marker in the root image; `test`: the same for a development or local image only, for the plan's runbook before any release carries the marker. Unset: no image of this device has the marker. Setting it is the maintainer's step |
| `DTB` | `exynos/google/gs201-cheetah.dtb` | Under `arch/arm64/boot/dts` in the kernel build, and under `dtbs/` in the kernel package |
| `SOC_IDS` | `b0:0x9855001 a0:0x9855000` | `label:soc_id`. The first is what the DTB is built with; each other entry is a copy with `/soc_id` rewritten. Order is the order in `dtb.img` |
| `SOC_COMPATIBLE` | (zuma: `b0-foplp:0x9865:1:0:0 b1-foplp:0x9865:1:1:0`; zumapro: `a1-ipop:0x9875:0:1:1`; gs201 IPOP, the Pixel 7a: `b0-ipop:0x9855:1:0:1`) | For a bootloader that matches the base DTB on `/soc_compatible` instead of `/soc_id` (zuma, zumapro, and gs201's IPOP package). `label:product_id:major:minor:pkg_mode`, one entry per child node: the label, upper-cased with `-` as `_`, is the node name, so each label appears once. The DTB ships once, unchanged; `images` checks that it has a `/soc_compatible` node holding exactly these children. A descriptor names exactly one of `SOC_IDS` and `SOC_COMPATIBLE`, and `tools/install-phone` checks the same |
| `DTBO_SOURCE` | `cheetah-m1-overlay.dts` | The board dtbo source beside the descriptor (GPL-2.0) |
| `DTBO_BOARD_ID`, `DTBO_BOARD_REV` | `0x30306`, `0x10000` | What ABL matches the dtbo entry on; checked against the source |
| `VENDOR_CMDLINE` | `console=tty0 earlycon=exynos4210,0x10A00000 …` | `vendor_boot` command line (kernel arguments really go in `/chosen/bootargs`) |
| `VENDOR_PAGESIZE` | `0x800` | Page size of `vendor_boot` (and `vendor_kernel_boot`, where the device has one) |
| `OS_VERSION`, `OS_PATCH_LEVEL` | `17.0.0`, `2026-07` | The `init_boot` header values (the `boot` header's, on a device without `init_boot`) |
| `AVB_FOOTERS` | (zuma, the Pixel 7a and the Pixel 7 Pro: `boot:0x4000000 init_boot:0x800000`) | Optional. For a phone whose `vbmeta_b` chains these partitions, as stock's does: libavb takes a chained partition with no AVB footer as invalid metadata, which an unlocked bootloader doesn't let through (zuma; the Pixel 7a; the Pixel 7 Pro, device/cheetah/NOTES.md 2026-10-28). A `vbmeta_b` that lists them as hash descriptors, or has verification disabled, never reads the footers. `image:partition_size`, each a `BOOT_IMAGES` entry, once; the size is the slot's partition size in bytes (stock's footer, `avbtool info_image`, or `fastboot getvar partition-size:<name>_b`), a multiple of 4096. `images` adds a hash footer to each, padding it to that size, signed with AOSP's test key (an unlocked bootloader accepts any key); needs `external/avb` under `SRC_DIR` (or `AVBTOOL`, `AVB_KEY`) and `openssl` |
| `AVB_ROLLBACK_INDEX`, `AVB_SECURITY_PATCH` | `1791158400`, `2026-10-05` | Required with `AVB_FOOTERS`, refused without it: stock's rollback index and `com.android.build.<image>.security_patch` from its footers. Never set the index above stock's: an index the bootloader stores locks stock's own images out of slot A. The `os_version` property is `OS_VERSION`'s major |
| `BOOT_METHOD` | `android-v4` (default when omitted) | Generic images, flash, push and installer accept only `android-v4`; other methods are refused before phone access. `ram-only` marks a probe with no persistent install support. `android-v0` (enchilada) is a header-v0 phone: `images` packs one `boot.img` for `fastboot boot`, and fastboot, flash, push and the installer refuse it |
| `PAGESIZE`, `BASE`, `KERNEL_OFFSET`, `RAMDISK_OFFSET`, `SECOND_OFFSET`, `TAGS_OFFSET` | (enchilada: `4096`, `0x00000000`, `0x00008000`, `0x01000000`, `0x00f00000`, `0x00000100`) | `android-v0` only, all required: the header-v0 page size and load offsets, numbers in decimal or lower-case hex. `images` packs the gzip `Image` with the `DTB` appended as the kernel, the initramfs as the ramdisk and `CMDLINE` as the command line. `BOOT_IMAGES` is `boot` alone and `boot_b` must be on `UFS_RW` |
| `BOOT_IMAGES` | `boot init_boot vendor_boot vendor_kernel_boot dtbo` | The images written to slot B (the `_b` suffix is added by the tools and is not configurable). `boot`, `vendor_boot` and `dtbo` are always there. Without `init_boot`, `boot` carries the empty generic ramdisk and the OS version; without `vendor_kernel_boot`, `vendor_boot` carries the DTB and the initramfs (the Pixel 6: `boot vendor_boot dtbo`) |
| `BOOT_UPDATE_AUTO_WRITE` | (unset; defaults to `yes`) | Optional: `yes` or `no`. The installer records it as `AUTO_WRITE` in `/etc/omamobile/boot-update.conf`; `no` keeps an installed development root from writing slot B through package updates. It does not change the installer's own allowed writes |
| `UFS_RW` | `boot_b … dtbo_b userdata` | The storage guard's allowlist, packed into the initramfs as `/etc/omamobile-ufs-rw`. Only slot B's boot images (`boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`) and `userdata` are accepted, `userdata` and every `BOOT_IMAGES` entry must be on it, and each name only once. The init fails closed: a missing, empty or malformed file, or any other name in it, leaves every partition read-only |
| `UFS_RW_LUNS` | (unset) | Optional. The LUNs besides `sda` that hold `UFS_RW` partitions, as disk names `sdb` to `sdz`, packed as `/etc/omamobile-ufs-rw-luns`. The init guards each as it guards `sda`: the whole-disk node removed, the disk left writable, and only its `UFS_RW` partitions left writable. Absent (every descriptor so far), malformed, or with a closed allowlist: every LUN but `sda` stays read-only at the disk level. Boot-image writers on the phone (`omamobile-boot-update`) still look only on `sda` |
| `INITRAMFS_INIT` | `/initramfs/init` | The init script. A leading `/` is relative to the repo root, so devices share one script. Any other value is relative to the descriptor |
| `INITRAMFS_ROOT_LABEL` | (unset) | Optional: `omamobile-root` enables read-only label/header checks before ext4 repair or mounting; only `e2fsck -p` statuses 0 and 1 proceed. Omitted: existing root handling, including unlabelled hand-installed roots, is unchanged |
| `INITRAMFS_ROOT_MODE` | (unset) | Optional: `persistent-development` or `ram-rescue`, requiring `INITRAMFS_ROOT_LABEL=omamobile-root`. The former skips growth and writes `/var/lib/omamobile/root-boot-pending` before handover; an installed, enabled SSH-ready helper must clear it after USB SSH is ready, or subsequent boots stay in RAM until the marker is cleared. The latter always stays in RAM. Omitted: existing handover behavior |
| `INITRAMFS_USB_RECOVERY` | (unset) | Optional: `yes` or `no`; `no` disables the separate 45-second no-host crash for an attended development/recovery policy. Omitted or `yes`: existing USB recovery behavior. Independent of root mode; retain watchdog and buttons/fastboot recovery |
| `INITRAMFS_MODULES` | (unset) | Optional: kernel modules the initramfs carries in `/lib/modules/omamobile/`, listed in load order in `/lib/modules/omamobile/order`, from this kernel build's `lib/modules/$(kernel_release)` (`omamobile modules` first). The shared init loads them before any other step, and only on a board whose first compatible is `COMPATIBLE`. For drivers the boot needs before the Arch root, such as the PMIC rails a `simple-framebuffer` waits for; `images` refuses an initramfs whose modules come from another build |
| `INITRAMFS_I2C_TOOLS` | (unset) | `1`: `i2cget` and `i2cset` (and `libi2c`) from Alpine's i2c-tools in the initramfs, for an init that talks to a chip before any driver runs (raven closes the MAX77759 USB switch). Nothing else from the package |
| `INITRAMFS_FB_WAIT` | (unset) | `1`: the init draws the early splash once `/dev/fb0` exists (waiting up to 3 s in the background) rather than at once, for a phone whose `simple-framebuffer` registers only after `INITRAMFS_MODULES` give it its rails (raven) |
| `USB_SWITCH` | `10d50000.i2c 0x25` | Optional: the MAX77759 TCPC's I2C controller and address. The init closes the chip's USB2 data switch (`USBSW_CTRL` 0x93 to 0x09) before any driver runs and keeps it closed across replugs, only on a board whose first compatible is `COMPATIBLE`, and only that register and value. Needs `INITRAMFS_I2C_TOOLS=1` (raven) |
| `SIMPLEFB_TRIG_CON` | `0x1c240030 0x3061` | This device's simplefb trigger writes, one or more `addr value` pairs on one line, packed into its initramfs next to `COMPATIBLE`. The init writes each pair only when that string is the board's first compatible. Absent or empty: no display write. Felix: `0x1c241030 0x01003061` (cover, DECON1, tear source DDI1) and `0x1c240030 0x00003061` (inner, DECON0) |
| `BRINGUP_PROBE` | `1` | Install the boot probe that reads watchdog and DPP registers. The init runs it only when the board matches `COMPATIBLE`. Absent on a phone whose panels are not driven yet |
| `PANEL_SIZE` | `1440x3120` | Portrait panel size for the early splash |
| `NV_PARTS` | `efs efs_backup modem_userdata persist modem_a modem_b` | Optional. The radio's NV and calibration partitions (GPT names) that `tools/nv-backup` copies read-only and `--check` compares with the phone: nothing on Linux may change them, so a difference fails the check (AGENTS.md section 1, MODEM-PLAN M0.1). Partition names only, each once, none on `UFS_RW`. Without it `tools/nv-backup` refuses the device |
| `NV_BACKUP_EXTRA` | `devinfo` | Optional, with `NV_PARTS`. Partitions `tools/nv-backup` copies too, for a full way back, but which change on the phone (cheetah's `devinfo` holds the bootloader's slot flags, which change after a flash, a fallback to slot A or the boot-success mark), so `--check` only reports them. Same rules as `NV_PARTS` |

A descriptor directory may also hold `kernel.config`, a config fragment that `omamobile kernel` merges after `kernel/configs/omamobile.config`, for options that would break another device (gs101's AoC interface, which excludes gs201's). It is for bring-up only: the release kernel (§4) is one build for every device, so an option stays there until its driver handles both SoCs and the line moves to the shared fragment.

The Pixel 4 (`flame`, SM8150) is a separate RAM-only first-light probe.
Its `ram-only` descriptor has empty `BOOT_IMAGES` and `UFS_RW`; build it with
`tools/build-flame-probe`, following [its runbook](../device/flame/BRINGUP-M1.md).
It does not use the generic Tensor image builder or installer.

### Optional initramfs root policy

Existing descriptors retain their current boot path. A descriptor may opt in:

- `INITRAMFS_ROOT_LABEL=omamobile-root`: inspect userdata read-only before
  repair or mounting; refuse another label or a failed ext4 header read. Only
  `e2fsck -p` statuses 0 and 1 may proceed. Old hand-installed, unlabelled roots
  are unaffected until their descriptor explicitly opts in.
- `INITRAMFS_ROOT_MODE=persistent-development`: require the label protection,
  skip initramfs growth, and persist `/var/lib/omamobile/root-boot-pending` before
  systemd handover. Install and enable the matching SSH-ready service on the
  root before using this mode; it must clear the marker after USB SSH is ready.
  Without that helper, the first boot hands over and leaves the marker behind;
  every subsequent boot stays in RAM until the marker is cleared manually.
  `ram-rescue` always stays in RAM.
- `INITRAMFS_USB_RECOVERY=no`: disable the separate 45-second no-host crash.
  Development roots may finish booting without a USB host, and a failed root
  handover must remain available in RAM instead of consuming slot retries.
  This is an explicit choice, independent of root mode; the existing recovery
  behavior remains the default. Retain a hardware-watchdog and buttons/fastboot
  recovery runbook before using a development image.

These keys change image construction only; no shipped descriptor opts in here.
Unknown root-mode files fail closed in RAM. This change has offline test evidence,
not a fresh phone boot.

`INITRAMFS_ROOT_MODE` and `INITRAMFS_USB_RECOVERY=no` are local development
settings and are refused by `initramfs --release`. With USB recovery left on,
each held boot without a USB host still spends a slot try when it restarts.
The handover marker is written only after the final storage-guard check passes.

After investigating the failure, clear the marker from the RAM rescue shell
to permit one more handover attempt. Find userdata by its partition name,
confirm it is the installed root, then mount it, remove the marker and unmount:

```sh
userdata=
for part in /sys/class/block/sd*; do
  [ -r "$part/partition" ] || continue
  if grep -qx PARTNAME=userdata "$part/uevent"; then userdata=/dev/${part##*/}; fi
done
mkdir -p /newroot
if [ -n "$userdata" ] && mount -t ext4 -o rw "$userdata" /newroot; then
  rm -f /newroot/var/lib/omamobile/root-boot-pending
  sync
  umount /newroot
fi
```

Clearing the marker does not repair the failed startup or replace the SSH-ready
helper. A further failed handover sets it again and holds subsequent boots.

### 3.2 Keys to add later

| Key | Step | Meaning |
| --- | --- | --- |
| `MAIN_LUN` | 2 | The UFS LUN holding the partition table with slot B and `userdata` (`sda`) |
| `FIRMWARE_MAP` | 4 | A file beside the descriptor (`firmware.map`: `source-in-vendor|destination` lines), replacing the arrays in `tools/extract-vendor-firmware` |
| `FACTORY_PRODUCT` | 4 | The `board=` value in the factory image's `android-info.txt`, and `fastboot getvar product`, checked before extraction and before flashing |
| `USERDATA_FS` | 4 | `ext4`; the installer grows the root to fill `userdata` on first boot |

### 3.3 Selecting a device

`DEVICE` picks the descriptor. `omamobile.conf` sets `DEVICE="${DEVICE:-cheetah}"`, so the environment wins, then `omamobile.local.conf`:

```sh
bin/omamobile images                    # cheetah
DEVICE=panther bin/omamobile images     # device/panther/device.conf
```

`DEVICE` must be a bare codename. `bin/lineage-ref` reads the same variable for its LineageOS target. Commands that don't depend on a device (`kernel`, `modules`, `modules-push`, `kexec`, `fastboot`, `kernel-shell`) don't read the descriptor. `capture` doesn't need one either, since a new device has no descriptor until after its captures.

What `bin/omamobile` checks, so a wrong descriptor fails the build rather than the phone:

- the descriptor's format, required keys and `CODENAME`;
- `UFS_RW` holds only slot B's boot images and `userdata`, each once, includes `userdata`, and covers every `BOOT_IMAGES` entry;
- `BOOT_IMAGES` names only `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot` and `dtbo`, each once, and includes `boot`, `vendor_boot` and `dtbo`;
- `initramfs` packs the checked `UFS_RW` into the image (`/etc/omamobile-ufs-rw`), so the init's allowlist is the descriptor's, and `UFS_RW_LUNS`, when set, holds only disk names `sdb` to `sdz` (`/etc/omamobile-ufs-rw-luns`);
- the DTB really is built with the first `SOC_IDS` value, and each rewrite took;
- with `SOC_COMPATIBLE` instead, the DTB has a `/soc_compatible` node holding exactly its entries (one child each, labelled or not), and a descriptor never names both keys;
- `AVB_FOOTERS` names only the device's boot images, once each, with block-aligned partition sizes, and comes with its rollback index and security patch; the footers are deterministic (the salt is the image's own hash) for a given avbtool: the footer records avbtool's version, which `images` prints, so another `external/avb` checkout gives other bytes;
- `install-phone` and `push` refuse an image larger than its `_b` partition (`fastboot getvar all`, or sysfs), and an `AVB_FOOTERS` size that is not that partition's exactly;
- the dtbo source carries `DTBO_BOARD_ID` and `DTBO_BOARD_REV`;
- `push` and `flash` refuse any image whose `_b` partition is not on the allowlist.
- `images` records the device in `images/DEVICE`, and `push`, `flash` and `tools/make-bundle` refuse images built for another device.

Step 1 changed no output for cheetah: `images` produced the same checksums for every file before and after, and `initramfs` staged an identical tree (§9).

## 4. The kernel package: `linux-omamobile`

One package for every device, in `[omamobile]`.

- **Source:** a release tag (`kernel-<YYYY.MM.DD>`) on `linux-omarchy-mobile`'s `omamobile` branch (§8), built from a clean checkout of the tag with `kernel/configs/omamobile.config` on arm64 `defconfig`.
- **Contents**, following Arch Linux ARM's layout:
  - `/usr/lib/modules/<release>/vmlinuz`: the uncompressed arm64 `Image` (the hook compresses it with lz4 for `boot.img`);
  - `/usr/lib/modules/<release>/kernel/…`, `modules.*`: stripped modules, as `bin/omamobile modules` packs them today;
  - `/usr/lib/modules/<release>/dtbs/exynos/google/*.dtb`: every Google board DTB the tree builds;
  - `/usr/lib/modules/<release>/pkgbase`: `linux-omamobile`, as Arch kernels do.
- **No initramfs, no boot images.** Those are per device and come from the device package's hook (§5).
- **Release string:** `CONFIG_LOCALVERSION` becomes `-omamobile` for release builds and `CONFIG_LOCALVERSION_AUTO` stays on. The published branch starts from a squashed commit, so no upstream tag is in its history and `setlocalversion` appends only the commit: `uname -r` is `7.3.0-rc6-omamobile-g<sha12>` (`-dirty` if the checkout isn't clean), which names the tagged commit exactly. `tools/publish-kernel` prints it, and the tag's message records it. The `-push1` suffix stays for development builds, so a development kernel can never be mistaken for a packaged one. `bin/omamobile kernel --release` makes a release build: `LOCALVERSION` `-omamobile` over the config fragment's `-omamobile-push1`, no device fragment (one kernel for every device, from the shared fragment alone), a clean tree checked before the build starts, and after it a refusal of any result that isn't `<version>-omamobile-g<sha12>` (a `-push1` or `-dirty` one). `tools/release build` runs it from the tag's worktree into the fixed release output directory, `$KERNEL_BASE/out-kernel-release`.
- **pkgver:** the version without its `-` (pacman forbids `-`), then the number of commits in the tag's history and the commit: `7.3.0rc6.r<n>.g<sha12>` (`n` from `git rev-list --count kernel-<date>`). `omamobile` only moves forward, so `n` grows from release to release and pkgver sorts upward. `pkgrel` counts packaging-only changes.
- **Build:** cross-compiled in the existing docker environment on x86 (`bin/omamobile kernel` and `modules`, unchanged), then packed by a `PKGBUILD` that only copies the build output (`arch=(aarch64)`, no compile step), so it can run on the build machine under `makepkg --config` with `CARCH=aarch64` (decided, §12.1). The compiler is the standalone AOSP clang prebuilt at a pinned revision, with pinned copies of the AOSP image scripts (`mkbootimg`, `mkdtboimg.py`, `avbtool`) (decided, §12.2).
- **Headers** (`linux-omamobile-headers`) can follow when something needs out-of-tree modules (DKMS); nothing does today.
- **Old modules:** a pacman upgrade removes the previous release's modules. The hook therefore keeps one copy of the previous `/usr/lib/modules/<release>` in `/var/lib/omamobile/boot/previous/` together with the previous slot-B images, so a rollback restores both (§5.3).

### 4.1 What exists (2026-11-01)

`packages/linux-omamobile`, tested offline (`test/all`: a fake kernel build, the refusals, the layout, and `makepkg -A` where it is installed). It packs a kernel output directory, whatever made it; for a release that is the cross build of §12 decision 1, `bin/omamobile kernel --release` (the release `LOCALVERSION` `-omamobile`, no device fragment, a clean tree) then `bin/omamobile modules`, in a clean checkout of the `kernel-<date>` tag.

- **`stage KERNEL_OUT [PREBUILT]`**, on the build machine, after `bin/omamobile kernel` and `modules` (or anything that leaves the same files): copies `include/config/kernel.release`, `arch/arm64/boot/Image`, every DTB under `arch/arm64/boot/dts/exynos/google` (`DTB_DIRS` adds others) and `modules-<release>.tar.zst` into the package's gitignored `prebuilt/`, with `SHA256SUMS`. `KERNEL_DIR` must be the clean checkout of a published release: its HEAD the release's commit and carrying a `kernel-<YYYY.MM.DD>[.N]` tag, the tag on the published repository (`LINUX_OMAMOBILE_REMOTE`, default GitHub's `linux-omarchy-mobile`) pointing at that commit, and the commit on its `omamobile` branch. `git rev-list --count HEAD` is the commit count for pkgver; the commit, the count and the tag go in `SOURCE`, which `install` requires. `stage --verify` checks a staged `prebuilt/` again (checksums, `SOURCE`, the tag on the published repository).
- **Refusals:** a development release (`-omamobile-push1-…`, or any release not of the form `<version>[-rcN]-omamobile[-<n>]-g<sha>`), a `-dirty` tree, no `KERNEL_DIR`, a `KERNEL_DIR` at another commit or with uncommitted changes, a commit without a release tag (a test build or an `omamobile-int` snapshot), a tag the published repository doesn't have or that isn't on its `omamobile`, an `Image` without arm64's header magic, a modules tarball of another release or without `modules.order`, no DTBs, and at packing time a `prebuilt/` that fails its checksums.
- **pkgver** from the staged release (`lib/pkgver`, as §4 and §7 say), **pkgrel** from the package's `version` file (packaging changes only). With nothing staged pkgver is `0` and `package()` refuses. `tools/build-packages` builds it only when named, never by default or with `--all` (so a `prebuilt/` staged for a test never reaches the daily publish, which carries `prebuilt/` directories along), and runs `stage --verify` first.
- **`/usr/share/omamobile/linux/kernel.release`** names the release the package installed, for the boot hook (§5.3), and `SOURCE` beside it the tag and commit.
- **Layout** as above. depmod's own files (`modules.dep`, `.alias`, `.symbols` …) are left out, as Arch's kernels leave them out: kmod's `60-depmod.hook` makes them on the phone, and the boot hook refuses a release without them. `options=(!strip !debug)`: makepkg must not touch the `Image` or the stripped modules. `depends=(kmod omamobile-boot-update)`.

## 5. Device package hook

The device package, not the kernel package, turns the kernel into bootable slot-B images, because only it knows the DTB, the `soc_id`s, the dtbo and the initramfs quirks. This is what `bin/omamobile images` plus `push` do today, run on the phone.

### 5.1 What the device package adds

- `/usr/share/omamobile/device.conf`: the descriptor, installed verbatim.
- `/usr/lib/omamobile/<codename>/dtbo.img`: built at package time from `DTBO_SOURCE`.
- `/usr/lib/omamobile/<codename>/initramfs.cpio.lz4`: the release initramfs (§5.2), built at package time.
- `/usr/lib/omamobile/<codename>/overlays/<name>.dtbo`: the descriptor's `DTB_OVERLAYS`, compiled at package time, which the hook applies onto the kernel package's DTB as `bin/omamobile images` applies them (cheetah's audio, camera, modem and fingerprint nodes come from these).
- `/usr/bin/omamobile-boot-update`: builds the images and writes slot B.
- `/usr/share/libalpm/hooks/90-omamobile-boot.hook`: runs it after a transaction that touches `usr/lib/modules/*/vmlinuz`, `usr/lib/modules/*/dtbs/*`, the descriptor, the dtbo, the overlays or the initramfs.
- `provides=(omamobile-device)`, `conflicts=(omamobile-device)`: exactly one device package per phone, and packages that need "some device" (`omamobile-modem` today) depend on the virtual name.
- Runtime dependencies: `dtc` (for the `soc_id` copies) and `mkbootimg` (Arch's `android-tools` ships it [I], to check; otherwise the package carries AOSP's Apache-2.0 `mkbootimg.py` with its notice, as the bootctl port does).

As built (§5.5), the tool and the hook are their own package, `omamobile-boot-update`, the same for every device, so the code that writes boot partitions exists once; the device package ships only the four kinds of data above, which `tools/stage-boot-files` prepares.

### 5.2 The release initramfs

The same Alpine-based initramfs, with release differences:

- **No developer keys.** It ships without `authorized_keys`: `bin/omamobile initramfs --release` builds it that way, and `tools/make-bundle` refuses to sign a bundle whose initramfs still holds SSH keys. The hook appends a second, tiny cpio to the ramdisk that holds the phone's own `/root/.ssh/authorized_keys` (the kernel unpacks concatenated cpio archives in order), so SSH into the initramfs keeps working for the phone's owner and nobody else. `tools/install-phone` appends the same cpio, with the same commands, to a copy of the bundle's ramdisk image (`vendor_kernel_boot`, or `vendor_boot` on a phone without one) before flashing it, so the initramfs takes the owner's key from the first boot and the hook's first run finds the image it would build already on slot B (`tests/install-phone-initramfs`). A device with `INITRAMFS_MODULES` (raven) is the exception: the hook's cpio also carries those modules, so its first run rewrites the image once.
- **No bring-up probes.** `probe()` and `omamobile.debug` stay in development builds only.
- **Quirks from the descriptor.** The trigger write is already per device: `bin/omamobile initramfs` packs `SIMPLEFB_TRIG_CON` into `/etc/omamobile-simplefb-trig` and `COMPATIBLE` beside it. The init writes the pair only when the board's first compatible string matches. A device without the trigger key gets no register write. The storage guard's allowlist is packed the same way, from `UFS_RW` into `/etc/omamobile-ufs-rw`, and the init leaves every partition read-only without a valid one. So is the USB product string (`USB_PRODUCT`, else `NAME`). Step 2 still turns the remaining quirk (`MAIN_LUN`) into a generated `/etc/omamobile/device.conf` the shared init reads at boot. That remaining step changes what boots, so it gets its own runbook and a test boot from `bin/omamobile push`; it is not a refactor.
- **Reproducible:** fixed mtimes (`SOURCE_DATE_EPOCH`), sorted file list, `cpio --reproducible`.

### 5.3 What `omamobile-boot-update` does

1. Reads `/usr/share/omamobile/device.conf` and checks that `/proc/device-tree/compatible` starts with its `COMPATIBLE`. Refuses on a mismatch: a package for one Pixel never writes another's slot B, and refuses a boot that doesn't name slot B (`androidboot.slot_suffix=_b` in `/proc/bootconfig` or `/proc/cmdline`).
2. Takes the release the installed `linux-omamobile` names (`/usr/share/omamobile/linux/kernel.release`, which its install writes), with its `vmlinuz`, and refuses if `depmod` hasn't run for it (the kernel without its modules boots without its GPU). Not the newest-looking `/usr/lib/modules/*`: release names end in a commit hash, so `sort -V` orders two releases by their hashes, and kernel-modules-hook leaves a full copy of the running release beside the new one after every upgrade.
3. Builds the images exactly as `bin/omamobile images` does (the same descriptor, the same commands; the shared code moves into one script used by both), into `/var/lib/omamobile/boot/next/`.
4. Skips the write if every image matches what slot B holds now (checksums of the partitions' leading bytes).
5. Saves slot B's current images and the running release's modules to `/var/lib/omamobile/boot/previous/`.
6. Writes each image through the same guarded path as `push`: the partition by `PARTNAME=<image>_b`, `ro` must read 0 (the storage guard decides, the hook never changes it), `dd conv=fsync`, then a read-back checksum. Any mismatch stops the hook with the error at the top of pacman's output and leaves the saved images in place for `omamobile-boot-update --rollback`.
7. **Never reboots.** The shell's update notice says a restart is needed.

**Development phones are opted out.** The hook does nothing unless `/etc/omamobile/boot-update.conf` says `AUTO_WRITE=yes`. Release installs set it; a development phone keeps `bin/omamobile push` as the only writer to slot B, so `omarchy update` never overwrites a test kernel. (As built: no package ships that file, so it can't conflict with the installer's copy or be replaced by an upgrade, and its absence means `AUTO_WRITE=no`; §12 decision 3 is taken as proposed until the maintainer says otherwise. A release image carries the file as a placeholder of comments only, which also means `AUTO_WRITE=no` until an installer fills it, §6.1.)

**What a bad kernel costs:** slot B has no A/B of its own. If the new images don't boot, ABL's retries run out and the phone falls back to stock Android on slot A, or, once the boot-success marker has marked slot B (cheetah marks it at every good boot), stops in fastboot or keeps resetting. The saved set in `/var/lib/omamobile/boot/previous/` is on `userdata`, which a phone that doesn't boot can't hand over, so recovery runs from the computer: the previous release bundle's images, or a copy of `previous/` taken off the phone after the write and before the restart (the package README says how), flashed with `bin/omamobile flash`. That is the same exposure the project has today; making it smaller (a second set of images on spare space, or a boot counter in the initramfs) is a later step.

### 5.4 Updating a phone: `omarchy update` and the Omarchy patches

`omamobile-omarchy` (in every image built from 2026-10-13 on, and a dependency of `omamobile-shell`, so `omarchy update` brings it to older phones) owns both halves; the details are in the headers of its `bin/omamobile-update` and `bin/omamobile-omarchy-patches`.

**The patches survive upgrades.** Two series families ship in the package, selected by the installed Omarchy version: `packages/omamobile-omarchy/patches/` for 4.5 (`patches/omarchy` links only to it), and `packages/omamobile-omarchy/legacy-4.0.6/` for a phone still on 4.0.6, until its next update. Fixes go in `patches/`. Its pacman hook (`95-omamobile-omarchy-patches.hook`, PostTransaction on `omarchy`, `omarchy-dev` and itself) re-applies it after every transaction that replaces Omarchy's files, and `rootfs/build-inside` runs the same tool, so image builds and upgrades take one code path. Every run starts from Omarchy's own files (checked against the package's mtree), applies the series in a scratch tree with `--fuzz=0`, verifies it by reversing it back to Omarchy's files, and only then swaps the files in. A patch whose reverse applies is already in Omarchy (a backport that landed): it is skipped and reported, and should be dropped from the series. Any other failure leaves Omarchy's files exactly as shipped, logs to `/var/log/omamobile/omarchy-patches.log` and notifies the user (the lock's PIN pad may be missing until a fixed series ships). A file that matches neither Omarchy's copy nor the last patched one was changed by something else and is never overwritten.

**The update takes the phone's path.** Patch 0012 hands `omarchy update` to `omamobile-update`, which runs Omarchy's own `omarchy-update -y` unchanged, with stand-ins first on `PATH` for the steps that don't belong on a phone. Step by step:

| Omarchy's step | On the phone |
| --- | --- |
| transcript (`script` to `/tmp/omarchy-update.log`) | kept; `omamobile-update` makes the pty itself, so one sudo timestamp covers the whole run |
| update lock, 10 GiB free-space check | kept |
| `omarchy-update-confirm` (gum) | replaced by the sheet's Update button, plus refusals: battery below 30% unless charging; `[omamobile]` not first or `[omarchy]` after Arch Linux ARM's repositories; another distribution's kernel, a bootloader, Snapper or fwupd package in the transaction; `linux-omamobile` when `omamobile-boot-update preflight` says its hook would refuse to write slot B; an update pacman can't plan (`pacman -Sup` fails, as with an unsatisfiable dependency), with pacman's reason |
| `omarchy-update-pkg-prune` (paccache) | kept |
| `omarchy-snapshot create` (Snapper, Limine's snapshot menu) | skipped: ext4 root, no Snapper (exit 127, which Omarchy takes for "Snapper absent") |
| stay-awake inhibitor | kept (the screen stays on during the update) |
| `omarchy-update-dev`, keyrings | kept |
| `pacman -Syu` with Omarchy's guard, `--overwrite /usr/share/omarchy/*` and conflict handler | kept; `[omamobile]` first, so its Mesa, Hyprland and libcamera win; the patch hook runs at the end of the transaction |
| `omarchy-migrate` | kept, but migrations that mention Limine, mkinitcpio, UKIs, efibootmgr, sbctl, Snapper, GRUB, `/boot/`, fwupd, x86 kernels or NVIDIA, ask with gum, or replace `/etc/pacman.conf`, are held: marked done for Omarchy, listed in `~/.local/state/omamobile/update/held-migrations`, and run after a review with `omamobile-update run-migration <name>` (never a `pacman.conf` one: 1791403252 puts `[omarchy]` above `[omamobile]`). If a migration still reorders the repositories some other way, `[omamobile]` is moved back to the top when Omarchy's migrate returns |
| `omarchy-hook post-update`, `omarchy-update-mise` | kept |
| `omarchy-update-aur-pkgs` (yay) | skipped: foreign packages are listed, never rebuilt on the phone |
| `omarchy-update-orphan-pkgs` (gum) | orphans listed, never removed |
| `omarchy-update-analyze-logs`, `omarchy-update-status` | kept (the initcpio check finds nothing; the status reaches the update sheet) |
| `omarchy-update-restart` (gum; "kernel updated" whenever no pacman-owned `vmlinuz` matches `uname -r`, which on the phone is always) | replaced: a restart is needed only for Omarchy's `reboot-required` or a replaced Hyprland; marked services and the shell restart as on a desktop; nothing reboots by itself |
| Update > Firmware (fwupd), Update > Config > Plymouth | hidden from the phone's menu (not part of the update) |

**The kernel** reaches a phone as `linux-omamobile` through this same update (from `omamobile-omarchy` 0.1.28): before anything is downloaded, an update that brings it asks `omamobile-boot-update preflight` (read-only), and refuses when the hook would refuse the write, so a phone never holds a kernel package its slot B doesn't match. With `AUTO_WRITE` off (a development phone) the package installs and slot B stays `bin/omamobile push`'s. The battery rule covers the write, and the hook checks the battery again itself; the result asks for a restart when slot B was written (the restart stand-in reads `/run/omamobile/boot-update.json`). Nothing reboots by itself. `OMAMOBILE_UPDATE=1 omarchy-update` runs Omarchy's flow unwrapped (an escape hatch, not for normal use); `pacman -Syu` stays blocked by Omarchy's guard.

**A channel with nothing published yet is a normal state.** When the check for updates fails and the `[omamobile]` channel's server says its index isn't there (HTTP 404; for `local`, no repository pushed yet), `omamobile-update check` reports `channel.empty` with no blocker and exit 0 ("The stable channel has no updates yet"), and an update ends as done with nothing to do. pacman needs every repository's index, so Omarchy's and Arch's updates wait with it. Any other failure (offline, a server error, a custom `Server` line answering 404) stays an error. Stable has had an index since the 2026.11.08 release, so today this is `local` before its first `tools/repo-push`, or a new server.

**The phone follows Omarchy's stable channel.** Phones installed before 2026-10-20 take `[omarchy]` from edge, which then carried 4.5.0rc1, a release candidate the phone's patches don't apply to. Switch before the next update, because the update would fetch the candidate in the same transaction as the fixed patches: `sudo sed -i 's|pkgs.omarchy.org/edge/|pkgs.omarchy.org/stable/|' /etc/pacman.conf && sudo rm -f /var/lib/pacman/sync/omarchy.db* /tmp/checkup-db-*/sync/omarchy.db*`. Removing edge's cached database matters: it is newer than stable's, so pacman's refresh keeps it and still offers the candidate. `omamobile-omarchy` 0.1.3's `omamobile-update` refuses an edge or rc `[omarchy]` and prints that line. Don't use Omarchy's own `omarchy-channel-set` or `omarchy-refresh-pacman` on the phone: they copy Omarchy's x86 `pacman.conf` and mirrorlist over the phone's (no `[omamobile]`, no Arch Linux ARM) and then upgrade everything.

**`[omamobile]` can hold Omarchy at a version the patches support.** `rootfs/packages.pinned` lists upstream package files by SHA-256 and URL (upstream's first, then our published copy, for when upstream prunes it); `tools/build-packages` adds them to `out/repo` unchanged, signed with the release key, so the daily publish carries them too; it refuses a pin with the name of a package we build, and `tools/release`'s packages stage refuses an index without every pin. `[omamobile]` comes first, so its copy wins over the newer one in `[omarchy]`: `omarchy update` (and `checkupdates`, behind the update toast) offers no newer Omarchy, and images install the pinned one. From 2026-11-06 it held `omarchy` and `omarchy-settings` at 4.0.6, because the series didn't apply to 4.5 and 4.5's migrations could install packages that replace ours (#433, #434). Since 2026-11-11 it holds them at 4.5.0-3, the version the 4.5 series, the update's stand-ins and the held migrations were checked against (a rehearsal image, then the 7 Pro's own update from 4.0.6); phones on 4.0.6 move to it at their next `omarchy update`. For a later Omarchy the maintainer moves the pins once the series is checked against it. A phone that already took the newer Omarchy keeps it: pacman doesn't downgrade on `-Syu`.

**Recovering a phone that took Omarchy 4.0.6 with `omamobile-omarchy` 0.1.0.** Its migration 1791403252 ran: `[omarchy]` sits above `[omamobile]`, Omarchy's Hyprland replaced the phone's, and no phone patch applies (no PIN pad on the lock screen, `omarchy update` no longer handed over). `omamobile-update` then refuses on the repository order, so the fix goes in by hand, over SSH or in a terminal on the phone:

1. Put `[omamobile]` back first: `sudo cp /etc/pacman.conf.bak /etc/pacman.conf` (the migration's copy from before the move; check with `grep '^\[' /etc/pacman.conf` that `[omamobile]` comes first), or move the `[omamobile]` section and its `Include` line above `[omarchy]` by hand.
2. Install the fixed series: `sudo pacman -Sy omamobile/omamobile-omarchy`. Its hook re-applies the patches; `omamobile-omarchy-patches status` should list them all applied.
3. Put back the phone's own builds that Omarchy's replaced: `sudo pacman -S $(pacman -Sl omamobile | awk '/\[installed: /{print "omamobile/" $2}')` (Hyprland at least; pacman reports a downgrade, which is expected: Omarchy's build has the higher release number).
4. Reboot, for Hyprland and the patched shell.

**The phone's update UI** is `omamobile-shell`'s `omamobile.update` sheet: a toast when Omarchy has a release (tap to open) and Update > Omarchy in the menu open it; it shows what's new, the battery and the phone patches, asks for the PIN, shows progress with the output under Details, and ends on the result. The run is a systemd user unit, so it survives the shell restart at its end.

**Kernel module trees.** Omarchy enables `kernel-modules-hook`'s `linux-modules-cleanup.service`, which at every boot moves each `/usr/lib/modules/<release>` that isn't running and that no package owns into `.old`. A phone's kernels come from `bin/omamobile push`, so a boot between a push and the reboot into the new kernel took the next kernel's modules away (seen on the Pixel 7 on 2026-10-27). `omamobile-omarchy` holds that unit off with a drop-in and runs `omamobile-modules-cleanup.timer` ten minutes after boot instead: it keeps the running release, the release `modules-push` last pushed (named in `/usr/lib/modules/.omamobile-next`), every tree pushed during this boot, every tree stamped before 2026 (a reset clock), every pacman-owned tree and the two newest others, and removes the rest (`/usr/lib/omamobile-omarchy/modules-cleanup --dry-run` shows what it would do). It never touches `.old`, which kernel-modules-hook's own tmpfiles rule empties.

Since `omamobile-omarchy` 0.1.32, `/usr/lib/modules/.omamobile-pinned` keeps additional releases indefinitely: list exact release names, one per line. Pins do not consume rollback slots and log as `keep <release>: pinned`. A missing file is empty; invalid lines and a symlinked pin file are ignored. Pin a daily kernel before experimenting with other kernels when its module tree contains hand-installed drivers. Re-sending the packaged archive cannot recover those drivers after cleanup deletes them.

`bin/omamobile modules-push` stages the incoming archive before replacing a release's tree. Each install records the sha256 of every module it installed (`.ko` or a compressed `.ko.*`, anywhere in the tree) in `.omamobile-modules.sha256`. The next push refuses, listing the paths and leaving the installed tree unchanged, only for a module missing from that manifest (added by hand) or not matching it (swapped by hand), so a rebuilt tree under the same release name installs. A tree from before the manifest is compared with the archive instead, by checksum: any installed module absent from it or different refuses, so the first push of rebuilt modules under an unchanged name onto such a tree refuses once. Generated depmod indexes and the markers are never compared. `OMAMOBILE_MODULES_REPLACE=1` explicitly permits discarding conflicting modules. `push` skips installation when the archive checksum matches `.omamobile-tarball`; a missing marker invokes the same guarded install, while a failed marker read stops the push and reports the release, expected checksum and read result.

### 5.5 What exists (2026-11-01)

`packages/omamobile-boot-update`, tested offline with a fake root (`OMAMOBILE_BOOT_ROOT`: a fake `/sys/block`, `/proc`, power supply and regular files as partitions; no root, no block device), and `tests/boot-update-parity` against `bin/omamobile`. Not run on a phone yet.

- **`omamobile-boot-update`**: `status`; `preflight [--json]` (read-only, everything a write checks before building); `build`; `write [--dry-run] [--yes]`; `rollback [--dry-run] [--yes]`; `hook` (what the pacman hook runs: nothing unless `AUTO_WRITE=yes`, then `write` without asking). A manual `write` or `rollback` asks for the codename, or needs `--yes`. `--dry-run` builds into a temporary directory, reads the partitions and prints the plan, and writes no partition and no state. One run at a time (`flock`).
- **The image builder**, `/usr/lib/omamobile-boot-update/omamobile-boot-images`: `bin/omamobile images`' commands with explicit inputs (overlays, soc_id copies or the `/soc_compatible` check, both layouts, AVB footers). Given the same inputs and tools it gives the same bytes as `bin/omamobile images`; `tests/boot-update-parity` checks that for a gs201 set with overlays and AVB footers and for a gs101 set. `bin/omamobile images` keeps its own copy of the commands for now, and the parity test keeps the two equal. The phone side of that test runs the distribution's `android-tools` where the build machine has it: Arch's 37.0.0.p1, the version Arch Linux ARM's aarch64 `extra` carries (checked 2026-11-01 in its file database: `mkbootimg`, `avbtool`, `mkdtboimg`, and `dtc` 1.8.1 with `fdtoverlay`), gives the build machine's AOSP scripts' bytes; its `mkbootimg.py` and `avbtool` are the files `tools/toolchain.lock` pins, so the phone needs no copies of its own. The descriptor is read by `lib/descriptor.sh`, `load_device`'s rules for `BOOT_METHOD=android-v4` (anything else has no update path here), with a few more checks on values the phone puts on a command line; the parity test checks that it accepts every android-v4 descriptor `bin/omamobile` accepts.
- **The ramdisk:** the device package's release initramfs as it is, unless the phone adds to it: the owner's `/root/.ssh/authorized_keys` (§5.2) and, for a device with `INITRAMFS_MODULES` (raven), those modules from the release being written, since they load only into the kernel they were built with. Both go in a second, reproducible cpio in the same lz4 stream. The shipped initramfs must pack exactly the descriptor's `UFS_RW` (the new images' storage guard is that initramfs's) and no SSH keys.
- **AVB footers:** signed with AOSP's public RSA-4096 test key, shipped in the package with its source, licence and SHA-256 (`avb/SOURCE`; the file `tools/toolchain.lock` pins) and checked by checksum before use, as `bin/omamobile images` signs them, so the phone's images match the build machine's byte for byte. Every install's bootloader is unlocked, and an unlocked bootloader accepts any key on a chained partition's footer and refuses only a missing one, so a key of the phone's own would add nothing. `AVB_KEY=` in the config replaces it.
- **The previous set** is slot B's whole partitions (an AVB footer sits at a partition's end, so a leading slice would not do) plus the module tree of the release that booted from them. It is replaced only when slot B holds a set that booted, which the kernel's write counters decide, not a release name: no slot B partition written since this boot (field 7 of `/sys/block/<lun>/<part>/stat`). A fastboot flash (the documented recovery) comes before the boot and counts as booted; this tool's own write, `bin/omamobile push` and a rollback in the same boot count as written. After such a write, or a write left incomplete, `previous/` keeps the last set that did boot; with nothing saved yet it saves slot B marked `BOOTED=no`, and a rollback says so. `rollback` checks it against its checksums, writes it back through the same checks and restores its modules (named in `.omamobile-next`, so the module cleanup keeps them). The newer `linux-omamobile` stays installed and the next kernel-related transaction would write it again; `pacman.conf` has no `Include` in `[options]` for an `IgnorePkg` drop-in, and the tool never edits `/etc/pacman.conf`, so it prints the one line that holds the package (the package README says the same).
- **Results** go to `/run/omamobile/boot-update.json`, with `kernel_changed` (slot B now holds another release than the running one); `omamobile-omarchy`'s restart stand-in reads it, so the update sheet asks for a restart when slot B was written ("kernel updated" only when the release changed, else "boot images updated"), and warns when the kernel package changed but slot B was not.
- **`preflight`**, which `omamobile-update` runs before an update that brings `linux-omamobile`, also refuses while slot B holds a set written but never booted (`current/RELEASE` is not the running kernel: pacman would remove that release's modules, and kernel-modules-hook keeps only the running one's), and when the file system lacks room for the new images, the saved set, the running release's modules and the incoming release's (taken to be the same size). `current/` is the tool's own record, so it counts only while slot B still holds its images (`current/SHA256SUMS` and `SIZES` against the partitions): after `bin/omamobile flash` (the recovery) or `push` it is stale, blocks nothing, and `status` says slot B changed outside the tool; a `rollback` that finds the saved set already in place records it.
- **`tools/stage-boot-files`** (`DEVICE=<codename> KERNEL_OUT=<build>`) prepares a device package's data in its gitignored `boot-files/`: the descriptor, `dtbo.img` (`bin/omamobile images`' commands), the compiled overlays and the release initramfs, which it refuses when it holds the builder's SSH keys, dropbear host keys or another device's allowlist. It refuses a device with `INITRAMFS_MODULES` (that initramfs belongs to one kernel release), and records in `SOURCES` the checksum of every tracked file the boot files come from (the descriptor, the dtbo source, the overlays, `initramfs/` and the package's `src/`). `omamobile-device-cheetah` (0.1.38) installs them, checked against their checksums, and **refuses to build without them**: one version is one package, whoever builds it (`OMAMOBILE_BOOT_FILES=none` builds without them on purpose, for its tests and for a development phone through `tools/phone-install-package`; never for a published package). It also refuses an initramfs whose `init` is not this tree's `INITRAMFS_INIT`, so `SOURCES` describes what built it. The initramfs is packed reproducibly (`tools/lib/initramfs-pack.sh`: sorted names with the root entry `.` first as before, owner 0:0, fixed mtimes, `cpio --reproducible`, staged under umask 022; the `cpio -itv` listing, modes and owners included, is the old packing's): two `bin/omamobile initramfs --release` builds on the build machine gave identical bytes (2026-11-02). That holds on one machine and close in time: the Alpine packages come from the live `v3.24` index (`tools/alpine-fetch.py`), the early splash from the machine's Omarchy theme unless `SPLASH_BGRA_GZ` pins it, and the small binaries from the clang found. So the boot files are staged once per device-package version, on the publish machine. `tools/build-packages` runs `tools/stage-boot-files --check` before it builds such a package; when the boot files are missing or `SOURCES` no longer matches the tree it skips that package only (the repository keeps its older version), builds and signs the rest, lists the skipped ones in `out/repo/.skipped` and exits 3 (any other failure exits 1); `tools/repo-publish` then publishes the rest and fails, so the publish timer shows it. The timer's `--remind` step runs first with its failure ignored, so the "Ready for stable" reminder still runs on such a day (copy the unit to `~/.config/systemd/user/` again to get that order). `tools/repo-publish --from-main` carries `boot-files/` into its clean tree with the `prebuilt/` directories. So after a change to one of those sources (all of `initramfs/` among them), a new device-package version needs `tools/stage-boot-files` run again before the daily publish builds it.
- **Before the first daily publish after this lands** (maintainer, once): on the build machine whose `omamobile-publish.timer` runs `tools/repo-publish --from-main` (the desktop), in the checkout it runs from, updated to the new `origin/main` (`initramfs/`, `device/cheetah/` and `packages/omamobile-device-cheetah/src` must equal it), with a scratch output directory:
  1. `DEVICE=cheetah KERNEL_OUT=<scratch> bin/omamobile initramfs --release` (downloads Alpine's minirootfs and packages once);
  2. `DEVICE=cheetah KERNEL_OUT=<scratch> tools/stage-boot-files` (needs a `dtc`, the kernel build's or the system's, and `mkdtboimg` from `tools/fetch-toolchain`);
  3. `tools/stage-boot-files --check packages/omamobile-device-cheetah/boot-files`.

  Whatever is staged there becomes `omamobile-device-cheetah` 0.1.38 for every phone. Without it the publish skips cheetah's package and fails after publishing the rest. Every other device package ships none, so on those phones the hook refuses ("does not ship its boot files yet") and `omamobile-update` refuses a kernel update where `AUTO_WRITE=yes`.
- **`tools/build-rootfs`** puts `linux-omamobile` and `omamobile-boot-update` in the root image of a device whose package ships boot files (cheetah), so a release install can take kernel updates through `omarchy update`: the package's modules replace the module tarball, and its release must be `KERNEL_OUT`'s, the one the bundle's boot images are built from. `--allow-missing linux-omamobile` falls back to the tarball for a test image and then leaves `omamobile-boot-update` out too, so the hook can't refuse every later device-package update for want of a kernel package. The hook stays off in the image; `tools/install-phone` turns it on.
- **`tools/install-phone`** writes `/etc/omamobile/boot-update.conf` with `AUTO_WRITE=yes` into the image copy (§6 step 3, §12 decision 3), and the desktop installer and the web page put the same line into the image's placeholder for it (§6.1); a development phone set up by hand has no such file.
- **mkinitcpio** is not in the root image (not in `rootfs/packages.*`, Omarchy's base list or the images' `MANIFEST`), so its own `90-mkinitcpio-install.hook` never sees `linux-omamobile`'s `vmlinuz`; `omamobile-update` refuses an update that would bring it in. If it ever were installed, that hook writes only files under `/boot` on the root file system, never a partition.
- **The first attended test** on the Pixel 7 Pro is [KERNEL-UPDATE-PLAN](../device/cheetah/KERNEL-UPDATE-PLAN.md).

## 6. Release bundles and the installer

For a first install, or to recover a phone that won't boot. One bundle per device per release.

**What exists (2026-10-13).** Built and tested offline; the first real use is [REINSTALL-RUNBOOK](../device/cheetah/REINSTALL-RUNBOOK.md):

| Piece | Where | Notes |
| --- | --- | --- |
| aarch64 packages without a phone | `tools/build-packages` | makepkg in an Arch Linux ARM container (the official tarball, MD5 and signature checked against the pinned build key, `tools/lib/alarm.sh`) under the laptop's qemu-user; signs with `keys/` into `out/repo/aarch64`. Mesa, Hyprland and libcamera take hours this way, so they're built only when named, once per version |
| The device's root image | `tools/build-rootfs`, `rootfs/` | pacstrap in that container: `rootfs/packages.base`, then Omarchy's own `install/omarchy-base.packages` (minus `rootfs/packages.omarchy-skip` and what isn't built for aarch64), then `rootfs/packages.omamobile`, the device package and the board's `ROOTFS_PACKAGES`, the `[omamobile]` repository itself, the kernel modules of the current build, and `omamobile-omarchy`'s version-selected patch family. Output `out/omamobile-rootfs-<codename>-<date>-aarch64.img.zst`, `.sha256` and a `MANIFEST` with every package version (also inside, `/usr/share/omamobile/rootfs/MANIFEST`) |
| First boot | `packages/omamobile-firstboot` | reads `/etc/omamobile/firstboot.conf` (data, never sourced), creates the user, SSH keys, ufw with SSH on `usb0`, runs Omarchy's own setup leaves (skipping four that don't fit a phone), SDDM autologin and the lock, Omarchy's and our user setup, then deletes the file |
| Growing the root | `initramfs/init` (`grow_root`) | `resize2fs` before mounting, only for a file system labelled `omamobile-root` smaller than its partition; `omamobile.noresize` skips it |
| The installer | `tools/install-phone` (the bundle's `install`) | as described below, steps 1, 3-5; the factory-image step (2) is `tools/phone-provision` after the first boot instead |
| The bundle | `tools/make-bundle` | `out/bundle/omamobile-<codename>-<date>/` as below, `SHA256SUMS.sig` from `keys/` |
| Per-phone data | `tools/phone-provision` | the extract tools on the user's factory image, pushed over USB SSH, plus the phone's own backup (modem board id and NV checksums, camera data, settings, home screens, fingerprint state only with `--fingerprint`); the bundle carries it and its tools in `tools/` |

Decisions taken in building it: the device packages are **installed** in the image, not only cached (a first boot without a package step has one less way to fail); the image's `[omarchy]` is Omarchy's **stable** channel (from 2026-10-20; before that edge was the only one with aarch64 builds of `omarchy`, `omarchy-settings` and `quickshell`, and edge then moved to 4.5.0rc1, which the phone's patches don't apply to); the image is per device (decided, §12.6; its `MANIFEST` names the device, and the installer refuses a mismatch).

Root image filenames include the device so two devices can share a version without overwriting each other. Builds use separate temporary directories and refuse a concurrent build of the same device/version in the same output directory. Compression and smoke checks finish before replacing the published files. `--local NAME` still uses `out/NAME/repo` and writes images under `out/NAME/`; use `--rootfs` to select one there. Independent package snapshots also need separate `ALARM_CACHE` directories (§10). Repository-mode installation and bundling select only images whose root `MANIFEST` matches the device, including older filenames.

The design:

```
omamobile-<codename>-<version>/
  README.txt                        what it is, what it touches, how to go back to stock
  INSTALL.md                        the install guide (docs/INSTALL.md)
  install                           the one-command installer (bash, laptop side)
  tools/                            phone-provision and what it runs (phone-ssh, extract-*),
                                    and nv-backup, the read-only radio backup it needs, so
                                    provisioning needs no checkout of the repository
  device.conf                       the descriptor the images were built from
  images/boot.img init_boot.img vendor_boot.img vendor_kernel_boot.img dtbo.img
  MANIFEST                          kernel release, package versions, both repositories' commits
  manifest.json                     the same as data, with the install checks (below)
  SHA256SUMS  SHA256SUMS.sig        checksums of everything above, signed with the release key
omamobile-rootfs-<codename>-<version>-aarch64.img.zst
  .sha256 .MANIFEST
omamobile-<codename>-<version>.tar  the one-file download: the two entries above, side by side
  .sha256 .sha256.sig               its SHA-256, signed with the release key
```

**The one-file download** (`tools/lib/bundle-tar.sh`, written by `tools/make-bundle` after signing) is an uncompressed tar of the bundle directory and the root image's three files, so unpacking it gives the layout `install` expects. It is deterministic: GNU format, names sorted, owner and group 0, every mtime the release date at 00:00 UTC (or `SOURCE_DATE_EPOCH`), modes 644 and 755. Uncompressed, because the root image is zstd already and the boot images don't shrink. It holds `SHA256SUMS.sig`, so no checksum inside the bundle can cover it; its `.tar.sha256` (one `sha256sum` line) carries its own detached signature by the release key instead, made the same way as `SHA256SUMS.sig`. `latest.json` names it too, but only as a pointer. A user checks the download with `sha256sum -c`, and `install` checks the signed `SHA256SUMS` inside it as for any bundle. Users run `bash install`, not `./install`: files downloaded one by one over HTTP lose their execute bit (the tar keeps it).

**The device's root image** is an ext4 Arch Linux ARM root with Omarchy, the `[omamobile]` repository configured and its keyring, `omamobile-shell`, the device package installed and the matching kernel modules. It is built by `pacstrap` in an aarch64 container. It contains no Google file. Its size is a few GB, flashed sparse; the first boot grows it to the whole `userdata` partition (`resize2fs` in the initramfs, before mounting).

The bundle's signed `SHA256SUMS` covers its `MANIFEST`, which names the exact root image and its SHA256 digest. The installer checks the selected image's name and bytes against that signed record before contacting the phone; changing the separate `.sha256` cannot authorize a replacement. Bundles use their own checked boot images; `--images` overrides are for repository mode. `--unsigned` remains available for development bundles, which use the root image's `.sha256` check.

**`install`** (`tools/install-phone`), run on the laptop with the phone in fastboot:

1. Checks the bundle's signature and checksums, and that `fastboot getvar product` is this bundle's codename, the bootloader is unlocked, and both slots carry the same bootloader version. Any doubt stops it.
2. Asks for the user's factory zip, checks its `board=`, and runs the device's firmware and chroot extraction on the laptop.
3. Makes a **local copy** of the root image and writes into it, with `debugfs -w` (no root needed): the extracted firmware, the user's SSH public key, `/etc/omamobile/boot-update.conf` with `AUTO_WRITE=yes`, and a first-boot marker naming the device package to install. The same key goes into a local copy of the ramdisk image's initramfs, as the boot hook appends it (§5.2), and that copy is what step 5 flashes. Nothing extracted leaves the laptop except into the user's own phone.
4. Shows exactly what it will write (`BOOT_IMAGES` with `_b`, and `userdata`), says that `userdata` is erased (stock Android needs a factory reset if it is ever booted again), and waits for the user to type the codename.
5. Runs only `fastboot flash <image>_b images/<image>.img` for each `BOOT_IMAGES` entry (the ramdisk image from its copy, step 3), `fastboot flash userdata <root image>`, `fastboot --set-active=b` and `fastboot reboot`. The partition names come from the descriptor and are checked against its `UFS_RW` again; the script has no code path for any other partition, no `-w`, no `--slot`, no `flashing` command.
6. On first boot, `omamobile-setup-system` installs the device package named by the marker (from the package cache, offline) and reminds the user to take the read-only backup of `efs`, `efs_backup`, `modem_userdata`, `persist` and `modem_a/b` ([MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) M0.1) before any radio work. `tools/nv-backup DIR` (in the bundle's `tools/`) takes it over USB SSH: the partitions from the descriptor's `NV_PARTS` and `NV_BACKUP_EXTRA`, found by `PARTNAME`, refused unless every one is found once, read-only and unmounted, each copied with `dd`, read again on the phone and compared, into a directory of mode 700 with files of mode 600; `--check DIR` compares the phone with it later.

`bin/omamobile flash` stays the developer's tool; `install` is for everyone else and is deliberately narrower.

**Ready for a web flasher and a desktop installer** (decided, §12.7; to build before the first release). The bundle carries `manifest.json`, covered by the signed `SHA256SUMS`: format version, release version, codename, product name, every file with its path, size and SHA-256, the kernel release and both commits, the release's URLs, and the install checks as data (the expected `fastboot getvar product`, unlocked bootloader, both bootloader slots on the same version, each `BOOT_IMAGES` entry flashed only to `<image>_b` with its expected size, `userdata` with the root image, then `--set-active=b` and reboot, and nothing else). `install` reads those checks too, so every installer enforces one set of rules. A root image built for the install link (`tools/build-rootfs --install-link`) adds `install_link: {"protocol": N}`, the protocol its daemon speaks, read from the image's MANIFEST ([INSTALL-LINK-PLAN](INSTALL-LINK-PLAN.md) §3.3); other bundles have no such key.

**Hosting** (decided, §12.7): bundles and root images live on our own server next to `[omamobile]` (`pkgs.omamobile.org/releases/<codename>/<version>/`, with a per-device "latest stable" index and CORS headers), because a root image (about 2.7 GB) is over GitHub's per-file limit; the GitHub Release for `release-<date>` carries the notes and the links. No Google firmware is ever hosted, in a bundle or anywhere else: every installer extracts it from the user's own factory image on the user's machine.

- **Layout.** `releases/<codename>/<version>/` holds the bundle directory's files (so `base_url` plus a `manifest.json` path is that file) and, beside them, the root image with its `.sha256` and `.MANIFEST` (so `base_url` plus `root_image.name` is the root image) and the one-file `omamobile-<codename>-<version>.tar` with its `.tar.sha256` and `.tar.sha256.sig`. `releases/<codename>/latest.json` names the current version, its `base_url`, `manifest.json`'s URL and SHA-256, and the `.tar`'s URL, size and SHA-256 (`bundle_tar`, `bundle_tar_size`, `bundle_tar_sha256`). It is only a pointer: the release is trusted through the signed `SHA256SUMS`, never through `latest.json`.
- **Upload:** `tools/release-upload out/bundle/omamobile-<codename>-<version>` (maintainer only; `--dry-run` first). It checks the bundle locally first: the release key's signature on `SHA256SUMS` (checked against this repository's `omamobile-keyring`, not the bundle's own key), every checksum, `manifest.json` against the bundle, the root image and the server path, and the `.tar`: its `.tar.sha256` signed by the release key, the tar matching it, and every member byte for byte the bundle file or root image file it stands for, with nothing else in it. Then it uploads into `releases/<codename>/.<version>.partial` (a rerun resumes an interrupted upload), checks the files there with `sha256sum`, and renames the directory to `<version>` in one step. It never overwrites a published version. Last, it reads every file back over HTTPS, checking sizes and SHA-256 (the root image and the `.tar` by size; `--full` hashes them too). `--latest` then points `latest.json` at the release (files before the index), and won't go back to an older version without `--allow-older`. `--verify-only` checks a published version again. It uses `tools/repo-publish`'s server settings (`OMAMOBILE_PKGS_HOST`, `_PORT`, `_PATH`).
- **Server:** `tools/server/releases-nginx.sh`, run once by the maintainer with sudo on the server, adds a `location ^~ /releases/` to the `pkgs.omamobile.org` vhost. The vhost already serves `/releases/` as plain files: a missing file is a 404, and byte ranges and `Content-Length` work. The script adds `Access-Control-Allow-Origin: *` with the exposed range headers and an answer to `OPTIONS` preflights, `Cross-Origin-Resource-Policy: cross-origin`, MIME types for `.json`, `.zst`, `.img`, `.sig` and `.sha256`, no gzip (so sizes stay exact), a year's immutable cache on version directories (but not on their 404s), `no-cache` on `latest.json`, a 403 for the upload's staging directories, and the security-headers snippet in every location. It does a dry run first, `nginx -t`, a verified reload and live checks, and it rolls back on any failure (`revert` undoes it).
- **Bandwidth:** each install downloads about 2.8 GB (a 2.7 GB root image plus about 80 MB of boot images, from the `.tar` or file by file; the `.tar` doubles the storage a release takes on the server, not the transfer), so 1 TB of transfer is about 350 installs. GitHub's per-file limit is 2 GiB, so a root image there would have to be split and joined again, which a browser flasher and the signed manifest would both have to know about. Our own server stays the one source; check the VPS plan's monthly transfer allowance before announcing a release.

### 6.1 Placeholders for the owner's answers (decided 2026-11-13)

`install` writes the owner's answers into a local copy of the root image with `debugfs` (step 3). The desktop installer and the web page can't: they stream the root image to the phone, unpacked from zstd and cut into sparse pieces as it arrives, and they have no ext4 writer and no local copy (the web page has no file-system tools at all). So the root image keeps a place for each file they need, and the signed manifest says where it is. The maintainer chose this on 2026-11-13 so that a phone installed by the desktop installer or the web page starts into a working account, ahead of the install link ([INSTALL-LINK-PLAN](INSTALL-LINK-PLAN.md)), which will carry the answers later without any placeholder.

- **In the image** (`rootfs/placeholders make`, from `rootfs/build-inside` before `mkfs.ext4 -d`): `/etc/omamobile/firstboot.conf` (mode 0600) and `/etc/omamobile/boot-update.conf` (mode 0644), root-owned, each exactly 4096 bytes: one block of the file system. Each holds comment lines and then one comment line of spaces up to its last byte, a newline. Every reader of the two files skips comments, so a phone whose installer left them as they are reads no answers (`omamobile-firstboot` does nothing, from 0.1.6) and `AUTO_WRITE=no`, as when the files are absent.
- **Where they are** (`rootfs/placeholders locate`, after `mkfs.ext4`): the root image's `MANIFEST` gets one line per placeholder, `answers placeholder: PATH offset BYTES length 4096 sha256 HEX`, the byte offset of the file's one data block in the raw (unpacked) image and the SHA-256 of the placeholder's bytes. `locate` refuses a file that can't be swapped in place: anything but one 4096-byte block, inode flags other than extents (inline data, encryption, verity, data journalling), another owner or mode, or a file system with 1 KiB blocks. These lines are not in the copy of the `MANIFEST` inside the image, which is written before `mkfs.ext4`. `tests/rootfs-smoke` checks the placeholders are still the markers and are where the `MANIFEST` says.
- **In the signed manifest** (`tools/bundle-manifest`): `root_image.placeholders`, a list of `{path, offset, length, sha256}` from those lines, each checked against the image (unpacked up to the last one) before it is written. An image from before the placeholders gives an empty list. The key is additive: format stays 1; `install` and older desktop installers ignore it and flash the image as it is, which leaves the placeholders holding no answers.
- **What an installer does:** after the root image's bytes are verified against the signed manifest, it replaces exactly those bytes in the unpacked stream, and only after the bytes it replaces match the recorded SHA-256. `firstboot.conf` gets the owner's answers in `omamobile-firstboot`'s format (the password only as its sha512-crypt hash, made on the owner's computer; the Wi-Fi passphrase as typed, as `install` writes it); `boot-update.conf` gets `AUTO_WRITE=` with the descriptor's `BOOT_UPDATE_AUTO_WRITE` (default `yes`), as `install` writes it. Each is padded to 4096 bytes the same way: the text, each line ending in a newline, then a comment line `#` and spaces up to the last byte, which is a newline (with two bytes left `#\n`, with one `\n`, with none nothing). `rootfs/placeholders fill PATH FILE` is the reference. No file-system metadata changes: ext4's `metadata_csum` covers metadata and not file data, and the image has no data journalling, so `e2fsck -fn` finds the result clean (`tests/rootfs-placeholders`, on a small real image).
- **What is not in a placeholder:** the owner's SSH key (`/root/.ssh/authorized_keys` and slot B's initramfs). The desktop installer and the web page don't ask for one; `omamobile-firstboot` treats `SSH_KEY` as optional, and `sshd` takes keys only, so such a phone has no SSH until the owner adds a key.
- **`install`** writes its own files over the placeholders, as before (`debugfs` `rm` then `write`).

### Development installer policy

A device descriptor may set `BOOT_UPDATE_AUTO_WRITE=no` to keep an installed
development root from writing boot images through package updates. The
installer records that value in `/etc/omamobile/boot-update.conf`; descriptors
that omit the key retain `AUTO_WRITE=yes`. Only `yes` and `no` are accepted.
This does not change which partitions the installer itself writes.

Use `tools/install-phone --serial <SERIAL>` to pin the phone for an install;
this is the installer's existing command-line check, independent of the
automatic boot-update policy.

## 7. Versions and tags

| Thing | Version | Where it is recorded |
| --- | --- | --- |
| Kernel | `uname -r`: `7.3.0-rc6-omamobile-g<sha12>`; pkgver `7.3.0rc6.r<n>.g<sha12>` (§4) | annotated tag `kernel-<YYYY.MM.DD>` (`.1`, `.2` for a respin) on `omamobile` in linux-omarchy-mobile; the scheme is a proposal for the maintainer to confirm |
| Packages | each package's `version` file, bumped in the commit that changes it (CONTRIBUTING §6.3) | the package |
| Descriptor | none of its own; a change to it is a device-package change and bumps that package | `omamobile-device-<codename>` |
| Bundle | calendar version `<YYYY.MM.DD>`, with `.1`, `.2` for a respin the same day | tag `release-<YYYY.MM.DD>` in this repository, covering every device released that day; `MANIFEST` pins the kernel tag, every package version and both commits |

A release never contains a kernel or package that isn't in `[omamobile]` at the same moment, so a bundle install and `omarchy update` meet at the same versions. The first release is `2026.MM.DD`, labelled "developer preview", for the Pixel 7 Pro only (§12.12).

## 8. The kernel branches

- **`omamobile` on GitHub is the one source of the release kernel.** It starts from a squashed commit holding the upstream tag's tree (v7.3-rc6), with every commit after it unchanged, and it only moves forward: pull requests and release tags point at its commit ids, so nothing rewrites or force-pushes it.
- **Community pull requests** land there after review (`tools/kernel-pr-check`, CI), as rebase merges.
- **The maintainer's work** lands as a fast-forward: a local release branch (say `omamobile-release`) built on the current `github/omamobile` from curated, signed-off commits of the subsystem branches, tested on the phone, then pushed with `tools/publish-kernel omamobile-release`, or opened as a pull request like anyone else's. The tool fetches the published tip first and pushes only a fast-forward. If something was merged meanwhile, it stops: rebase the release branch (`git rebase FETCH_HEAD omamobile-release`), test what changed, and run it again. It also refuses merge commits, and any commit without the author's human `Signed-off-by` or with an AI's, as well as identifiers and blobs (`tools/kernel-pr-check`'s commit and policy checks). A `Co-Authored-By` trailer is only a warning, there and on pull requests (the maintainer's decision, 2026-11-02): kernel commits credit an AI with `Assisted-by`, but AI may assist; a human tests, verifies and signs off. `--dry-run` prints exactly what it would push.
- **A release is a tag on `omamobile`:** annotated, `kernel-<YYYY.MM.DD>` after the bundle's calendar version (§7; proposed, for the maintainer to confirm), on the commit the release kernel is built from. `tools/publish-kernel --tag kernel-<date> [omamobile-release]` creates it and pushes it with the branch in one atomic push, or alone on the published tip. A release tag never moves; a respin the same day is `kernel-<date>.1`.
- **`omamobile-int`** is a local integration and testing branch only: the subsystem branches merged, work in progress included, for test kernels. It is no longer published and is not a release source: what a release needs moves from it into the release branch as curated commits. The `omamobile-int` snapshots on GitHub (the last from 2026-10-18) are no longer updated.
- Board DTS files for new devices land in the device's topic branch first, then in `omamobile` through a pull request or the release branch.

## 9. Reproducibility and CI

**What step 1 showed.** Given the same kernel build and initramfs, `bin/omamobile images` is deterministic: two runs and the old and new code all gave identical checksums for `boot.img`, `init_boot.img`, `vendor_boot.img`, `vendor_kernel_boot.img`, `dtbo.img`, `dtb.img`, both DTB copies and `Image.lz4`. `initramfs` is deterministic in content but not in bytes: its cpio carries mtimes and inode numbers. Packed with fixed mtimes and `cpio --reproducible`, old and new code gave the same archive.

**To make whole releases reproducible:**

- Pin the build container by digest (`docker/Dockerfile` `FROM ubuntu:24.04@sha256:…`), and record the clang version in `MANIFEST`.
- Set `KBUILD_BUILD_TIMESTAMP`, `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST` and `SOURCE_DATE_EPOCH` from the tagged commit.
- Pack the initramfs with fixed mtimes, a sorted list and `cpio --reproducible`, and without `authorized_keys` (§5.2).
- Pin the Alpine minirootfs and APKs by checksum (the minirootfs is already pinned; `alpine-fetch.py` should pin the APKs too).
- The clang comes from a 400 GB LineageOS checkout today; release builds use the pinned AOSP clang prebuilt instead (decided, §12.2), which changes the kernel's bytes once, so one cheetah boot from it comes before the release kernel is built.

**CI** (GitHub Actions, or any runner with docker):

| Job | When | What |
| --- | --- | --- |
| lint | every push | `bash -n` and shellcheck on `bin/` and `tools/`, each package's `test/all`, descriptor checks for every `device/*/device.conf` |
| kernel | kernel tag, or nightly on `omamobile` | build `Image`, modules and all DTBs in the container; `dt-validate` (`CHECK_DTBS=y`) on each board DTB |
| images | after kernel | `DEVICE=<each> bin/omamobile images`; build twice and compare checksums |
| packages | release | `linux-omamobile` packed from the kernel job; aarch64 packages on an arm64 runner in an Arch Linux ARM container, or on the phone as today |
| bundle | release | bundle and root image, **unsigned** |

CI never holds the signing key and never sees a factory image. The maintainer downloads the CI artifacts, rebuilds locally and compares checksums, then signs (§10). Nothing CI produces contains a Google file.

## 10. Signing

- **The release key** (2026-10-26, `20567593566EEEE2DD8864608632C8075EB94673`) is an ed25519 primary that only certifies, with an ed25519 signing subkey that expires 2028-10-26. `tools/release-key-init` made it once, on a tmpfs: the primary's secret (passphrase-protected), its revocation certificate and the public key are kept offline by the maintainer, in a password manager, and the passphrase separately. The build machine holds only the signing subkey, without a passphrase, in `keys/gnupg.release` (with `keys/fingerprint.release`), so a scheduled publish can sign unattended. Phones trust the primary, so a lost build machine costs a subkey: revoke it and certify a new one from the offline primary, and phones keep working.
- **Renew the subkey before 2028-10-26** (`--quick-set-expire` from the offline primary, then re-export the public key into `omamobile-keyring`). An expired subkey's signatures stop verifying.
- **Releases sign with the release key** (decided, §12.4): before the first bundle, `tools/build-packages`, `tools/make-bundle` and the publish switch from `keys/gnupg` to `keys/gnupg.release`.
- **Users follow `stable`, builders and testers `development`** (decided, §12.9). Release images point `[omamobile]` at `stable` on `pkgs.omamobile.org`: the device package's `omamobile-mirrorlist` becomes that URL instead of a local `file://` path.
- **The move from the original key.** The original package key (2026-10-12, `6C84FE3D240709E70E27CC94B301F5EA62B249FE`, `keys/gnupg`) still signs packages, the database and bundles. `omamobile-keyring` 20261026 trusts both keys and is itself signed by the original, so phones accept the release key with an ordinary update. Then: switch the build tools to the release key (`keys/gnupg.release`), and once published phones have that keyring, move the original key to `omamobile-revoked`. `tools/install-phone` accepts either key's signature on a bundle until then.
- Rotation and revocation go through `omamobile-keyring`'s `omamobile-trusted` and `omamobile-revoked`, as Arch's keyring does.
- **Publishing** (`tools/repo-publish`): `pkgs.omamobile.org` has two channels, `development/aarch64` and `stable/aarch64`. `repo-publish development` builds what changed (`build-packages --all`), checks every package's checksum and signature against `omamobile-keyring`'s trusted keys, and uploads packages first, then the index, then the pruning; each channel keeps the files of the current index and of the last one before it with a different package set, also after a publish that changed nothing. `repo-publish stable` promotes development's signed files unchanged, after asking. The maintainer's laptop runs it daily from a clean `origin/main` checkout (`--from-main`, `tools/systemd/omamobile-publish.timer`), and `--remind` opens a "Ready for stable" issue when development has differed from stable for three days. Experimental phones' device packages are published to development only. The server account needs the `deployers` group.
- Never commit, paste or upload a key, a passphrase or `keys/`. CI gets no key.
- **Contributors' builds** (review lesson L-7). A port's own packages are signed with a local key that only that contributor's machine trusts, and everything lands under `out/<codename>/` and `keys/<codename>/`, never in the maintainer's `keys/` or `out/repo`:

  ```sh
  tools/local-key-init panther                       # once: keys/panther/{gnupg,fingerprint,public.asc}
  tools/fetch-published out/panther/published        # pkgs.omamobile.org/development, each signature checked
  tools/build-packages --local panther --import out/panther/published packages/omamobile-device-panther
  KERNEL_OUT=... tools/build-rootfs --local panther  # out/panther/omamobile-rootfs-*.img.zst
  ```

  `tools/fetch-published` accepts the index and each package only when a key in `omamobile-keyring`'s `omamobile-trusted`, and not in `omamobile-revoked`, signed it, and each package only when it matches the signed index's SHA-256. `build-packages --local` keeps those packages' own `.sig` files, so only what it builds and the repository index carry the local key. The build image of `build-packages` and `build-rootfs --local` trusts the local key too (`ALARM_LOCAL_KEY`, locally signed in that image only). **The phone does not:** after the first boot, `pacman` refuses that `[omamobile]` index until the owner adds the key by hand (`pacman-key --add public.asc`, then `pacman-key --lsign-key <fingerprint>`). No package carries a contributor's key.

## 11. Release checklist

Per release, in order. Stop at any failed step. `tools/release` runs the checklist as stages (`tools/release --version <date> <stage>`, `--dry-run` to only check and print, `status` for where a release stands); the stage for each step is in brackets. Each stage checks what the ones before it recorded in `out/release/<date>/state`, and the steps that need the maintainer (a push, the signing key, the server, the attended install) stop and print the exact command.

1. **Kernel** [`kernel`]: a release branch on the current `github/omamobile` holds everything the release needs as curated, signed-off commits (§8); `tools/kernel-pr-check --build OUT --merge github/omamobile <branch>` passes; it boots on each released device, with `uname -r` and the result in that device's NOTES (the stage looks for the exact release, `<version>-omamobile-g<sha12>`, in `device/<codename>/NOTES.md` only: a plan's Expect line or a `-push1` build of the commit doesn't count).
2. **Publish and tag** [`kernel`]: `tools/publish-kernel --dry-run --tag kernel-<date> <branch>`, read what it would push, then run it without `--dry-run`. If it stops because `omamobile` moved, rebase, test what changed, and repeat. The stage checks that the annotated tag is on GitHub's `omamobile` and that the release worktree (`$KERNEL_BASE/wt-release`) is exactly that commit and clean.
3. **Build** [`build`] the kernel from the tag in the pinned container with the pinned clang (the stage checks `toolchain.txt`), release `LOCALVERSION` (`bin/omamobile kernel --release`), into the fixed `$KERNEL_BASE/out-kernel-release` (byte-identical builds need the same paths; the stage refuses that directory when it holds anything but a release build); stage `linux-omamobile` from it (`packages/linux-omamobile/stage`, §4).
4. **Images** [`images`] for every device: `DEVICE=<codename> bin/omamobile initramfs --release`, then `DEVICE=<codename> bin/omamobile images`, twice, checksums equal; then the device package's boot files (§5), for a device package whose `install` ships them (`OMAMOBILE_BOOT_FILES`): kept when `tools/stage-boot-files --check` finds them current, since the device package in `out/repo` was built from them, and then the boot images are built from their initramfs, so the bundle boots the bytes every phone's hook writes later; when they are stale, staged again only for a new device-package version (the stage asks for the bump when `out/repo` already has the current one), then `tools/build-packages packages/<device package>`.
5. **Packages** [`packages`]: every changed package has a bumped `version`, its `test/all` passes, `tools/build-packages` builds and signs them and the database on the laptop (`tools/repo-build` on a phone only as an opt-in shortcut). The stage checks that `out/repo` is signed by the release key, holds every package the image installs at this checkout's version, and that development publishes exactly it (`tools/repo-publish --no-build development`); it pins that index. `linux-omamobile` and `omamobile-boot-update` are among the image's packages (decision 10); `tools/build-packages` builds `linux-omamobile` only when named (`tools/build-packages packages/linux-omamobile`), and the stage checks the device package carries the staged boot files' initramfs. When the packages are built and published on a build host (the machine the daily publish runs on) and the release is cut on another, `tools/build-host-sync` carries the files between them instead of hand copies (host from `BUILD_HOST` in `omamobile.local.conf`, `--dry-run` prints every command): `push` after the `images` stage sends the staged `linux-omamobile` prebuilt and the device packages' boot files, checked on both sides (`packages/linux-omamobile/stage --verify`, `tools/stage-boot-files --check`) and refused unless the build host's checkout is the same clean commit; `command` prints the one build-and-publish command for it, with the `DOCKER_HOST` its publish service runs with resolved (a unit's `%t` means nothing to a shell); `pull` before this stage brings its `out/repo` and `out/publish` back and puts them in place only when their indexes are the ones `pkgs.omamobile.org` serves, `out/repo` is development's index, and every listed package matches. Then [`rootfs`] the root image on the stable channel from the pinned index, carrying both, and [`bundle`] the signed bundle.
6. **Test install** [`test-install`] on each released device, attended (this gates the release, §12.10): the signed bundle's `install` on a phone whose stock slot A and backups are known good; first boot, device package installed, `omarchy update` clean (the installed phone follows stable, and `promote` comes after this step: the stage first asks the server whether stable has an index, and with none, which can only be before the first release to a server, prints the one-time promotion of the pinned index and stops; later releases find the previous release there), then a package-hook kernel update and a reboot into it; on the Pixel 7 Pro with a SIM, after `tools/phone-provision` and the carrier settings, the modem stack comes up at boot on its own ([MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) M4.6b) and the phone registers. The bundle is signed before this step, so the bytes tested are the bytes released; `test-install --passed "<uname -r>"` records it.
7. **Identifiers** [`identifiers`]: grep the bundle, the root image's file list, `MANIFEST` and the release notes for MAC addresses (`[0-9a-f]{2}(:[0-9a-f]{2}){5}`), serial numbers, SSIDs and account names; confirm no file from a factory image is in any artifact. The stage also reads the root image's `/etc`, `/root` and our own directories and the release initramfs; serials, SSIDs and account names come from a private list outside the repository (`~/.config/omamobile/release-identifiers`, one per line). `tools/release scan FILE...` checks any file the same way.
8. **Verify** [`verify`] the release's signature from a clean keyring: the bundle's `SHA256SUMS.sig` by the release key, every file against `SHA256SUMS`, and the root image against the SHA-256 the signed `MANIFEST` names (the bundle stage signed it; the root image needs no signature of its own, since the installer and `manifest.json` authorise it only through that signed record); upload [`upload`] them to `pkgs.omamobile.org/releases/` (§6) with `tools/release-upload --dry-run out/bundle/omamobile-<codename>-<date>`, then `tools/release-upload --full --latest out/bundle/omamobile-<codename>-<date>`, files before the index (`upload --done` reads them back with `--verify-only`); promote [`promote`] the release's packages to `stable`: `tools/repo-publish stable --expect-index <sha256>` promotes development's index and files unchanged, signatures included, and only if development's index is still the one the release was built and tested from.
9. **Tag** [`tag`] `release-<date>` in this repository; publish the repository, the bundles and the notes (`docs/release-notes/<date>.md`: what changed, the kernel tag and its `uname -r`, known issues, how to go back to stock).

## 12. Decisions (2026-11-01)

Decided by the maintainer for the first release; the reasoning is in the release decisions brief.

1. **Kernel package build:** cross-compiled in the x86 container and packed on the build machine (the desktop that runs the daily publish), from a release tag (§4).
2. **Release toolchain:** the standalone AOSP clang prebuilt at a pinned revision, plus pinned copies of the AOSP image scripts; the container pinned by digest (§4, §9).
3. **Boot hook on development phones:** opt-in. Only a release installer writes `AUTO_WRITE=yes` (`tools/install-phone`, and from 2026-11-13 the desktop installer and the web page through the image's placeholder, §6.1); `bin/omamobile push` stays the development path (§5.3).
4. **Signing key:** the release key (2026-10-26); every tool switches to it before the first bundle, then the original key is retired (§10).
5. **CI host for aarch64 packages:** the desktop for the first release; GitHub's arm64 runners later, for unsigned rebuild-and-compare (§9).
6. **Root image:** one per device, as built (§6).
7. **Bundle hosting:** our own server next to `[omamobile]`; the GitHub Release carries the notes and links. The bundle's signed JSON manifest carries every file's size and hash and the install checks as data, ready for a web flasher and a desktop installer. No Google firmware is ever hosted (§6).
8. **Second device:** panther, after the first release.
9. **Channels:** users on `stable`, builders and testers on `development`; the device package's `omamobile-mirrorlist` becomes the server URL (§10).
10. **Kernel updates:** the release waits until `linux-omamobile` and `omamobile-boot-update` pass checklist step 6 on the Pixel 7 Pro (install, a package-hook kernel update, a reboot into it).
11. **Kernel source:** the release kernel is a tag on the published `omamobile` branch, after the curated commits land there by fast-forward, so the source is public before any kernel binary ships (§8).
12. **Name, version and gates:** calendar version `2026.MM.DD` (§7), labelled "developer preview", Pixel 7 Pro only. Modem ships as a known issue; Suspend gates the release only if the shell's auto-sleep ships on. *Amended 2026-11-03:* the modem works on the tested network (calls, texts, data; [DEVICES](DEVICES.md)), so it ships on by default: `omamobile-device-cheetah` 0.1.43 enables `omamobile-modem-boot.target` with a vendor wants link, the stack's packages are in cheetah's `ROOTFS_PACKAGES`, and the modem unit is skipped until `tools/phone-provision` has run. The carrier settings stay a known issue until #373 (set by hand in `modem-sit.conf`).
