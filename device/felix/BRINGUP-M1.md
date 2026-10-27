<!-- SPDX-License-Identifier: MIT -->
# Pixel Fold (felix) first light

Status (2026-10-27): the descriptor unmasks both triggers. Cover DECON1
`0x1c241030` is written with `0x01003061` (tear source DDI1). Inner DECON0
`0x1c240030` is written with `0x00003061` (tear source DDI0). The inner
picture changing is no longer a stop. Do not reset either panel or program
its DSI. Slot A is another Omarchy install, not stock Android. A bad slot B
boot has no Android to fall back to. The way back is fastboot from the
buttons, then the last known-good slot B set with
`DEVICE=felix bin/omamobile flash`. The 2026-10-13 boot below is the first-light
record, when the inner trigger was still left masked.

## Facts

The stock capture and the cover-console boot are in [NOTES.md](NOTES.md).

## What booted

The local board file enables the USB controller and the cover framebuffer
the bootloader is already scanning, and it relies on the SoC tree for the
cluster watchdogs. Both panel nodes, both touch controllers, the GPU, and
UFS stay disabled. That board file is not in this repository. It will be
proposed against linux-omarchy-mobile, branch `omamobile`.

The shared init writes this device's `SIMPLEFB_TRIG_CON`, one pair per
line after the packer splits it. That is the cover pair and the inner pair.
`BRINGUP_PROBE` is unset, so it does not read the display DMA registers.
`device/felix/device.conf` is what `bin/omamobile` reads. The default
device stays cheetah. A Fold image is `DEVICE=felix`.

## First boot

Phone folded. Flash only slot B. Expect SSH at `root@172.16.42.1` and a
Linux console on the cover. The inner trigger is unmasked, so that panel
scans its splash. Nothing in the tree has a panel reset pin or its rails.

Stop if the cover brightness changes on its own, or if the phone does not
come back. The way back is fastboot from the buttons, then the last
known-good slot B set with `DEVICE=felix bin/omamobile flash`. Do not
treat a slot A boot as stock Android. What was written to slot A is
recorded on omarchy-mobile#35.
