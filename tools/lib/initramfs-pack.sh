# SPDX-License-Identifier: MIT
# Pack an initramfs staging tree reproducibly (docs/RELEASES.md §5.2), for
# bin/omamobile initramfs: the same tree gives the same bytes on any
# machine, whatever order the files were made in, when, or under which
# umask, so a release initramfs staged on two build machines is one file.
#   names sorted (LC_ALL=C, "." first, as before), owner 0:0, every mtime INITRAMFS_EPOCH
#   (SOURCE_DATE_EPOCH, else 0), GNU cpio --reproducible (no inode or
#   device numbers), lz4 -l -9 (legacy frames, as the kernel reads them)
# Modes are kept as staged: the caller sets its umask (022) before staging.
#
#   initramfs_pack STAGE OUT
initramfs_pack() {
  local stage=$1 out=$2 epoch=${SOURCE_DATE_EPOCH:-0}
  [[ -d $stage ]] || { echo "initramfs_pack: no $stage" >&2; return 1; }
  [[ $epoch =~ ^[0-9]+$ ]] || { echo "initramfs_pack: SOURCE_DATE_EPOCH must be a number" >&2; return 1; }
  find "$stage" -exec touch -h -d "@$epoch" {} +
  # "." stays in, first: the kernel applies its mode (0755) to the
  # initramfs's /, which otherwise keeps tmpfs's 1777
  (cd "$stage" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --reproducible --quiet) \
    | lz4 -l -9 -q > "$out"
}
