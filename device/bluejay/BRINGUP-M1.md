<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a: first-boot gates

Status (2026-11-05): first Linux boot passed. The M1 initramfs runs from B
on `7.3.0-rc6-omamobile-push1-g29a7a9326bf0`; USB SSH and guarded UFS
passed, as did more than nine minutes in the same boot. Before that test,
the approved matching stock OTA completed with recovery status 0 and
fastboot reported stock A active, successful and not unbootable. The
applied stock OTA is `CP3A.261005.002.A1`. Private backups are verified.
The Omarchy desktop has not been installed. Facts: [NOTES.md](NOTES.md).

## Sources and outputs

- Mobile worktree: `~/src/omarchy-mobile-bluejay-20261105`, branch
  `bringup/bluejay-20261105`, based on `80ef270`.
- Kernel worktree: `~/android/mainline/wt-bluejay-m1-20261105`, branch
  `omamobile-bluejay-m1-20261105`, published base `29a7a9326bf0`.
- Kernel output: `~/android/mainline/out-bluejay-m1-20261105`.
- Kernel C and DT sources are unchanged. Build the shared config with
  `W=1`, `Image.gz` and `exynos/google/gs101-bluejay.dtb`. The M1 initramfs
  uses the shared init, no board-specific register writes or probes, and
  only `boot_b vendor_boot_b dtbo_b userdata` on its storage allowlist.
- Captures, serial selection, stock packages, checksums and private
  recovery instructions stay outside this repository. Never put their
  identifying contents or vendor images into a commit.

## R0: current facts (complete; read-only, low risk)

Serial-pin adb and fastboot, assert `product=bluejay`, and capture Android
state before unlocking. The owner approved the reboot, data erasure and
unlock, and confirmed the bootloader prompt physically. Fastboot now
reports `unlocked=yes`, `current-slot=b`. A's contradictory successful /
unbootable flags remain unchanged. Stop on a product or serial mismatch.
Rollback: none for reads; the approved unlock's data wipe is irreversible.

## R1: establish stock recovery (complete; high impact)

Prepare Google's full `bluejay` OTA for `CP3A.261005.002.A1` on the laptop.
Check the complete file's SHA-256 against Google's published download
table, its ZIP metadata's `pre-device`, resulting fingerprint and security
patch, and its payload partition inventory. Do not use a partial download.

The package contains bootloader, modem, vbmeta and system firmware as well
as boot images. A recovery sideload is therefore outside the project's
Linux slot-B writer allowlist. **Ask the owner for this specific stock
recovery exception before entering the recovery/sideload sequence.** A
general acceptance of erasing user data is not this exception.

The owner explicitly approved the exact recovery / signed OTA / stock A
verification / return-to-bootloader sequence. The full OTA checksum
matched Google's published SHA-256, its metadata matched the captured
phone fingerprint, and the serial-pinned sideload completed. This
approval covers this stock recovery operation, not a later Linux flash.

Results (2026-11-05): adb sideload exited 0 with `Total xfer: 2.00x`.
Owner-provided photos show package verification result 0 and **Install
from ADB completed with status 0**. Earlier metadata mount / formatting
and missing `tune2fs` messages are visible; they did not prevent recovery
from reporting successful installation. The approved stock reboot returned
the phone as a normal Android MTP USB device; debugging was unavailable
after the wipe. After the owner returned it to fastboot, serial-pinned
queries report `current-slot=a`, `slot-successful:a=yes`,
`slot-unbootable:a=no`; B is also successful and not unbootable. The
bootloader remains unlocked at `bluejay-17.0-15681480`. Slot-A success is
the bootloader's reported evidence; no post-OTA Android properties were
read, and no explicit Welcome-screen confirmation was received. The
installed package's device and fingerprint were verified before sideload.

After approval, use the captured serial and stock B's recovery, with the
owner at the buttons. Expected sequence: recovery menu, Apply update from
ADB, exact verified package via `adb -s <serial> sideload <OTA>`, successful
verification and installation, then owner-approved stock boot. Record the
actual resulting slot rather than assuming recovery updated A.

Pass: stock Android boots on A, reports the expected build, and fastboot
subsequently reports A bootable and successful. Inspect B's state too.
Stop: recovery rejects the signature, build, timestamp or device; an
installation error; unexpected slot; or no working A boot. Do not bypass
verification, downgrade, run a factory flash script or manually write
protected firmware partitions. Keep the working B images until A is
verified. Rollback: remain in recovery/fastboot and diagnose with the
matching stock package available; a partially applied update has no
assumed automatic rollback. Do not relock the bootloader for development.

## R2: offline images (complete; not permission to flash)

Once the kernel build finishes, build this device's boot images with the
project tool and the explicit kernel source/output above. Verify the
bluejay compatible, both gs101 SoC revision entries, MP1.0 overlay IDs,
image sizes and boot AVB footer/index against the stock capture. Run the
storage-guard checks and device-tree validation. Keep build logs and
record warnings; a completed build alone is not a phone test.

Results (2026-11-05): `W=1` built
`7.3.0-rc6-omamobile-push1-g29a7a9326bf0` and the bluejay DTB with no
compiler errors. The unchanged published sources produced 1,145 warning
lines, 1,138 of them initializer overrides; this is not a warning-free
build. No kernel source patch was made, so checkpatch has no patch to
review. Google board-schema validation reported no diagnostics (limited
to `arm/google.yaml`, not all subsystem bindings). Storage-guard tests
passed 24 checks; image-layout tests passed 37.

The shared initramfs and all three images built. Offline preflight checked
both SoC revision IDs, bluejay compatible and symbols, MP1.0 overlay IDs,
vendor header and command line without earlycon, boot footer rollback
index `1791158400` / security patch `2026-10-05`, and image sizes against
the actual partition sizes. The packed allowlist has exactly the expected
four names, with no board MMIO trigger, probe or USB-switch file. Image
hashes and build receipts remain in the private output directory. No
phone test or flash is implied by these results.

## R3: first Linux boot (complete, explicitly approved)

Use only `DEVICE=bluejay bin/omamobile flash` with the explicit validated
M1 output. It writes B's three images and activates/reboots B. The owner
must approve that concrete image set and be present for physical recovery.
Do not install a root filesystem or reuse another phone's data yet.

Expect USB NCM/ACM and SSH to the initramfs at `172.16.42.1` within about a
minute. Display refresh is not enabled, so a stationary bootloader logo
is not the pass/fail signal. Verify uptime beyond 120 seconds, watchdog
handover and storage-guard state. Stop if USB is absent after three minutes
or there is a reset loop; do not keep retrying or change two things.

Rollback: owner-assisted Volume Down + Power to fastboot, then approved
selection and boot of the previously verified stock A. With no verified A,
R3 must not run. Risk: high, first custom kernel on this board.

Results (2026-11-05): all three writes returned OKAY; SSH answered at
uptime 2.57 seconds. Compatible and native kernel release matched bluejay
and the validated image set. USB is configured/high-speed. Both cluster
watchdogs report reset disabled. At 565.6 seconds SSH still answered in
the same boot, without panic, oops, UFS error-handler or guard-failure
signatures. All flashed image prefixes matched the original image hashes
on readback. Slot A stayed read-only. The same-boot storage guard verified
every protected partition, with `/dev/sda` absent as intended. No custom
driver load, display-register access or additional reboot followed.

## R4: capture and backups before subsystem work (backups complete; memory audit open)

If R3 passes, capture the live FDT, dmesg, memory map, interrupts, native
kernel release and read-only partition state. Verify reserved memory.
Read and checksum this phone's own calibration / modem partitions into a
private backup before radio, PMIC, AoC or Trusty experiments. No such
backup exists from the unprivileged stock capture. No Wi-Fi, GPU, touch,
audio, charging or suspend capability is claimed by these first-boot gates.

Results: live FDT, kernel logs, iomem, interrupts, modules, mounts, USB,
watchdog and block guard state were captured privately. The six required
calibration / modem partitions plus stock A's three boot images and
`devinfo` were read without mounting or changing flags, each matched by
exact size and remote-before / local-copy / remote-after SHA-256. All
protected partitions remained read-only. Twelve native static reserved
regions match exclusions in iomem. The static stock-reference comparison
has unresolved differences: [MEMORY-PLAN](MEMORY-PLAN.md). Do not enable
new hardware until that gate is resolved. B's boot-success flags have not
been changed by this test.
