<!-- SPDX-License-Identifier: MIT -->
# dodge chainload

Stage 1 of the OnePlus 13 (dodge) RAM-only boot path. ABL refuses header
v2 under `fastboot boot`, and a header v4 `boot.img` ramdisk is ignored
(stock DTB comes from the flashed `vendor_boot`). The only way to reach
our DTB without flashing `vendor_boot` is this chain:

1. Pack our kernel with a built-in initramfs (`/omamobile/…`) and
   `CONFIG_CMDLINE_FORCE rdinit=/omamobile/init` as a kernel-only
   header v4 image (`tools/dodge-chain pack`, also via
   `bin/omamobile images` when `BOOT_METHOD=qcom-abl`).
2. Stage 1 (`init` here) runs as PID 1. It mounts proc (and optionally
   sysfs) only, never opens a block device, and `kexec -c` into stage 2. Stage-1 userspace claim only: the kernel may still probe UFS on stock's DTB.
3. Stage 2 is the PR kernel `Image`, the dodge DTB (live memory map
   from `$LIVE_DTB`), and the shared initramfs from
   `bin/omamobile initramfs` (`INITRAMFS_INIT=/initramfs/init`).

## Files

- `init` — stage 1 PID 1. No storage writes.
- `stage2-dtb.py` — builds stage 2's DTB from the board DTB plus the
  rooted live FDT's memory map. `$LIVE_DTB` is never committed.

## Variables

See `tools/dodge-chain`. Defaults that match the known-good boot:

- `DTB_OPTS='splash fb'`
- `STAGE2_CMDLINE='rdinit=/init clk_ignore_unused pd_ignore_unused panic=10 console=tty0 omamobile.ufs-probe'`
- `LIVE_DTB` — required; path to the rooted live FDT (outside the tree)

Nothing here is installed by `packages/omamobile-device-dodge`. Stage 2
carries the shared storage guard; stage 1 never reaches it.
