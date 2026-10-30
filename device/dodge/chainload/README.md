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
   sysfs) only, never opens a block device, compares this boot's memory
   `reg` with the copy saved at pack time from `$LIVE_DTB`, appends
   `androidboot.slot_suffix` from `/proc/bootconfig`, then
   `/proc/device-tree/chosen/bootargs`, then the packed
   `/omamobile/slot_suffix` (from `OMAMOBILE_SLOT` — ABL omits it under
   `fastboot boot`) (stage 1's own `/proc/cmdline` is
   `CMDLINE_FORCE`d and has no ABL keys), and `kexec -c`
   into stage 2. Stage 1's kernel config has UFS disabled
   (`SCSI_UFS_QCOM` / `SCSI_UFSHCD`), so it does not probe storage on
   stock's DTB.
3. Stage 2 is the PR kernel `Image`, the dodge DTB (live memory map
   from `$LIVE_DTB`), and the shared initramfs from
   `bin/omamobile initramfs` (`INITRAMFS_INIT=/initramfs/init`).

`bin/omamobile images` refuses `qcom-abl` unless this directory exists
and passes `CHAINLOAD_DIR` into `tools/dodge-chain`, so the next
Qualcomm phone cannot inherit dodge's splash address, panel geometry,
apps RSC or SMMU stream ID by accident.

## Files

- `init` — stage 1 PID 1. No storage writes.
- `stage2-dtb.py` — builds stage 2's DTB from the board DTB plus the
  rooted live FDT's memory map. `$LIVE_DTB` is never committed. Dodge
  splash/panel/RSC/SMMU values live only in this script.

## Variables

See `tools/dodge-chain`. Defaults that match the known-good boot:

- `DTB_OPTS='splash fb'`
- `STAGE2_CMDLINE` — from the descriptor's `CMDLINE` (via `bin/omamobile`)
  or `rdinit=/init clk_ignore_unused pd_ignore_unused panic=10 console=tty0 omamobile.ufs-probe`
- `LIVE_DTB` — required; path to the rooted live FDT (outside the tree)
- `CHAINLOAD_DIR` — required; this directory
- `KERNEL_DIR` — required; same tree stage 2 was built from

Nothing here is installed by `packages/omamobile-device-dodge`. Stage 2
carries the shared storage guard; stage 1 never reaches it.
