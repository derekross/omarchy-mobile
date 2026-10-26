<!-- SPDX-License-Identifier: MIT -->
# Pixel 4 (flame): first light

Status (2026-10-19): RAM-only first light.
Kernel source: [postmarketOS SM8150 Linux][kernel], tag `v7.0.0-sm8150`,
release `7.0.0-sm8150`; tested package `linux-postmarketos-qcom-sm8150-7.0.0-r0`.
This probe consumes that package's kernel/DTB/modules; it does not build a
kernel worktree or maintain an integration branch. Outputs go to the explicit
`--out` directory supplied to `tools/build-flame-probe`.

USB NCM, ACM, SSH and all-read-only UFS are verified. Separate RAM-resident
Arch/Omarchy experiments reached a software-rendered desktop with physical
touch. They are evidence for later work, not payloads shipped by this builder.
Persistent installation support is deferred. The development handset no
longer has a stock boot slot; see its current state below. On a stock phone,
preserve the working Android slot until an independent recovery path exists.
The `ram-only` descriptor is refused by generic image/install/flash/push tools.

## Development handset state (2026-10-19)

**`boot_b` currently holds experimental U-Boot, not stock Android.** Separate
development work erased and reflashed it after the RAM-only tests below.
That loader reads a Linux image from an experimental Arch root on
`userdata`, which has also replaced Android's data filesystem. Neither the
installed loader nor that native root is shipped by this PR or builder.

Slot A is marked unbootable; unchanged `boot_a` and `dtbo_a` image hashes
do not make it a verified fallback. This handset has **no independently
verified bootable stock slot**. Verified stock boot/DTBO backups and the
matching factory image are retained off-device. Android recovery depends
on Android fastboot, restoring the stock images and resetting the replaced
Android data filesystem; it is not an automatic fallback to stock B.
Spontaneous resets and a pixelated display after restart have occurred in
the separate native setup and remain unresolved. Do not infer native boot
reliability from this RAM-probe result.

## Goal

Boot a kernel and an SSH server entirely from RAM, with every UFS disk and
partition read-only. Establish a recovery path and take calibration backups
before enabling more hardware. An Arch root and the Omarchy shell come after
this gate; no claim of working Wi-Fi follows from another distribution's tests.

## Sources and facts

- [V, stock ADB, 2026-10-18 initial inspection] `ro.product.device=flame`,
  `ro.board.platform=msmnile`,
  stock Android `TP1A.221005.002.B2`, kernel
  `4.14.276-g6ef255005cea-ab9062920`, bootloader `c2f2-0.5-8906123`.
- [V, stock ADB, 2026-10-18 initial inspection] Bootloader unlocked
  (`ro.boot.flash.locked=0`); Android was running from **B** at that time.
  This is historical stock state, not the current fallback described above.
- [V, stock ADB] `boot_a/b`, `dtbo_a/b`, `userdata` exist; there is no
  `vendor_boot`, `init_boot`, or `vendor_kernel_boot`. SoC ID is 339,
  revision 2.2; board revision MP1.0, stock DTBO index 11.
- [V, source] The original image builder emits header-v4 images and uses
  Tensor's `soc_id` DT property. Flame uses the separate RAM-only U-Boot payload
  builder rather than this Tensor image path. See `tools/build-flame-probe`.
- [V, source] The shared `initramfs/init` includes a writable-partition
  allowlist and optional Tensor probes. This RAM probe has no writable
  exceptions or root handoff, and keeps a single separate init/guard. Native
  integration with the shared init belongs in the deferred install work.
- [V, source] The [SM8150 kernel v7.0.0-sm8150][kernel] includes
  `arch/arm64/boot/dts/qcom/sm8150-google-flame.dts` (BSD-3-Clause), with
  `compatible = "google,floral-sm8150", "qcom,sm8150"`, Qualcomm board IDs,
  a 1080x2280 panel, UFS, USB, WCN3990, and Adreno 640 descriptions.
- [V, source] The [postmarketOS device package][devicepkg] uses this kernel
  with U-Boot and EFI. Its [device page][wiki] reports display, touch, GPU,
  Wi-Fi, Bluetooth, battery and USB networking. These are **upstream reports**,
  not results from this Omarchy Mobile port.
- [V, source] Andrew Gigena's [U-Boot flame branch][uboot], commit
  `0c42ac323aea8368b0624e405ded403351022df2`, has a flame DTS and configuration.
  For a RAM-only probe, omit its storage-scan preboot, start USB fastboot,
  disable fastboot flashing, USB mass storage, and on-disk EFI capsules, and
  keep its environment volatile. Do not install this development bootloader.

[kernel]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/tree/v7.0.0-sm8150
[devicepkg]: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/main/device/testing/device-google-flame
[wiki]: https://wiki.postmarketos.org/wiki/Google_Pixel_4_(google-flame)
[uboot]: https://gitlab.com/andrewgigena/u-boot/-/tree/andrew/google-flame

## Design

Use a separate first-light init with no Android mounts, no rootfs handoff,
no partition growth, no firmware services, and no register probes. The
kernel's built-in UFS/USB support brings up USB NCM and ACM. Only its matching
`qcom-wdt` module is added, with a keeper feeding a 30-second hardware
watchdog every five seconds.
The storage guard sets whole disks and partitions read-only and watches for
late enumeration. The SSH key is supplied locally and is never committed.
An initial guard failure exits PID 1, triggering the same `panic=10` reset
as a failed mount, before any services start. The reset follows the phone's
installed boot path; it returns to stock only if that path still holds stock.

Use `fastboot boot`, which downloads an image to RAM. Keep stock boot and
DTBO images intact. A temporary U-Boot stage is required with the tested
bootloader: Android's fastboot rejects the direct mainline images.
Never run the existing installer with a renamed cheetah descriptor.

### Building the Linux probe

`tools/build-flame-probe` takes an SM8150 kernel build (or the matching kernel
package's files), AOSP's `mkbootimg.py` with its `gki/` helpers, and the
developer's public SSH key. It builds an aarch64 Alpine initramfs inside
Docker, checks the flame DTB and kernel/module release, and packs a boot
image for **U-Boot's** fastboot server. It does not access a phone.

```sh
tools/build-flame-probe \
  --kernel /path/to/Image.gz \
  --dtb /path/to/sm8150-google-flame.dtb \
  --watchdog-module /path/to/qcom-wdt.ko.zst \
  --ssh-key /path/to/developer.pub \
  --mkbootimg /path/to/system/tools/mkbootimg/mkbootimg.py \
  --out /path/to/fresh-output
```

The output is local development material: its initramfs contains that public
key. No proprietary firmware is included. The tested kernel package is
`linux-postmarketos-qcom-sm8150-7.0.0-r0` from the project's official mirror;
the source recipe is [pmaports][recipe]. The builder needs UFS, USB, NCM,
ACM and devtmpfs built in. It disables remote processors and forces the USB
controller into peripheral mode in its copy of the DTB.

[recipe]: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/tree/main/device/testing/linux-postmarketos-qcom-sm8150

### Temporary U-Boot stage

Use the U-Boot commit linked above, built with `qcom_defconfig`,
`qcom-phone.config`, and `sm8150-google-flame.config`. Build in a separate
output directory. For this probe:

- use a volatile environment (`CONFIG_ENV_IS_NOWHERE=y`);
- disable `FASTBOOT_FLASH`, `CMD_USB_MASS_STORAGE`,
  `EFI_CAPSULE_ON_DISK`, `EFI_CAPSULE_FIRMWARE_RAW`, and
  `EFI_RUNTIME_UPDATE_CAPSULE`;
- replace `preboot=scsi scan; usb start` with `preboot=` in
  `board/qualcomm/qcom-phone.env`, and `bootcmd` with `bootcmd=run fastboot`;
- in its flame DTB, set `/soc@0/usb@a6f8800/usb@a600000/dr_mode` to
  `peripheral` and remove `usb-role-switch`. Without this change, the
  tested build reached its display but did not enumerate USB;
- gzip `u-boot-nodtb.bin`, append that flame DTB, and use AOSP mkbootimg
  with header v0, base 0, kernel offset 0x8000 and page size 4096.

After the gate checks below, boot that image from Android fastboot using
`fastboot boot /path/to/u-boot.img`. U-Boot then enumerates as a USB download
gadget with manufacturer `U-Boot`. Check that
`fastboot getvar version-bootloader` contains `U-Boot`; the generic fastboot
protocol version alone does not identify the bootloader. **Confirm that
U-Boot is running before booting the Linux probe** with
`fastboot boot /path/to/fresh-output/boot.img`. Enumeration can take longer
than three seconds; wait for the gadget before sending the next image.

U-Boot's Android image parser treats `0x10008000` and `0x11000000` as the
default kernel and ramdisk addresses, relocating them to RAM at runtime.
The builder deliberately emits those sentinels. ABL's base=0 layout instead
asks U-Boot to load the kernel at physical 0x8000, and the tested phone
returned to stock Android after a watchdog reset. These two image formats
are not interchangeable.

## Gates and rollback

These gates require a working stock boot path before starting. The current
development handset does not meet that prerequisite; its separate native
setup must not be used as evidence that the stock rollback below is available.

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Inspect stock over ADB | Exact model, build, unlock state and partition names recorded privately | Wrong product or locked bootloader | None: read-only | Low |
| Download matching factory image | SHA-256 equals Google's published checksum; stock `boot.img` and `dtbo.img` available locally | Missing image or mismatch | None: host-only | Low |
| Build and inspect probe | Boot image fits 64 MiB; correct flame DTB; init has no storage writes; local SSH key installed | Wrong DTB or any unintended write path | Delete host output | Low |
| Reboot to Android fastboot | `product=flame`, unlocked, exact active slot recorded | Device no longer responds | Volume Down + Power to fastboot; Start for stock | Low |
| Temporary boot | Mainline kernel and NCM/ACM enumerate; fresh SSH succeeds | Hang, no USB, or unexplained reset | Power held about 30 s, then Volume Down + Power for Android fastboot; Start for stock | Medium |
| Read-only checks | Kernel release, storage guard flags, USB state and uptime recorded | Any UFS disk or partition still writable | Stop all bring-up; return to stock | Low |
| Private backups | `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, and boot/DTBO images read and hashed off-repo | Any partition unreadable or checksum fails | Return to stock; no hardware enablement | Low |

No persistent write is part of this first-light gate. For a later install,
restore and independently verify stock slot A or an equivalent recovery
path before considering any slot B overwrite; prepare a separate gated runbook.
Stock Android changes modem NV; take a fresh backup after each stock boot.

## Results

2026-10-18, kernel `7.0.0-sm8150`:

- Stock inspection passed. Battery was 100% and 27.3 C. Captures are private
  and outside this repository.
- The first U-Boot stage reached the screen. Forcing its USB controller into
  peripheral mode restored its USB fastboot and console access on macOS.
- Direct Linux images (header v2/gzip, header v0/appended DTB, and v2/lz4)
  were rejected by Android fastboot. Do not respond by flashing them.
- The corrected U-Boot handoff reached Linux, NCM, ACM and key-only SSH.
  `uname -r` reported `7.0.0-sm8150`; UDC state was `configured`. macOS used
  its existing NCM and ACM drivers.
- All **74** detected UFS disks/partitions reported `ro=1`. There are no
  writable exceptions, and no Android filesystem was mounted.
- One long raw backup transfer lost the USB connection just short of 32 MiB.
  That partial file was not accepted as a backup. Replugging the cable
  restored SSH to the same running kernel. Compressed 4 MiB chunks then
  transferred all backups successfully; Linux remained up for over ten
  minutes. USB stability under sustained raw transfers remains open.
- Twelve private partition backups were verified against hashes computed
  on the phone: `persist`, `modemst1/2`, `fsg`, `fsc`, `devinfo`, `boot_a/b`,
  `dtbo_a/b`, and `modem_a/b`. Both boot and both DTBO backups also match the
  matching Google factory image. At this RAM-probe gate both boot and DTBO
  images were unchanged; Linux RAM probes wrote no UFS data. Later native
  installation experiments are outside this PR and this builder.
- The kernel registered `msmdrmfb` at 1080x2280, 32 bpp, stride 4352; a
  framebuffer capture shows the live Linux console. The boot log contains
  DSI/SMMU errors and a clock warning, so accelerated rendering and reliable
  modesetting are not yet claimed by that console test. GPU firmware was
  absent at first light; a later guarded probe verified FD640 hardware EGL
  contexts with Mesa 26.2.5. See [GPU-PLAN.md](GPU-PLAN.md).
- The matching `qcom_wdt` module loaded in RAM, and the watchdog keeper ran
  with a 5-second feed and a 30-second timeout. Deliberate expiry was not
  tested. A second RAM boot verified the keeper started directly from
  the checked-in init and all 74 UFS nodes were protected again.
- After rechecking calibration hashes, QRTR and ath10k SNOC loaded under a
  recovery timer and an external log stream. A fresh SSH connection passed;
  the timer was canceled. No WLAN interface appeared with remote processors
  disabled. A later guarded probe started MPSS and the kernel PD mapper,
  registered `wlan0`, and scanned 27 BSS entries. Calibration hashes still
  matched after testing. Association is not verified; see
  [WIFI-PLAN.md](WIFI-PLAN.md).
- A separate development init booted an Arch/Omarchy root served by the
  computer over NFSv3. Directory reads, file creation, `fsync` and rename
  checks passed before handoff. Systemd, udev, networking and SSH started,
  and first-boot setup created the owner account. An independent SSH
  server in RAM remained available after the root handoff. This is not
  part of the checked-in first-light builder.
- That desktop attempt did not produce a usable session: Hyprland's first
  rendering faulted (see [GPU-PLAN.md](GPU-PLAN.md)), and USB access was
  later lost during the NFS workload. The phone returned to stock B.
  NFSv4 had also produced remote I/O errors. A computer-served root is
  not yet a reliable desktop test path on this setup.
- Udev's late RTC driver load set the wall clock to 1970 during Arch
  startup, after systemd had initialized it. This caused package-keyring
  time errors. Recheck time after driver loading and before provisioning;
  a correct timestamp at PID 1 startup alone is insufficient.
- In separate, out-of-tree Arch/Omarchy development work, a compressed
  SquashFS root copied into RAM, with a RAM overlay, removed
  the continuous NFS dependency. Arch systemd, Hyprland and Quickshell ran
  a usable Omarchy session. A small EGL triangle/readback test passed with
  llvmpipe; the desktop uses the same software-rendering workaround. All
  74 UFS nodes remained read-only throughout this test.
- In that separate Arch payload, a guarded `spi_geni_qcom` load again logged
  firmware-update bypass and sensing enabled. A physical tap/swipe capture
  contained 320 input events,
  including multitouch coordinates and tracking IDs. The owner unlocked
  the numeric keypad and confirmed the home screen opened.
- UFW initially failed its IPv6 rules because the packaged kernel lacked
  `xt_limit`, `xt_hl`, and `ip6t_rt`. Modules compiled from the exact running
  source/config with the matching Clang 23.1.3 loaded successfully. A
  guarded firewall restart then installed both IPv4 and IPv6 rules, and a
  fresh USB SSH login passed before its recovery timer was canceled.
  See [kernel-extra.config](kernel-extra.config); a full replacement kernel
  built with that fragment has not yet been tested.

### Recovery checks before native installation

A recovery-slot test selected slot A for a stock boot attempt. ABL
exhausted its retries, marked A unbootable and fell back to stock slot B.
Fastboot then reported A with zero retries and B successful. The exact
slot-selection command was not retained, so this is not evidence of a
successful stock A boot or proof that A was bootable beforehand. Boot A and
DTBO A hashes remained identical to their backups; no image was flashed
during this check. Selecting a slot changed boot-control state, not image
contents. At that point stock B was the only working stock slot. A later
recovery test RAM-booted the verified matching factory `boot.img` from
Android fastboot and reached stock
B with Android's boot-completed flag set. This verified that image on the
then-existing Android data. Both checks predate the native installation:
development work subsequently overwrote `boot_b` and `userdata`, as recorded
in the current-state section. The stock B fallback is no longer available.
Restoring Android now also requires a factory data reset. Keep both boot
backups and Android fastboot available for recovery; persistent installation
is not offered here. Do not use the Tensor installer on this phone.

### Host validation (2026-10-19)

`tests/all` passed its runnable tests, including main's storage-guard and USB
product tests, the unsupported-boot-method and flame guard tests, and the
Tensor image-layout and failed-flash regressions. The flame test covers an
initial guard failure exiting with status 1 rather than sleeping before
watchdog/USB startup. This is a host fixture test; a deliberate guard failure
and panic reset have not been exercised on the phone. The provisioning
container integration and root-image smoke test were skipped because their
test image and a completed Omarchy root image were not present. ShellCheck
passed for the new scripts.

## Separate native-root development path (2026-10-19)

The default descriptor and first-light tool above remain RAM-only. The explicit
`FLAME_NATIVE=1` profile, runtime package, source-pinned loader build and
separate userdata/boot-B gates are documented in
[native/README.md](native/README.md), with bounded handset results and
host-only publication changes in [native/RESULTS.md](native/RESULTS.md).
This does not establish a release installer or a healthy stock A fallback.
