<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Mi 8 (dipper): RAM-only first light


**Status (2026-11-21):** a RAM/NFS overlay with the candidate Dipper CPU0
idle service and enablement link injected completed firstboot and reached the
Omarchy lock screen under Hyprland on shared Mesa FD630. CPU0's
`little-rail-power-collapse` state was disabled; CPU1 remained enabled. A
65-second DPMS-off/on cycle left SSH responsive and restored the compositor
capture. I then verified, built and installed signed package 0.1.3 on that
overlay root; pacman owns both new files and the service remains active. The
post-install smoke found display, GPU, STMFTS and buttons; all 91 UFS flags
stayed read-only. The root and six new kernel error lines remain; root on
userdata, a clean kernel report, physical panel viewing and gesture delivery
are not established. See [NOTES.md] for evidence limits.

**Status (2026-11-18):** a fresh Omarchy 4.5.0-3 NFS root runs on the phone
with `omamobile-omarchy 0.1.45`. Two phone smoke runs confirmed the USB link,
display connector and all UFS disks read-only. Both found no render node, no
multitouch input, and no Hyprland or shell session. Firstboot with the 0.1.8
service-enable change reached user setup, but UFW failed because the NFS root
had modules for a different kernel release. Matching modules are now in the
disposable root; a phone reboot and smoke test with them are pending. The NFS
journal later showed the graphical target and SDDM session starting, without
visual confirmation or a captured renderer. A rescue framebuffer was
unblanked, but that result was also not visually confirmed. Exact evidence
and limits are in [NOTES.md]. The earlier status saying no persistent image
was flashed is historical: a RAM-rescue image was written to the single
`boot` partition on 2026-11-19, as detailed below. The descriptor and
installer still have no Dipper install path.

**Status (2026-11-15):** a RAM-only `fastboot boot` reached the Omarchy 4.5.0-3 NFS root with `omamobile-omarchy 0.1.45`. Its journal records the handoff, the UFS guard setting all six whole-disk nodes and all 85 partitions read-only, both packed-DTB `removed-region` nodes, the initramfs guard, and the `qcom_wdt` device; direct UFS `ro` readback was not captured. In a later 20-second-watchdog NFS retry, `/proc/iomem` showed `0x85fc0000–0x8a8fffff` reserved and `networkctl status usb0` reported routable/configured. Systemd was still `initializing`; it did not reach multi-user, and `tools/phone-smoke`, watchdog feeder state, direct UFS `ro` readback and the visible screen remain unverified. The phone later returned to the existing ext4 root. The 60-second setting was rejected by the driver, so the package now uses 30 seconds (driver maximum 31); a fresh boot with that packaged setting remains unverified. The diagnostic root used volatile journals and temporary early-SSH wiring; those changes are not in the package. No flash or explicit UFS-write command was issued. Image hash, source commits and evidence limits are in [NOTES.md].

**Previous status (2026-11-14):** a fresh rootfs was built with Omarchy 4.5.0-3 and `omamobile-omarchy 0.1.45`; all build-time rootfs smoke checks passed. The Dipper kernel and EA8074 panel module also built. A RAM-only NFS test did not reach that new root: a later SSH session reported the existing kernel (`g2a318a96ae9d-dirty`) and an `ext4` root. `reboot-to bootloader` returned the phone to fastboot. The test image showed no firstboot log or created test account. `/proc/iomem`, UFS read-only flags, `tools/phone-smoke`, `networkctl status usb0` and the visible desktop were not captured. No flash command was issued; incidental userdata writes by the existing ext4 system could not be ruled out. Earlier RAM boots and test limits are recorded in [NOTES.md].

A retry of image `d7bdde5e35b5c78a5878ebf4df28effefca35bed9a26c39098f473278d233ead` was accepted by `fastboot boot`, but the host saw no ARP reply and a 10-second capture contained no SSH, RPC or NFS packets. The root handoff remains unverified. The exported image was checked on the host: it has Omarchy 4.5.0-3, `omamobile-omarchy 0.1.45`, `omamobile-device-dipper 0.1.0`, all seven runtime dependencies and 375 package-owned `/usr/lib/systemd/system/*.service` files; the three old unowned units and WLAN helper are absent. No phone-side `phone-smoke`, `networkctl status usb0`, `/proc/iomem`, UFS flags or display observation could be collected from this boot. No flash or explicit UFS-write command was issued; with the running root unknown, incidental writes cannot be ruled out.

Before that retry, the 84-partition read-only backup was revalidated and `userdata` was recaptured to a private off-repository file archive from an ext4 mount using `ro,noload`. GNU tar preserved numeric ownership, modes, sparse files, ACLs and xattrs; zstd integrity and a full tar listing passed. This supersedes the older possibly stale userdata archive. It is a file-level, non-atomic archive, not a raw partition image.

A separate RAM NFS-root run used image `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7` with the rebased #503 init. BusyBox `mount` switched to the test NFS root; all six disk flags and all 85 partition flags were `ro=1`. Systemd reached the multi-user target with `RuntimeWatchdogSec=60s`, and SSH remained available. `reboot-to bootloader` returned the phone to fastboot. The exported root was a generic Arch base; this did not test the Omarchy desktop or link-loss recovery. Full results are in [NOTES.md].
The FTS5 driver from [touch #219] is merged into linux-omarchy-mobile. The
Dipper board DTS from [DTS #220] is merged too (2026-11-11), and the EA8074
panel driver is under review in [panel #218].
The EA8074 panel test is recorded in [NOTES.md]. The FTS5 touchscreen
registered and physical taps produced touch events on 2026-11-13; see
[NOTES.md]. End-to-end touch use in a visible Omarchy session remains
unverified.
On 2026-11-09, a guarded RAM boot was used to capture all 84 GPT partitions
other than `userdata` (the phone has no `super`); source and compressed-image
checksums passed. The separate live userdata archive also passed its checksum
and zstd integrity checks. It is a file-level, non-atomic archive, not a raw
partition image.

This is a RAM-only bring-up. Dipper has one OS `boot` partition and no alternate
OS slot. The descriptor sets `BOOT_METHOD=ram-only`, the builder makes only a
`fastboot boot` image, and the initramfs keeps every UFS partition read-only.
There is no supported flash, push, installer or persistent update path here.

## Recovery and safe boot

Each gate below must pass before proceeding. Set `FASTBOOT_SERIAL` to the
intended handset's serial, `BACKUP_CHECKSUMS` to the locally held stock
partition manifest, and `USERDATA_BACKUP_CHECKSUMS` to the private userdata
archive's checksum file. Do not boot if either backup is missing or fails.

1. **Backup gate** — Expect: the verified backup of the installed system's 84
   non-userdata GPT partitions, both checksum manifests, and the userdata archive
   are available off-device. Pass: both
   `sha256sum -c "$BACKUP_CHECKSUMS"` and
   `sha256sum -c "$USERDATA_BACKUP_CHECKSUMS"` report every entry OK (run each
   from the directory containing its manifest). The userdata archive is a live
   file-level copy, not a raw partition image or an atomic snapshot. Stop: any
   missing or mismatched entry. Rollback: do not boot; there is no reviewed
   restore procedure yet, and nothing in this runbook writes UFS. Risk: an
   unverified backup cannot recover a damaged single-slot phone.
2. **Fastboot gate** — Enter fastboot with **Volume Down + Power**; the §3.1
   entry is in [CONTRIBUTING.md §3.1](../../CONTRIBUTING.md#phones-without-ab-slots).
   Run `fastboot -s "$FASTBOOT_SERIAL" getvar product` and
   `fastboot -s "$FASTBOOT_SERIAL" getvar unlocked`. Expect `dipper` and `yes`.
   Pass: exactly one device is listed, both values match, and the serial pins
   every fastboot command. Stop: absent/ambiguous device, wrong product or
   locked bootloader. Rollback: leave fastboot without writing. Risk: this
   device has no alternate OS slot.
3. **Recovery gate** — Fastboot entry uses **Volume Down + Power**; the forced
   restart is separate. On 2026-11-09, an attended test found that holding
   **Power alone for 10 seconds** restarted into Android from both installed
   Android and the Omarchy Mobile RAM kernel. Volume Down + Power then entered
   fastboot from Android. Expect: the Power-only hold restarts the phone. Pass:
   the observed procedure above is recorded and the phone can enter fastboot.
   Stop if Power alone does not restart it. Rollback: do not start a RAM boot
   until this gate passes. Risk: a hard kernel hang has not been simulated;
   recovery from one still depends on the hardware button reset working.
4. **RAM boot gate** — Run
   `fastboot -s "$FASTBOOT_SERIAL" boot boot.img`. Expect: the image starts
   without changing UFS, and the screen stays lit because simpledrm holds the
   panel's VCI and VDDIO rails. If it goes dark about 30 seconds in, record
   `dmesg | grep -i -E 'regulator|simple'` and stop.
   **Pre-boot DTB check:** before running `fastboot boot`, decompile the exact
   packed DTB on the laptop with
   `dtc -I dtb -O dts` and verify it contains both
   `removed-region@86200000` and `removed-region@89100000`. On the phone,
   before touching the screen or doing any other test, verify
   `/proc/iomem` marks the complete `0x85fc0000–0x8a8fffff` range reserved.
   If it does not, stop immediately and run `reboot-to bootloader`.
   Pass only when `uname -r`, the `boot.img` sha256, all partition `ro` values,
   whole-disk `ro` values, and `ufs-ro` lines from `dmesg` are recorded.
   `/dev/sda` must be absent or present with `/sys/block/sda/ro=1` in NFS mode;
   each other whole-disk node must be absent or present with its `ro=1`. Every
   partition must have `ro=1`. Stop if any partition or present whole-disk node
   has `ro=0`.
   Also record the reserved-memory lines from
   `grep -i -E 'reserved|System RAM' /proc/iomem`, the bound `qcom_wdt`
   driver, its running watchdog feeder, and USB/SSH are recorded and correct.
   Stop if any partition or present whole-disk node has `ro=0`, the watchdog
   is not fed, USB/SSH fails,
   or anything asks to flash. Rollback: use the verified forced-restart
   procedure from step 3, then recover from the verified backup if needed.
   Risk: a hard kernel hang can still require the tested button procedure
   from step 3. The Dipper builder disables the no-USB panic watcher and
   selects `ram-rescue`, so missing USB does not deliberately reset the
   single-slot phone, and missing or failed NFS never selects userdata.

The current recorded first light used the stock `dtbo` untouched. The device
package still has no supported flash, push or installer path. The persistent
rescue write was a separate manual operation, and its exact host command and
whether its serial was pinned were not retained. The post-write check hashed
only the first 23,314,432 bytes of the 64 MiB `boot` partition; a whole-
partition hash was not captured then. A read-only audit on 2026-11-21 measured
the current whole-partition hash as
`2453231cb158f8cea115fc998a9e3c8075e564c33182b2e234e6bbabe6c3cf88`; no boot
write is recorded since 11-19, but this does not recreate the missing
after-write measurement. Quatrix One owns the handset and operated the test.
The 11-09 restore image is identified by SHA-256
`e9ef7bff84d181e09de286a95b9487ec5fcb5c0cc53db3ae780d6a64ceb4fbe8`; after
verifying that image and the unlocked Dipper in fastboot, the documented
recovery command is `fastboot -s "$FASTBOOT_SERIAL" flash boot
"$BOOT_11_09_IMAGE"`, followed by `fastboot -s "$FASTBOOT_SERIAL" reboot`.
This restore has not been run and must wait for the maintainer's confirmation.
Do not write the phone again while that review question is open. Keep it and
the USB cable present during a probe.

## Build and probe

Build a kernel checkout containing the Dipper kernel PRs with
`device/dipper/kernel.config` merged after the shared Omarchy Mobile fragment.
Set `DEVICE=dipper`, `KERNEL_DIR` (source), and `KERNEL_OUT` (build output), then
run `bin/omamobile kernel`. The output must include `Image`, `Image.gz`,
`arch/arm64/boot/dts/qcom/sdm845-xiaomi-dipper.dtb`, and modules from that same
kernel release. Then set `SSH_PUBKEY` to an OpenSSH public key and run
`tools/dipper/build` with the same `KERNEL_DIR` and `KERNEL_OUT`. For a local
NFS-root probe, pass `OMAMOBILE_NFSROOT=<host>:/<export>` to the builder; the
host and export are build inputs, never descriptor values. The builder requires
Docker with arm64 emulation; it writes its output inside `out/dipper` by
default. Do not commit the key or generated images.

The initramfs provides USB networking, SSH and a rescue shell. It does not
mount `persist`, read or embed per-phone identifiers, start Wi-Fi, or install a
root filesystem. The network daemon binds only to the IPv4 address assigned to
`usb0`. No Wi-Fi credentials, MAC addresses or private keys belong in the
repository; the SSH public key and generated host key stay in the local output.

## What remains

- Do not flash until there is a reviewed, device-specific recovery plan and a
  verified backup of the installed system. This PR deliberately adds no
  persistent writer.
- A current Arch root has passed all 17 offline rootfs-smoke checks, but has
  not booted on the phone. A later hard NFS-root mount can freeze the
  root session if the host drops; use it only for a RAM-only probe. NFS-root
  must configure systemd's hardware watchdog within the kernel driver's limit.
  The Dipper `qcom_wdt` driver's `0xFFFFF` tick limit at 32764 Hz gives a
  maximum timeout of 31 seconds. Systemd rejected 60 seconds in the
  2026-11-15 test; the package now uses 30 seconds for both runtime and reboot
  watchdogs. A fresh boot with that packaged setting still needs verification.
  It must never fall through to writable userdata.
- Wi-Fi needs firmware and the phone's own WLAN address. Read identity files
  from `persist` with `debugfs` (read-only) before enabling that service; never
  mount `persist`.
- The 2026-11-15 test journal records
  `Failed to set watchdog hardware timeout to 1min: Invalid argument` with
  `RuntimeWatchdogSec=60s`; udev also timed out before SSH became available.
  The earlier 2026-11-10 NFS test used `RuntimeWatchdogSec=20s` and reached
  multi-user. NFS link-loss recovery and the Omarchy desktop on the current
  Omarchy root remain untested.
- FTS5 controller probe and physical contact/coordinate/release events passed
  on 2026-11-12 (see [NOTES.md]); current physical gestures and clean-session
  input delivery remain untested.
  Shared Mesa FD630 rendering and a compositor DPMS cycle passed in guarded
  rescue; they do not replace a clean-session test (see [NOTES.md]).

From this rescue image, an SSH session can return to fastboot with
`reboot-to bootloader`. The installed ROM's `recovery` image was verified from
its 4.9.337 kernel header, but recovery-mode reboot was not tested; this runbook
uses only the verified bootloader path. The helper asks the PMIC reboot-mode
driver to select the bootloader and writes no UFS partition. The PMIC reset path
was verified on the handset on 2026-11-09. The packaged helper returned the
running image to fastboot on 2026-11-09 without writing UFS.

[panel #218]: https://github.com/derekross/linux-omarchy-mobile/pull/218
[touch #219]: https://github.com/derekross/linux-omarchy-mobile/pull/219
[DTS #220]: https://github.com/derekross/linux-omarchy-mobile/pull/220
[NOTES.md]: NOTES.md
