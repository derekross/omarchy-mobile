# SPDX-License-Identifier: MIT
# The release's one-file download (docs/RELEASES.md §6): one tar holding the
# bundle directory and, beside it, the root image with its .sha256 and
# .MANIFEST, so unpacking it gives exactly the layout tools/install-phone
# expects (the root image next to the bundle). tools/make-bundle makes it;
# tests use the same function.
#
#   source tools/lib/bundle-tar.sh
#   bundle_tar OUT NAME ROOTNAME VERSION
#     writes OUT/NAME.tar from OUT/NAME/ and OUT/ROOTNAME{,.sha256} and
#     OUT/<ROOTNAME without .img.zst>.MANIFEST, then OUT/NAME.tar.sha256
#     ("<sha256>  NAME.tar"). Both are written under a temporary name and
#     renamed into place. Returns non-zero on failure.
#
# Deterministic: the same files give the same bytes on any machine. GNU tar
# format (no pax headers with access or change times; base-256 sizes for a
# root image over 8 GiB), names sorted (C locale), owner and group 0 with
# no names, every mtime the release date at 00:00 UTC (SOURCE_DATE_EPOCH
# wins when set; a version that isn't a date gives 0), modes normalised to
# 644 and 755 (executable bits as on disk), hard links stored as files. No
# compression: the root image is zstd already, the boot images don't
# shrink, and the rest is small.

bundle_tar_epoch() {  # bundle_tar_epoch VERSION: prints the mtime the tar uses
  local v=$1
  if [[ -n ${SOURCE_DATE_EPOCH:-} ]]; then
    [[ $SOURCE_DATE_EPOCH =~ ^[0-9]+$ ]] || { echo "SOURCE_DATE_EPOCH is not a number" >&2; return 1; }
    echo "$SOURCE_DATE_EPOCH"
  elif [[ $v =~ ^(20[0-9]{2})\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01]) ]]; then
    date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} 00:00:00" +%s
  else
    echo 0
  fi
}

bundle_tar() {
  local out=${1:?} name=${2:?} root=${3:?} version=${4:?} epoch members f
  epoch=$(bundle_tar_epoch "$version") || return 1
  members=$(printf '%s\n' "$name" "$root" "$root.sha256" "${root%.img.zst}.MANIFEST" | LC_ALL=C sort)
  for f in $members; do
    [[ -e $out/$f ]] || { echo "bundle_tar: no $out/$f" >&2; return 1; }
  done
  # Each step chained: set -e does nothing here when the caller tests the
  # status (bundle_tar ... || die), so a failed tar would go on to the rename
  (
    set -euo pipefail
    cd "$out" &&
    rm -f "$name.tar.new" "$name.tar.sha256.new" &&
    LC_ALL=C tar --format=gnu --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
      --mode='u+rw,go-w,a+rX,a-st' --hard-dereference -cf "$name.tar.new" -T - <<<"$members" &&
    mv -f "$name.tar.new" "$name.tar" &&
    sum=$(sha256sum < "$name.tar" | cut -d' ' -f1) &&
    printf '%s  %s\n' "$sum" "$name.tar" > "$name.tar.sha256.new" &&
    mv -f "$name.tar.sha256.new" "$name.tar.sha256"
  )
}
