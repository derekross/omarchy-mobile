<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx) first light

Status (2026-10-23): slot B boots and SSH comes up at `root@172.16.42.1`
over the USB NCM gadget. Both cluster watchdogs are stopped at probe. The
screen keeps the bootloader logo: there is no framebuffer node yet. Stock
Android is still on slot A. Slot B has not been marked successful. Kernel
7.3.0-rc6.

## Facts

The stock capture and what each boot showed are in [NOTES.md](NOTES.md).
Tracking issue: #36.

## What booted

The board file (linux-omarchy-mobile, `gs201-lynx.dts`) enables the USB
controller and relies on the SoC tree for the cluster watchdogs. UFS, the
panel, touch, the GPU and the radios stay disabled. It carries
`/soc_compatible/B0_IPOP` instead of `/soc_id`, because lynx's ABL matches
the IPOP package's DTB on that node, and `ramoops` at stock's address.

`device/lynx/device.conf` is what `bin/omamobile` reads with `DEVICE=lynx`.
It differs from cheetah's in two ways the bootloader forces:

- `SOC_COMPATIBLE="b0-ipop:0x9855:1:0:1"`: one DTB, matched on
  `/soc_compatible`.
- `AVB_FOOTERS="boot:0x4000000 init_boot:0x800000"` with stock's rollback
  index and security patch: without a footer on `boot` and `init_boot`,
  lynx's unlocked ABL never shows the orange warning and never boots slot B
  (black screen, nothing on USB, three silent retries, then slot A).

The shared init writes no display register (`SIMPLEFB_TRIG_CON` is unset)
and reads no display DMA register (`BRINGUP_PROBE` is unset).

## First boot

Flash only slot B, from fastboot: `DEVICE=lynx bin/omamobile images`, then
`DEVICE=lynx bin/omamobile flash`. Slot A stays stock Android. Confirm the
phone is in fastboot before every `flash` (an `adb reboot bootloader` once
did nothing), and run fastboot commands under `timeout`: they otherwise wait
forever on a phone that is not there.

Expect, in this order:

1. The orange "bootloader unlocked" warning, then a black screen that stays
   black. The bootloader logo may stay instead. Both are normal: this kernel
   does not drive the panel.
2. Within about 20 s, a USB network device on the laptop. The phone's DHCP
   server did not answer here, so give the host side `172.16.42.2/24` by
   hand (an NetworkManager profile works).
3. `ssh root@172.16.42.1` answers, from the initramfs (busybox, dropbear).
   `dmesg | grep watchdog` shows both `10060000.watchdog` and
   `10070000.watchdog` as `watchdog inactive, reset disabled`.

Stop if no USB device appears within a minute, if the phone resets by itself
at about 60 s (a watchdog was left running), or if it does not come back to
slot A by itself after three failed boots. Do not flash again until you know
why.

## How to get back

Slot B has three retries after `fastboot --set-active=b`, and every boot
that is not marked successful uses one. After the third, ABL boots slot A on
its own. While stock is on slot A that is the fallback; just let it boot.

- **Force restart:** hold Power for about 30 s. The phone restarts into the
  active slot. Both watchdogs are stopped at probe, so a hang that does not
  panic only ends this way.
- **Fastboot by hand:** hold Volume Down and Power together, from off or
  through a force restart, until the bootloader menu appears. Then
  `fastboot --set-active=a` (or `b`). Never pick "Factory data reset" in
  that menu or in Android recovery: it wipes `userdata`.
- **Fastboot without buttons**, from our Linux: `DEVICE=lynx bin/omamobile
  fastboot`. It crashes our kernel, ABL falls back to slot A, and the tool
  runs `adb reboot bootloader` from Android. Holding Volume Down during a
  `reboot-to` is too late by the orange warning.
- **Power off:** `poweroff` from our Linux stops the SoC but leaves the
  panel lit and the phone off USB (no PMIC driver). Use the bootloader
  menu's "Power off" instead.

Nothing here writes outside slot B's five boot images. Stock's `init_boot_a`
stays as it was, so slot A can go back to plain stock with the factory image.
