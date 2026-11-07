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

- Enter fastboot with **Volume Down + Power**. The device's §3.1 recovery entry
  is in [PR #499](https://github.com/derekross/omarchy-mobile/pull/499).
- Check the bootloader's unlocked state with `fastboot getvar unlocked`.
- Boot the generated image with `fastboot boot boot.img`. Do not use
  `fastboot flash`, `bin/omamobile flash`, `bin/omamobile push`, or the installer.
- Because the image is loaded into RAM and does not write UFS, a power cycle
  returns to the boot image already installed on the phone. Keep the phone and
  a USB cable present during every probe.
- If the USB host never configures, the shared initramfs waits, shows its log,
  then panics after 20 seconds. On this RAM-only path that does not alter the
  installed `boot`; use the buttons to return to fastboot if the phone does not
  resume stock Android by itself.

## Build and probe

Build a kernel checkout containing the Dipper kernel PRs with
`device/dipper/kernel.config` merged after the shared Omarchy Mobile fragment.
Set `DEVICE=dipper`, `KERNEL_DIR` (source), and `KERNEL_OUT` (build output), then
run `bin/omamobile kernel`. The output must include `Image`, `Image.gz`,
`arch/arm64/boot/dts/qcom/sdm845-xiaomi-dipper.dtb`, and modules from that same
kernel release. Then set `SSH_PUBKEY` to an OpenSSH public key and run
`tools/dipper/build` with the same `KERNEL_DIR` and `KERNEL_OUT`. The builder
requires Docker with arm64 emulation; it writes its output outside the source
tree by default. Do not commit the key or generated images.

The initramfs provides USB networking, SSH and a rescue shell. It does not
mount `persist`, read or embed per-phone identifiers, start Wi-Fi, or install a
root filesystem. The network daemon binds only to the IPv4 address assigned to
`usb0`. No Wi-Fi credentials, MAC addresses or private keys belong in the
repository; the SSH public key and generated host key stay in the local output.

## What remains

- Do not flash until there is a reviewed, device-specific recovery plan and a
  verified stock backup. This PR deliberately adds no persistent writer.
- The initramfs has no Arch root yet. A later NFS-root path must remain in the
  rescue shell when the host or export is unavailable; it must not fall through
  to the phone's writable userdata.
- Wi-Fi needs firmware and the phone's own WLAN address. Read identity files
  from `persist` with `debugfs` (read-only) before enabling that service; never
  mount `persist`.
- Test the panel and FTS5 changes on the phone before marking them supported.

[panel #218]: https://github.com/derekross/linux-omarchy-mobile/pull/218
[touch #219]: https://github.com/derekross/linux-omarchy-mobile/pull/219
[DTS #220]: https://github.com/derekross/linux-omarchy-mobile/pull/220
[ath10k #221]: https://github.com/derekross/linux-omarchy-mobile/pull/221
[the notes PR #330]: https://github.com/derekross/omarchy-mobile/pull/330
