<!-- SPDX-License-Identifier: MIT -->
# Pixel 3a (sargo): first light and a hand install on slot B

**Status (2026-11-28):** the RAM boot ran on one phone on 2026-11-24, and
Omarchy was then put on slot B by hand (recorded below, not to be
repeated). Until the maintainer has decided about this phone, it stays as
it is: boots of what is on slot B, no new writes to `boot_b` or `userdata`.
Results and what failed on the way: [NOTES.md](NOTES.md).

Every step that touches the phone is the owner's call. Pin every fastboot
command with `-s "$FASTBOOT_SERIAL"`. Keep captures, the factory image and
logs in `~/android/reference/sargo/` or `out/`, never in the repository:
the bootloader puts the phone's serial on the kernel command line, so a
`dmesg` holds it.

## Build (laptop only)

```sh
export DEVICE=sargo KERNEL_DIR=~/omamobile-kernel/wt-sargo KERNEL_OUT=~/omamobile-kernel/out-sargo
bin/omamobile kernel && bin/omamobile modules && bin/omamobile initramfs
# The owner's own stock dtbo.img, for the DTB's overlay sink (DTBO_SINK=yes)
unzip -p sargo-*-factory-*.zip '*/image-sargo-*.zip' > image.zip && unzip -p image.zip dtbo.img > dtbo.img
STOCK_DTBO=$PWD/dtbo.img bin/omamobile images
```

Pass: `images` reports "dtbo-sink: 10 overlays, 153 labels sunk" and one
`boot.img`. Stop: any refusal. Risk: none.

## RAM boot (nothing written)

1. **Stock facts.** `fastboot getvar all`: product `sargo`, `unlocked: yes`.
   Record the slot flags. Stop: locked, or another product. Risk: none.
2. **Recovery.** Fastboot by the buttons is Volume Down + Power; a forced
   restart is Power held until the phone restarts. Stop if either doesn't
   work. Risk: none.
3. **Boot.** For a probe that stays in the initramfs, build the images with
   `omamobile.initramfs` added to `CMDLINE`. Then
   `fastboot boot $KERNEL_OUT/images/boot.img`.
   Expect: a USB network device and serial console within about 30 s, SSH
   as root on 172.16.42.1 (or the phone's IPv6 link-local address on that
   interface, which needs no address on the laptop).
   Pass: `dmesg | grep ufs-ro` shows `mmcblk0` and `mmcblk0rpmb` removed and
   every partition but the running slot's `boot` and `userdata` read-only.
   Stop: "Invalid Parameter" from fastboot (the DTB, `text_offset` or
   header; NOTES "first light"), or any other eMMC partition writable.
   Rollback: `reboot-to bootloader` from the shell. Risk: low. A RAM boot
   spends one of slot B's tries too (NOTES.md, 2026-11-25), and new ones
   wait for the maintainer's answer on #1070.

## Record: the hand install on slot B of 2026-11-24 (not to be repeated)

**What was done on 2026-11-24, outside the tools because they refuse this
boot method. It waits for the maintainer's decision on this phone and is
not a step for anyone to follow:** `userdata` goes only through
`tools/install-phone`, and slot B's images only through `bin/omamobile
flash`/`push`, once this phone has its CONTRIBUTING.md §3.1 entry. What
came of it is in [NOTES.md](NOTES.md) ("Writes made by hand on
2026-11-24").

- **Root image.** `tools/local-key-init sargo`, `tools/fetch-published
  --channel stable out/sargo/published`, `tools/build-packages --local
  sargo --import out/sargo/published packages/omamobile-device-sargo`,
  `KERNEL_OUT=... tools/build-rootfs --local sargo --channel stable`, the
  first-boot answers written into a copy as `tools/install-phone` does
  (firstboot.conf, root's authorized_keys, boot-update.conf with
  `AUTO_WRITE=no`), then `img2simg`.
- **The writes.** `fastboot flash userdata root.simg`, `fastboot flash
  boot_b boot.img`, `fastboot --set-active=b`, `fastboot reboot`; the
  initramfs grew the root and first boot created the user.
- **Into the root, by hand:** `linux-firmware-qcom` and Arch Linux ARM's
  `mesa` and `vulkan-freedreno`, and the output of
  `tools/extract-vendor-firmware -d sargo`, after setting the clock
  (`date -s`; at 1970 pacman refuses every signature).

## Slot A: stock restored (draft for the maintainer to read; nothing here has run)

Why: CONTRIBUTING.md §3.1 keeps stock on slot A as the way back, and this
phone's slot A holds the owner's earlier Linux install instead (NOTES.md,
"Slots"). Nothing in this section runs until the maintainer has read it and
said yes; it is a one-time exception to §3.1's "never flash `vbmeta` or
anything without `_b`", for slot A's own partitions only.

What it writes: only `_a` partitions, only those the factory image's own
image zip names, and of those only the ones whose bytes differ from it.
**Never** `bootloader`, `radio`/`modem`, anything without a slot suffix,
anything on slot B, or `userdata`. The factory zip's `bootloader-*.img` and
`radio-*.img` are not used: the phone already runs those versions (A1).
Pin every command with `-s "$FASTBOOT_SERIAL"`; keep every image and
capture off the repository.

A0. **Before.** The maintainer's yes on this section. `tools/nv-backup -d
    sargo --check` against the backup of 2026-11-25 passes (every NV
    partition the same). Risk: none.

A1. **The build.** `fastboot getvar all` recorded: `product: sargo`,
    `unlocked: yes`, `version-bootloader: b4s4-0.4-8048689`,
    `version-baseband: g670-00145-220106-B-8048689`, and both slots' flags
    (NOTES.md's table gets a row). The SP2A.220505.008 factory zip's
    SHA-256 matches Google's published one, and its `bootloader-*` and
    `radio-*` names carry exactly those two versions. Stop: any
    difference (it wouldn't be the installed build, and an older one is
    never flashed). Risk: none.

A2. **The list.** `unzip -l` on the inner `image-sargo-sp2a.220505.008.zip`,
    each image recorded here with the partition it goes to
    (`<name>.img` → `<name>_a`), and for each `fastboot getvar
    has-slot:<name>` (yes) and `fastboot getvar is-logical:<name>_a` (no).
    Left out: `system_other.img` (fastboot writes it to the other slot),
    `android-info.txt`, and any metadata-only image. Stop: an image whose
    partition has no slot, or is logical (it would need fastbootd; ask
    first). Risk: none.

A3. **Compare before writing.** From the running system on slot B (one of
    its tries), read every listed `_a` partition through the guard, which
    keeps them read-only: its SHA-256 over the image's unsparsed size
    (`simg2img` for a sparse image), and a copy of `boot_a` and `vbmeta_a`
    as they are now, kept off the repository as the rollback. Expected from
    NOTES.md: `dtbo_a` matches, and `boot_a` and `vbmeta_a` differ (the
    earlier install); the others are recorded either way. Risk: none
    (reads).

A4. **Write.** In fastboot (`reboot-to bootloader` from slot B, or the
    buttons), for each partition that differed in A3 and only those:
    `fastboot -s "$FASTBOOT_SERIAL" flash <name>_a <name>.img`, with stock's
    own `vbmeta.img` for `vbmeta_a` (no `--disable-verity` or
    `--disable-verification`). Then `fastboot getvar all` again. Stop: any
    error; write nothing more. Rollback: the copies from A3, written back
    the same way. Risk: low (slot A only; `boot_b`, `vbmeta_b` and
    `userdata` untouched).

A5. **A stock boot.** `fastboot --set-active=a`, `fastboot reboot`.
    `userdata` holds the Arch root, not Android's data, so stock is expected
    (not tried) to stop in recovery ("Cannot load Android system") and
    offer a factory data reset: **don't take it**; choose "Reboot to
    bootloader" there. Reaching that screen from slot A's own chain (the
    unlocked-bootloader warning, then Android's recovery) is the pass for
    the way back. A full boot to Android would need `userdata` wiped, which
    loses the Arch root; that is the maintainer's choice, and it would then
    be reinstalled through `tools/install-phone` once slot B has its §3.1
    entry. Stop: a boot loop (buttons, then `fastboot --set-active=b`).
    Risk: low.

A6. **Back to slot B, and a fresh backup.** `fastboot --set-active=b`,
    `fastboot reboot`; from Linux, `tools/nv-backup -d sargo DIR` into a new
    directory, and `--check` against the 2026-11-25 backup (the NV
    partitions the same; `devinfo` may differ, it holds the slot flags).
    Both slots' flags before and after go into NOTES.md's table. Risk: none.

After this, slot B's §3.1 entry (the GPT mark) can be proposed on its own.

Slot B is unmarked: each boot spends one of its three tries. Prefer
restarting services over rebooting; `fastboot --set-active=b` restores the
tries.
