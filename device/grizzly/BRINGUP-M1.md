<!-- SPDX-License-Identifier: MIT -->
# Grizzly M1 bring-up plan

The test phone has November D1 on stock A. Earlier B trials reached
authenticated USB SSH in RAM rescue. Two RAM-root trials also reached
systemd with zero SCSI disks. The UFS diagnostic stops at PHY readiness.
See the [D1 recovery and trial record](NOTES.md#november-d1-recovery-and-first-light-checks)
and the [kernel provenance and fixtures](bringup/README.md). Coordinate with
the October-build Grizzly in [#26](https://github.com/derekross/omamobile/issues/26).

| Step | Pass | Stop | Return |
| --- | --- | --- | --- |
| Review sources and fixture | Publish the matching source branch and confirm its release and commit. Reproduce the five image checks, B0 DT selection, AVB signatures and ABL handoff bounds. Verify stock A and its Recovery route, the matching D1 bootloaders and the attended return timer. | Source mismatch, failed validation, uncertain stock recovery or nobody available to catch Fastboot. | Leave the phone on stock A. |
| Stage the diagnostic | The serial-pinned stage-only writer acknowledges the five B images. A remains active and successful. The 64 MiB `vendor_boot_b` readback matches the entire 8,192-byte payload. | Any write or readback fails, snapshot update is active, or slot and bootloader checks disagree. | Leave A selected. Keep B inactive until staging is complete and verified. |
| Run the v29 diagnostic once | Capture `cpm-before-handshake`, both HSIO-S acquisition readings, both SGIA IRQ readings, prep/core vote provenance and final PHY/TOP results. The guard records a skip when the wrapper has yet to report on. Verify the log after stock A boots. | The NV/PMIC ordering is unresolved, the return path is lost, or a block device appears. | Catch Fastboot with Volume Down after the timed warm restart, select A, then boot stock. Preserve the console before considering a repeat. |
| Review first storage-visible rescue | Use a Grizzly descriptor and the shared initramfs. Inspect the exact archive for the shared storage guard, RAM rescue and a closed write allowlist. Match the actual stock UFS reference clock and keep raw SCSI, BSG and RPMB exposure disabled. | Open write allowlist, unresolved clock attribute, unexplained LUN mapping, or any path that hands off to an installed userspace. | Keep the storage-visible fixture offline. Retain the link-only diagnostic and stock A. |
| Back up calibration and radio partitions | The first storage-visible boot runs Grizzly RAM rescue. Verify expected partitions by unique GPT label, `ro=1` and unmounted state. The first reads are through `tools/nv-backup`. Complete the backup and check its hashes in a private off-repo directory. Size the attended return window for the reads and verification pass. | Missing or ambiguous labels, any writable or mounted target, a failed hash, or not enough time to finish. | Keep files private, return to stock A, and defer further CPM, PMIC and charger experiments until a verified backup exists. |
| Install Grizzly userspace | A Grizzly-specific root and boot policy pass their own review and tested recovery procedure. | A Cheetah device package, boot-success unit or AoC service in the storage-visible root, or an unverified recovery path. | Keep Grizzly in RAM rescue or return to stock A. |

v29 includes the existing PMIC decoupling writes. Resolve the order of
the read-only NV backup and any further PMIC or CPM hardware work
before deciding whether to run that fixture. The prior UFS trials
stalled before they could expose storage.

## Staging and return sequence used for D1

These commands describe the attended workflow used by the trials.
The review and validation gates above apply before another B boot.
`GRIZZLY_SERIAL` selects the phone, `GRIZZLY_M1_DIR` holds the reviewed
bundle's `images/` directory, and `VERIFIED_SLOT_B_BOOTLOADER` comes from
an independent observation of B's bootloader. D1 reports the version of
the executing slot. Keep the raw captures and partition readback private.

```sh
adb -s "$GRIZZLY_SERIAL" reboot bootloader
fastboot -s "$GRIZZLY_SERIAL" getvar all > "$CAPTURE/fastboot-before.txt" 2>&1
DEVICE=grizzly KERNEL_OUT="$GRIZZLY_M1_DIR" FASTBOOT_SERIAL="$GRIZZLY_SERIAL" \
    bin/omamobile flash --stage-only --bootloader-slots-match "$VERIFIED_SLOT_B_BOOTLOADER"
fastboot -s "$GRIZZLY_SERIAL" fetch vendor_boot_b "$CAPTURE/vendor_boot_b.readback.img"
fastboot -s "$GRIZZLY_SERIAL" getvar all > "$CAPTURE/fastboot-staged.txt" 2>&1
printf 'version-bootloader:b: %s\n' "$VERIFIED_SLOT_B_BOOTLOADER" >> "$CAPTURE/fastboot-staged.txt"
python3 device/grizzly/bringup/check-slot-b.py \
    "$GRIZZLY_M1_DIR/images" "$GRIZZLY_M1_DIR/images/SHA256SUMS" \
    --fastboot-vars "$CAPTURE/fastboot-staged.txt" --require-healthy-a \
    --vendor-boot-readback "$CAPTURE/vendor_boot_b.readback.img"
```

Once staging passes and the live reader and return plan are ready, select
B, confirm it, and issue one boot request.

```sh
fastboot -s "$GRIZZLY_SERIAL" --set-active=b
fastboot -s "$GRIZZLY_SERIAL" getvar current-slot
fastboot -s "$GRIZZLY_SERIAL" reboot
```

Catch Fastboot with Volume Down at the scheduled restart. Confirm that the
bootloader is back, select A and confirm that selection. Release Volume
Down before the stock boot request.

```sh
fastboot -s "$GRIZZLY_SERIAL" --set-active=a
fastboot -s "$GRIZZLY_SERIAL" getvar current-slot
fastboot -s "$GRIZZLY_SERIAL" reboot
```

On Android, verify `sys.boot_completed=1`, `ro.boot.slot_suffix=_a`,
`ro.build.id=CP4A.261105.040.D1`, enforcing verity and the original
stock VBMeta digest. Capture the matching tagged console in ramoops
and DropBox before another trial.

```sh
adb -s "$GRIZZLY_SERIAL" exec-out cat /sys/fs/pstore/console-ramoops-0
adb -s "$GRIZZLY_SERIAL" shell dumpsys dropbox --print SYSTEM_LAST_KMSG
```

## Storage and reference clock

Stock D1's UFS `mphy_ref_clk` selects LPCM8 clock 1 at 38.4 MHz. The
v29 packed DT connects `mphy-ref` to the same clock. The external
device REFCLK and the device attribute remain unmeasured. The
diagnostic checks the configured M-PHY rate and stops at link/Hibern8.
A future full-discovery path
must verify the device's existing `bRefClkFreq` before allowing the
generic UFS core to write a mismatching attribute.

The exact v29 ramdisk already carries the shared initramfs in RAM rescue
and omits its write allowlist. The normal Android-v4 descriptor packaging
path emits the configured boot-image and userdata allowlist. The first
storage-visible Grizzly fixture must preserve the shared guard's
all-read-only behavior. Verify this in the finished ramdisk and then
verify every relevant LUN on the phone before reading data. The
`tools/nv-backup` descriptor requires a verified Grizzly NV inventory.
D1's partition list and vendor labels support
`persist nvdata nvram protect_f protect_s modemdp modem_a modem_b`
as the initial NV inventory. Copy `devinfo` separately because the
slot flags can change. Confirm each label and its size in Grizzly
rescue. Allow at least 3,235 MiB of private host storage and a separate
on-phone checksum pass. The v29 90-second window is insufficient
for this backup.
