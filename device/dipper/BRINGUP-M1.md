<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Mi 8 (dipper): RAM-only first light

**Status (2026-11-11):** the newest RAM boot is the 2026-11-11 one in [NOTES.md]: #505's rebuilt image `665fcbd682cd8e64b3ffec1ff7f4ab9ca33a26b9b47b11073be7a3c267abf2b1` on kernel/DTS #220's final head, with every UFS partition read-only. Before it, on 2026-11-10, the combined #503/#505 non-NFS image `540b5d31ea73a31ade9a8d8cb5152cf701dc3c2ad8256734790b0ef2db6dbdd0` booted by RAM on the Xiaomi Mi 8 with kernel/DTS PR #220 at `055a4019998f22cc0e2a8afef7650274a6ce0657`. Its initramfs root had all 85 UFS partition flags at `ro=1`. `/sys/block/sda/ro` was `0`, but `/dev/sda` was absent; `sdb`–`sdf` were `ro=1`. The guard confirmed this state. `qcom_wdt` and its feeder ran, simpledrm registered `fb0`, USB/SSH worked, and `/proc/iomem` reserved `0x85fc0000–0x8a8fffff`, covering the former TZ range. The pinned rescue SSH key matched, and `reboot-to` returned the phone to fastboot. Physical input events were not captured on this exact image.

A separate RAM NFS-root run used image `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7` with the rebased #503 init. BusyBox `mount` switched to the test NFS root; all six disk flags and all 85 partition flags were `ro=1`. Systemd reached the multi-user target with `RuntimeWatchdogSec=60s`, and SSH remained available. `reboot-to bootloader` returned the phone to fastboot. The exported root was a generic Arch base; this did not test the Omarchy desktop or link-loss recovery. Full results are in [NOTES.md].
The FTS5 driver from [touch #219] is merged into linux-omarchy-mobile. The
Dipper board DTS from [DTS #220] is merged too (2026-11-11), and the EA8074
panel driver is under review in [panel #218].
The EA8074 panel test is recorded in [NOTES.md]. The FTS5 touchscreen
still needs a hardware test.
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
   Risk: a USB host that never configures still reaches the existing watcher
   panic after about 65 seconds; on this single-slot phone, recovery depends on
   the tested procedure from step 3.

The current recorded first light used the stock `dtbo` untouched. The image is
RAM-only; never use `fastboot flash`, `bin/omamobile flash`, `bin/omamobile
push`, or the installer. Keep the phone and USB cable present during a probe.

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
- The initramfs has no Arch root yet. A later hard NFS-root mount can freeze the
  root session if the host drops; use it only for a RAM-only probe. NFS-root
  needs a root with `RuntimeWatchdogSec=60s`, because `kill -9 -1` stops the
  userspace feeder before systemd can take over. It must never fall through to
  writable userdata.
- Wi-Fi needs firmware and the phone's own WLAN address. Read identity files
  from `persist` with `debugfs` (read-only) before enabling that service; never
  mount `persist`.
- The exact systemd journal line from the earlier failed `qcom_wdt` timeout
  change was not retained. The 2026-11-10 NFS test root reached systemd with
  `RuntimeWatchdogSec=60s`; NFS link-loss recovery and the Omarchy desktop on
  that root remain untested.
- Test the FTS5 touchscreen changes and GPU rendering on the phone before
  marking them supported.

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
