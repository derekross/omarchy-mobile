<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T (hotdogb) first-light plan

The device is sold as the OnePlus 7T (HD1901/HD1905 among the model
variants) and uses the SM8150-AC (Snapdragon 855+). The board compatible
is `oneplus,hotdogb`. See [NOTES](NOTES.md) for evidence from one test
phone. The model listing is no claim that both variants were tested,
and the SoC name alone is insufficient to identify a phone.

## Boot and recovery gates

The development image used an Android boot header v2 with a separate DTB
in the image, a kernel and an initramfs. ABL applied stock DT overlays.
The image packer and initramfs on that build were private bring-up tools.
The shared tools in this tree have no 7T image packer. The descriptor
allows no writable partitions and the shared image, flash, push and
installer commands refuse it. A replacement RAM image needs a separately
reviewed v2 layout, overlay handling and per-board watchdog handling.

1. **Offline first.** Build the board's DTB and verify the memory map
   against stock, including the boot splash, DSP and secure reservations.
   Build with UFS and radio unavailable to userspace for first light.
   Stop for an overlap or an unidentified carveout.
2. **Attended RAM-only first light, after review.** Establish the button
   path back to the bootloader and verify the no-USB path stays in RAM
   or returns to the bootloader. Test console and USB gadget first.
   Stop if the phone tries to mount storage, restarts unexpectedly, or
   USB fails to enumerate. Return to the bootloader by the buttons.
   The local image's RAM boots establish that ABL can start its v2
   layout. The shared first-light image still needs this test.
3. **Persistent install is gated on a maintainer decision.** Follow
   [CONTRIBUTING §3.1](../../CONTRIBUTING.md#31-stock-android-stays-on-slot-a).
   Stock on slot A, the slot-B plan and independent recovery all need to
   be checked. Before proposing any GPT slot mark, characterize where
   this ABL keeps the flags, the boot LUN and exact sectors, the bit and
   CRCs, before/after status and rollback for corrupted GPT. A new
   exception would be a separate maintainer decision.

## Firmware

Owners provision required firmware from their own matching stock software
or read-only backups under [CONTRIBUTING §7](../../CONTRIBUTING.md#7-licensing-and-vendor-firmware).
The sensor DSP result used a matching stock SLPI image, its userspace
libraries and its registry. The registry is phone-specific. Keep
calibration and identity data local and out of packages, and leave the
protected partitions read-only. An upstream extraction workflow is pending.
