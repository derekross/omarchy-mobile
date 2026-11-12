# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# A package directory as a tar stream for building somewhere without the git
# history (the build container, the phone): the directory as it is
# (including gitignored prebuilt files the PKGBUILDs install), minus
# makepkg's work directories and old packages, plus .pkgver with the version
# tools/pkg-version works out here, for PKGBUILDs that ask it.
#
#   source tools/lib/pkg-tar.sh
#   pkg_tar packages/<name> | tar xf - -C DEST
#
# Returns non-zero, writing nothing, when the version can't be worked out
# (a shallow clone, no .git): a build must not guess it.
pkg_tar() {
  local dir=${1%/} name tmp v='' extra=()
  name=$(basename "$dir")
  if grep -qF 'tools/pkg-version' "$dir/PKGBUILD"; then
    v=$("$(dirname -- "${BASH_SOURCE[0]}")/../pkg-version" "$dir") || return 1
  fi
  tmp=$(mktemp -d)
  mkdir "$tmp/$name"
  if [[ -n $v ]]; then
    echo "$v" > "$tmp/$name/.pkgver"
    extra=(-C "$tmp" "./$name/.pkgver")
  fi
  # Appended last, so it wins over a stale .pkgver in the directory.
  tar cf - --exclude="./$name/pkg" --exclude="./$name/src/build" --exclude='*.pkg.tar.*' \
    -C "$(dirname "$dir")" "./$name" "${extra[@]}"
  local rc=$?
  rm -rf "$tmp"
  return $rc
}
