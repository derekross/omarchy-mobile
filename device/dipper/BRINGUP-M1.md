<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Mi 8 (dipper): RAM-only first light

**Status (2026-11-08):** first-light results are recorded in [the notes PR #330].
Kernel support is public for review in [panel #218], [touch #219],
[DTS #220] and [ath10k #221]. These PRs are not merged yet. The direct EA8074
panel driver and FTS5 touchscreen path still need testing on the current kernel.

This is a RAM-only bring-up. Dipper has one OS `boot` partition and no alternate
OS slot. The descriptor sets `BOOT_METHOD=ram-only`, the builder makes only a
`fastboot boot` image, and the initramfs keeps every UFS partition read-only.
There is no supported flash, push, installer or persistent update path here.

## Recovery and safe boot

Each gate below must pass before proceeding. Set `FASTBOOT_SERIAL` to the
intended handset's serial and `BACKUP_CHECKSUMS` to the locally held stock
backup checksum manifest. Do not boot if the manifest is missing or fails.

1. **Backup gate** — Expect: the verified stock backup and checksum manifest
   are available off-device. Pass: `sha256sum -c "$BACKUP_CHECKSUMS"` reports
   every entry OK. Stop: any missing or mismatched entry. Rollback: restore the
   verified stock backup using the device recovery procedure. Risk: an
   unverified backup cannot recover a damaged single-slot phone.
2. **Fastboot gate** — Enter fastboot with **Volume Down + Power**; the §3.1
   entry is in [PR #499](https://github.com/derekross/omarchy-mobile/pull/499).
   Run `fastboot -s "$FASTBOOT_SERIAL" getvar unlocked`. Expect `yes`. Pass:
   the serial identifies the intended phone and the bootloader is unlocked.
   Stop: absent/ambiguous serial or locked bootloader. Rollback: leave fastboot
   without writing. Risk: this device has no alternate OS slot.
3. **Recovery gate** — Confirm the handset's forced-restart buttons and hold
   duration on the device, then record them in this runbook. Fastboot entry
   with **Volume Down + Power** is separate from a forced restart. Stop if the
   forced-restart procedure has not been verified; do not infer it from another
   phone. Expect: an attended forced restart returns the handset to a state
   where fastboot can be entered. Pass: that recovery path has been exercised
   and recorded. Rollback: do not start a RAM boot until it passes. Risk: a
   single-slot phone with no verified forced restart may be unrecoverable after
   a hang.
4. **RAM boot gate** — Run
   `fastboot -s "$FASTBOOT_SERIAL" boot boot.img`. Expect: the image starts
   without changing UFS. The screen may go dark about 30 seconds after boot
   because the panel regulator is not enabled; that alone is not a hang.
   Pass only when `uname -r`, the `boot.img` sha256, all `ro` values from
   `grep . /sys/block/sd*/ro /sys/block/sd*/sd*/ro`, the `ufs-ro` lines from
   `dmesg`, the reserved-memory lines from
   `grep -i -E 'reserved|System RAM' /proc/iomem`, the bound `qcom_wdt`
   driver, its running watchdog feeder, and USB/SSH are recorded and correct.
   Stop if any partition has `ro=0`, the watchdog is not fed, USB/SSH fails,
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
  verified stock backup. This PR deliberately adds no persistent writer.
- The initramfs has no Arch root yet. A later hard NFS-root mount can freeze the
  root session if the host drops; use it only for a RAM-only probe. NFS-root
  needs a root with `RuntimeWatchdogSec=60s`, because `kill -9 -1` stops the
  userspace feeder before systemd can take over. It must never fall through to
  writable userdata.
- Wi-Fi needs firmware and the phone's own WLAN address. Read identity files
  from `persist` with `debugfs` (read-only) before enabling that service; never
  mount `persist`.
- Test the panel and FTS5 changes on the phone before marking them supported.

[panel #218]: https://github.com/derekross/linux-omarchy-mobile/pull/218
[touch #219]: https://github.com/derekross/linux-omarchy-mobile/pull/219
[DTS #220]: https://github.com/derekross/linux-omarchy-mobile/pull/220
[ath10k #221]: https://github.com/derekross/linux-omarchy-mobile/pull/221
[the notes PR #330]: https://github.com/derekross/omarchy-mobile/pull/330
