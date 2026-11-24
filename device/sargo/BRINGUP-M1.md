<!-- SPDX-License-Identifier: MIT -->
# Pixel 3a (sargo): first light and a hand install on slot B

**Status (2026-11-24):** both parts ran on one phone: a RAM boot to a USB
shell, then Omarchy installed on slot B and `userdata` with display, GPU and
touch working. Results and what failed on the way: [NOTES.md](NOTES.md).

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
   Rollback: `reboot-to bootloader` from the shell. Risk: low.

## Hand install on slot B (writes `userdata` and `boot_b`)

`bin/omamobile flash` and `tools/install-phone` refuse `android-v2` until
this phone's CONTRIBUTING.md §3.1 entry exists, so this is by hand. It
erases whatever is on `userdata`.

4. **Root image.** `tools/local-key-init sargo`, `tools/fetch-published
   --channel stable out/sargo/published`, `tools/build-packages --local
   sargo --import out/sargo/published packages/omamobile-device-sargo`,
   `KERNEL_OUT=... tools/build-rootfs --local sargo --channel stable`
   (`ALARM_MIRROR=http://<mirror>/$arch/$repo` when the Arch Linux ARM
   redirector hands out a stale mirror). Write the first-boot answers into a
   copy as `tools/install-phone` does (firstboot.conf, root's
   authorized_keys, boot-update.conf with `AUTO_WRITE=no`), then `img2simg`.
   Risk: none.
5. **Write.** `fastboot flash userdata root.simg`, `fastboot flash boot_b
   boot.img`, `fastboot --set-active=b`, `fastboot reboot`.
   Expect: the initramfs grows the root, switches to Arch, first boot
   creates the user, SDDM starts Hyprland.
   Stop: the phone doesn't come back on USB within a minute (fastboot by the
   buttons, then `fastboot --set-active=b` and look at the screen's last
   lines). Rollback: slot A is untouched; what it boots depends on what was
   there. Risk: medium (userdata is erased).
6. **Display, GPU, touch.** Until the packages carry them: install
   `linux-firmware-qcom` and Arch Linux ARM's `mesa` and `vulkan-freedreno`,
   and copy the output of `tools/extract-vendor-firmware -d sargo` to `/`.
   Set the clock first (`date -s`): with the clock at 1970 pacman refuses
   every signature. Then `systemctl restart sddm`.

Slot B is unmarked: each boot spends one of its three tries. Prefer
restarting services over rebooting; `fastboot --set-active=b` restores the
tries.
