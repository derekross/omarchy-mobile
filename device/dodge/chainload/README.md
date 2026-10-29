<!-- SPDX-License-Identifier: MIT -->
# dodge chainload (optional)

Helpers used during early bring-up to load a stage-2 DTB and continue into the
Arch root without flashing. Day-to-day kernel updates rewrite `boot_b` from
a built `boot.img`; keep these scripts only if you are iterating a one-shot
`fastboot boot` image.

- `init` / `probe-init`: small initramfs entry points for chain experiments.
- `stage2-dtb.py`: packs or swaps a board DTB into a boot image for trials.

Nothing here is required by `packages/omamobile-device-dodge`.
