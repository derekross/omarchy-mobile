# SPDX-License-Identifier: MIT
# Shared by the stand-in extraction tools (test/fake-tools): they write
# small made-up trees shaped like the real tools' outputs, and fail, stall
# or lie on request. $OMAMOBILE_PROVISION_FAKE_DIR holds the requests:
#   fail-NAME     a number: NAME fails that many more times
#   stall-NAME    NAME sleeps (for the test that interrupts a run)
#   lie-NAME      NAME writes a MANIFEST that doesn't match its tree
# and gets uid-NAME, the user each tool ran as. The image's generation
# (generation.txt in the zip, stored: gen1, gen2) goes into every file.
set -euo pipefail
umask 022
F=${OMAMOBILE_PROVISION_FAKE_DIR:?}
fake_start() { # NAME SRC
  id -u > "$F/uid-$1" 2>/dev/null || true
  if [[ -f $F/stall-$1 ]]; then : > "$F/stalled-$1"; sleep 60; fi
  if [[ -f $F/fail-$1 ]]; then
    n=$(<"$F/fail-$1")
    if ((n > 0)); then echo $((n - 1)) > "$F/fail-$1"; echo "stand-in $1: asked to fail" >&2; exit 1; fi
  fi
  # the test's image zip stores generation.txt uncompressed
  [[ -z ${2:-} ]] || GEN=$(grep -ao 'gen[0-9][0-9]*' "$2" | sed -n 1p)
}
manifest() { # OUT
  (cd "$1/root" && find . -type f -printf '%m %P\n' | LC_ALL=C sort -k2 |
    while read -r mode path; do printf '%s %s %s\n' "$(sha256sum "$path" | cut -d' ' -f1)" "$mode" "$path"; done) > "$1/MANIFEST"
}
chroot_tree() { # OUT NAME
  local r=$1/root
  rm -rf "$r"
  mkdir -p "$r/vendor/bin" "$r/vendor/etc" "$r/system/lib64" "$r/apex/com.android.runtime/lib64/bionic"
  echo "$2 daemon $GEN" > "$r/vendor/bin/$2-daemon"; chmod 755 "$r/vendor/bin/$2-daemon"
  echo "$2 conf $GEN" > "$r/vendor/etc/$2.conf"
  echo "only in $GEN" > "$r/vendor/etc/only-$GEN.conf"
  echo "libc $GEN" > "$r/apex/com.android.runtime/lib64/bionic/libc.so"
  ln -s /apex/com.android.runtime/lib64/bionic/libc.so "$r/system/lib64/libc.so"
  chmod 750 "$r/vendor/etc"
  manifest "$1"
  [[ ! -f $F/lie-$2 ]] || sed -i "1s/^[0-9a-f]\\{64\\}/$(printf '0%.0s' {1..64})/" "$1/MANIFEST"
  echo "fictional/cheetah/$GEN" > "$1/SOURCE"
}
